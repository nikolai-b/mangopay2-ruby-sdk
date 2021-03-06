require 'net/http'
require 'cgi/util'
require 'digest/md5'
require 'multi_json'

# helpers
require 'mangopay/version'
require 'mangopay/errors'


module MangoPay

  autoload :HTTPCalls, 'mangopay/http_calls'
  autoload :Resource, 'mangopay/resource'
  autoload :Client, 'mangopay/client'
  autoload :User, 'mangopay/user'
  autoload :NaturalUser, 'mangopay/natural_user'
  autoload :LegalUser, 'mangopay/legal_user'
  autoload :PayIn, 'mangopay/pay_in'
  autoload :PayOut, 'mangopay/pay_out'
  autoload :Transfer, 'mangopay/transfer'
  autoload :Transaction, 'mangopay/transaction'
  autoload :Wallet, 'mangopay/wallet'
  autoload :BankAccount, 'mangopay/bank_account'
  autoload :CardRegistration, 'mangopay/card_registration'
  autoload :PreAuthorization, 'mangopay/pre_authorization'
  autoload :Card, 'mangopay/card'
  autoload :Event, 'mangopay/event'
  autoload :KycDocument, 'mangopay/kyc_document'
  autoload :Hook, 'mangopay/hook'
  autoload :Refund, 'mangopay/refund'
  autoload :Dispute, 'mangopay/dispute'
  autoload :Mandate, 'mangopay/mandate'
  autoload :Report, 'mangopay/report'
  autoload :JSON, 'mangopay/json'
  autoload :AuthorizationToken, 'mangopay/authorization_token'

  # temporary
  autoload :Temp, 'mangopay/temp'

  class Configuration
    attr_accessor :preproduction, :root_url,
                  :client_id, :client_passphrase,
                  :temp_dir

    def preproduction
      @preproduction || false
    end

    def root_url
      @root_url || (@preproduction == true ? "https://api.sandbox.mangopay.com" : "https://api.mangopay.com")
    end
  end

  class << self
    attr_accessor :configuration

    def version_code
      "v2.01"
    end

    def api_path
      "/#{version_code}/#{MangoPay.configuration.client_id}"
    end

    def configure
      self.configuration ||= Configuration.new
      yield configuration
    end

    def api_uri(url='')
      URI(configuration.root_url + url)
    end

    #
    # - +method+: HTTP method; lowercase symbol, e.g. :get, :post etc.
    # - +url+: the part after Configuration#root_url
    # - +params+: hash; entity data for creation, update etc.; will dump it by JSON and assign to Net::HTTPRequest#body
    # - +filters+: hash; pagination params etc.; will encode it by URI and assign to URI#query
    # - +headers_or_idempotency_key+: hash of headers; or replaced by request_headers if nil; or added to request_headers as idempotency key otherwise (see https://docs.mangopay.com/api-references/idempotency-support/)
    # - +before_request_proc+: optional proc; will call it passing the Net::HTTPRequest instance just before Net::HTTPRequest#request
    #
    # Raises MangoPay::ResponseError if response code != 200.
    #
    def request(method, url, params={}, filters={}, headers_or_idempotency_key = nil, before_request_proc = nil)
      uri = api_uri(url)
      uri.query = URI.encode_www_form(filters) unless filters.empty?

      if headers_or_idempotency_key.is_a?(Hash)
        headers = headers_or_idempotency_key
      else
        headers = request_headers
        headers['Idempotency-Key'] = headers_or_idempotency_key if headers_or_idempotency_key != nil
      end

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        req = Net::HTTP::const_get(method.capitalize).new(uri.request_uri, headers)
        req.body = JSON.dump(params)
        before_request_proc.call(req) if before_request_proc
        http.request req
      end

      # decode json data
      data = JSON.load(res.body.to_s) rescue {}

      unless res.is_a?(Net::HTTPOK)
        raise MangoPay::ResponseError.new(uri, res.code, data)
      end

      # copy pagination info if any
      ['x-number-of-pages', 'x-number-of-items'].each { |k|
        filters[k.gsub('x-number-of-', 'total_')] = res[k].to_i if res[k]
      }

      data
    end

    # Retrieve a previous response by idempotency_key
    # See https://docs.mangopay.com/api-references/idempotency-support/
    def fetch_response(idempotency_key)
      url = "#{api_path}/responses/#{idempotency_key}"
      request(:get, url)
    end

    private

    def user_agent
      {
          bindings_version: VERSION,
          lang: 'ruby',
          lang_version: "#{RUBY_VERSION} p#{RUBY_PATCHLEVEL} (#{RUBY_RELEASE_DATE})",
          platform: RUBY_PLATFORM,
          uname: get_uname
      }
    end

    def get_uname
      `uname -a 2>/dev/null`.strip if RUBY_PLATFORM =~ /linux|darwin/i
    rescue Errno::ENOMEM
      'uname lookup failed'
    end

    def request_headers
      auth_token = AuthorizationToken::Manager.get_token
      headers = {
          'user_agent' => "MangoPay V2 RubyBindings/#{VERSION}",
          'Authorization' => "#{auth_token['token_type']} #{auth_token['access_token']}",
          'Content-Type' => 'application/json'
      }
      begin
        headers.update('x_mangopay_client_user_agent' => JSON.dump(user_agent))
      rescue => e
        headers.update('x_mangopay_client_raw_user_agent' => user_agent.inspect, error: "#{e} (#{e.class})")
      end
    end

  end
end
