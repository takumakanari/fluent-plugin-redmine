module Fluent

  class RedmineOutput < Output
    Fluent::Plugin.register_output('redmine', self)

    # Define `log` method for v0.10.42 or earlier
    unless method_defined?(:log)
      define_method("log") { $log }
    end

    config_param :url, :string, :default => nil
    config_param :api_key, :string, :default => nil
    config_param :tag_key, :string, :default => "tag"
    config_param :project_id, :string, :default => nil
    config_param :tracker_id, :integer
    config_param :priority_id, :integer
    config_param :subject, :string, :default => "Fluent::RedmineOutput plugin"
    config_param :description, :string, :default => ""
    config_param :debug_http, :bool, :default => false

    def initialize
      super
      require "json"
    end

    def configure(conf)
      super

      if @url.nil?
        raise Fluent::ConfigError, "'url' must be specified."
      end

      if @api_key.nil?
        raise Fluent::ConfigError, "'api_key' must be specified."
      end

      @use_ssl = (@url =~ /^https:/) ? true : false

      if @use_ssl
        require "net/https"
      else
        require "net/http"
      end

      @subject_expander = TemplateExpander.new(@subject)
      @description_expander = TemplateExpander.new(@description)
      @redmine_uri = URI.parse("#{@url}/issues.json")

      @redmine_request_header = {
        "Content-Type" => "application/json",
        "X-Redmine-API-Key" => @api_key
      }
    end

    def emit(tag, es, chain)
      bulk = []
      es.each do |time,record|
        bulk << [
          @subject_expander.bind(make_record(tag, record)),
          @description_expander.bind(make_record(tag, record))
        ]
      end
      bulk.each do |subject, desc|
        begin
          submit_ticket(subject, desc)
        rescue => e
          log.warn "out_redmine: failed to create ticket to #{@redmine_uri}, subject: #{subject}, description: #{desc}, error_class: #{e.class}, error_message: #{e.message}, error_backtrace: #{e.backtrace.first}"
        end
      end
      chain.next
    end

    def submit_ticket(subject, desc)
      request = Net::HTTP::Post.new(
        @redmine_uri.request_uri,
        initheader = @redmine_request_header
      )
      request.body = JSON.generate(make_payload(subject, desc))

      client = Net::HTTP.new(@redmine_uri.host, @redmine_uri.port)
      if @use_ssl
        client.use_ssl = true
        client.verify_mode = OpenSSL::SSL::VERIFY_NONE # TODO support other verify mode
      end
      if @debug_http
        client.set_debug_output($stderr)
      end

      client.start do |http|
        res = http.request(request)
        unless res.code.to_i == 201
          raise Exception.new("Error: #{res.code}, #{res.body}")
        end
        return res.body
      end
    end

    def make_payload(subject, desc)
      {
        :issue => {
          :project_id => @project_id,
          :tracker_id => @tracker_id,
          :priority_id => @priority_id,
          :subject => subject,
          :description => desc
        }
      }
    end

    private

    def make_record(tag, record)
      dest = Hash.new
      dest[:"#{@tag_key}"] = tag
      record.map do |key, value|
        dest[:"#{key}"] = value
      end
      dest
    end

    class TemplateExpander
      attr_reader :template, :placeholders

      Empty = ''

      def initialize(template)
        @template = template
        @placeholders = Array.new
        @template.gsub(/%{([^}]+)}/) do
          @placeholders << $1 unless @placeholders.include?($1)
        end
      end

      def bind(values)
        @placeholders.each do |key|
          key_ = :"#{key}"
          values[key_] = Empty unless values.key?(key_)
        end
        @template % values
      end
    end

  end

end
