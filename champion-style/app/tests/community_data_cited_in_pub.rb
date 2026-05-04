# fair_tests/community_data_cited_in_pub.rb

class FAIRTest
  OPENALEX_BASE = 'https://api.openalex.org'
  OC_INDEX_BASE = 'https://opencitations.net/index/api/v2'
  MAILTO        = ENV.fetch('OPENALEX_MAILTO', 'anonymous@example.com')

  CitationResult = Struct.new(
    :doi,
    :openalex_id,
    :fulltext_citations,
    :reference_citations,
    :opencitations,
    :errors,
    keyword_init: true
  ) do
    def any_citations?
      [fulltext_citations, reference_citations, opencitations].any? { |c| c&.any? }
    end

    def total_count
      (fulltext_citations&.length || 0) +
        (reference_citations&.length || 0) +
        (opencitations&.length || 0)
    end
  end

  def self.community_data_cited_in_pub_meta
    {
      testversion: HARVESTER_VERSION + ':' + 'Tst-0.0.2',
      testname: 'FAIR Test - R1.2 - Dataset - The dataset is cited in a publication',
      testid: 'community_data_cited_in_pub',
      description: '## What is being measured?

This Test evaluates whether the research object provided by the supplied DOI has been formally recognised and cited within the scholarly literature. The assessment uses the DOI to query global citation indexes and aggregation services, such as OpenAlex (searching both full-text data availability sections and reference lists) and OpenCitations. The metric passes if the dataset identifier is found within the citation network of at least one external publication (in the reference section or in text).

## Why should we measure it?

Under FAIR Principle R1.2, metadata must be associated with detailed provenance to support its evaluation and reuse. Formal citation in a peer-reviewed publication is a robust indicator of a research object’s provenance.',
      metric: 'https://w3id.org/fair-metrics/esrf/FM_R1.2_D_CITED-BY-PUB_ESRF',
      indicators: 'https://doi.org/10.25504/FAIRsharing.3e9860',
      type: 'http://edamontology.org/operation_2428',
      license: 'https://creativecommons.org/publicdomain/zero/1.0/',
      keywords: ['FAIR Assessment', 'FAIR Principles'],
      themes: ['http://edamontology.org/topic_4012'],
      organization: 'OSTrails Project',
      org_url: 'https://ostrails.eu/',
      responsible_developer: 'Mark D Wilkinson',
      email: 'mark.wilkinson@upm.es',
      response_description: 'The response is "pass", "fail" or "indeterminate"',
      schemas: { 'subject' => ['string', 'the GUID being tested'] },
      organizations: [{ 'name' => 'OSTrails Project', 'url' => 'https://ostrails.eu/' }],
      individuals: [{ 'name' => 'Mark D Wilkinson', 'email' => 'mark.wilkinson@upm.es' }],
      creator: 'https://orcid.org/0000-0001-6960-357X',
      protocol: ENV.fetch('TEST_PROTOCOL', 'https'),
      host: ENV.fetch('TEST_HOST', 'localhost'),
      basePath: ENV.fetch('TEST_PATH', '/community-tests')
    }
  end

  def self.community_data_cited_in_pub(guid:)
    FtrRuby::Output.clear_comments
    output = FtrRuby::Output.new(
      testedGUID: guid,
      meta: community_data_cited_in_pub_meta
    )

    output.comments << "INFO: TEST VERSION '#{community_data_cited_in_pub_meta[:testversion]}'\n"

    doi    = guid.sub(%r{\Ahttps?://doi\.org/}i, '').strip
    errors = {}

    openalex_id         = fetch_openalex_id(doi, errors)
    fulltext_citations  = fetch_fulltext_citations(doi, errors)
    reference_citations = openalex_id ? fetch_reference_citations(openalex_id, errors) : []
    opencitations       = fetch_opencitations(doi, errors)

    res = CitationResult.new(
      doi: doi,
      openalex_id: openalex_id,
      fulltext_citations: fulltext_citations,
      reference_citations: reference_citations,
      opencitations: opencitations,
      errors: errors
    )

    errors.each { |key, message| output.comments << "WARN (#{key}): #{message}\n" }

    unless res.any_citations?
      output.comments << "FAIL: No citations found for #{guid} in OpenAlex or OpenCitations\n"
      output.score = 'fail'
      return output.createEvaluationResponse
    end

    output.comments << "SUCCESS: #{guid} has #{res.total_count} citation(s) " \
                       "(fulltext: #{res.fulltext_citations.length}, " \
                       "references: #{res.reference_citations.length}, " \
                       "opencitations: #{res.opencitations.length})\n"
    output.score = 'pass'
    output.createEvaluationResponse
  end

  def self.community_data_cited_in_pub_api
    api = FtrRuby::OpenAPI.new(meta: community_data_cited_in_pub_meta)
    api.get_api
  end

  def self.community_data_cited_in_pub_about
    dcat = FtrRuby::DCAT_Record.new(meta: community_data_cited_in_pub_meta)
    dcat.get_dcat
  end

  # ---------------------------------------------------------------------------
  # Step 1a — resolve the OpenAlex Work ID for this DOI
  # ---------------------------------------------------------------------------
  def self.fetch_openalex_id(doi, errors)
    url  = "#{OPENALEX_BASE}/works/doi:#{doi}"
    body = get_json(url, errors, :openalex_id_lookup)
    body&.dig('id')
  end

  # ---------------------------------------------------------------------------
  # Step 1b — full-text / data-availability search
  # ---------------------------------------------------------------------------
  def self.fetch_fulltext_citations(doi, errors)
    quoted = %("#{doi}")
    url    = "#{OPENALEX_BASE}/works?filter=fulltext.search:#{URI.encode_uri_component(quoted)}&mailto=#{MAILTO}"
    body   = get_json(url, errors, :fulltext_citations)
    body&.dig('results') || []
  end

  # ---------------------------------------------------------------------------
  # Step 2 — reference-list citations
  # ---------------------------------------------------------------------------
  def self.fetch_reference_citations(openalex_id, errors)
    short_id = openalex_id.split('/').last
    url      = "#{OPENALEX_BASE}/works?filter=cites:#{short_id}&mailto=#{MAILTO}"
    body     = get_json(url, errors, :reference_citations)
    body&.dig('results') || []
  end

  # ---------------------------------------------------------------------------
  # Step 3 — OpenCitations Index v2
  # ---------------------------------------------------------------------------
  def self.fetch_opencitations(doi, errors)
    encoded = URI.encode_uri_component("doi:#{doi.downcase}")
    url     = "#{OC_INDEX_BASE}/citations/#{encoded}"
    body    = get_json(url, errors, :opencitations)
    case body
    when Array then body
    when Hash  then body['results'] || []
    else []
    end
  end

  # ---------------------------------------------------------------------------
  # Generic HTTP GET → parsed JSON
  # ---------------------------------------------------------------------------
  def self.get_json(url, errors, key)
    uri     = URI.parse(url)
    request = Net::HTTP::Get.new(uri)
    request['Accept']     = 'application/json'
    request['User-Agent'] = "FAIRTest/1.0 (mailto:#{MAILTO})"

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                                   open_timeout: 10, read_timeout: 15) do |http|
      http.request(request)
    end

    case response.code.to_i
    when 200 then JSON.parse(response.body)
    when 404 then nil
    else
      errors[key] = "HTTP #{response.code} from #{uri.host}"
      nil
    end
  rescue JSON::ParserError => e
    errors[key] = "JSON parse error: #{e.message}"
    nil
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    errors[key] = "Timeout: #{e.message}"
    nil
  rescue StandardError => e
    errors[key] = e.message
    nil
  end
end
