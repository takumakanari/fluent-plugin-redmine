require "json"
require "net/http"

module Fluent

  class RedmineOutput < BufferedOutput
    Fluent::Plugin.register_output('redmine', self)

    desc "Redmine url"
    config_param :url, :string

    desc "Redmine api key"
    config_param :api_key, :string, secret: true

    desc "Key name in the record for tag"
    config_param :tag_key, :string, default: "tag"

    desc "Redmine project id"
    config_param :project_id, :string, default: nil

    desc "Redmine category id"
    config_param :category_id, :integer, default: nil

    desc "Key name in the record for Redmine category id"
    config_param :category_id_key, :string, default: nil

    desc "Redmine tracker id"
    config_param :tracker_id, :integer, default: nil

    desc "Redmine priority id"
    config_param :priority_id, :integer, default: nil

    desc "Key name in the record for Redmine priority id"
    config_param :priority_id_key, :string, default: nil

    desc "Ticket title"
    config_param :subject, :string, default: "Fluent::RedmineOutput plugin"

    desc "Ticket description"
    config_param :description, :string, default: ""

    desc "If true, show debug message of http operations"
    config_param :debug_http, :bool, default: false

    desc "Redmine custom fields, array of hash with id, value"
    config_param :custom_fields, :array, default: []

    desc "Key name in the record for Redmine custom fields"
    config_param :custom_fields_key, :string, default: nil

    def configure(conf)
      super

      @use_ssl = (@url =~ /^https:/) ? true : false

      @subject_expander = TemplateExpander.new(@subject)
      @description_expander = TemplateExpander.new(@description)
      @redmine_uri = URI.parse("#{@url}/issues.json")

      @redmine_request_header = {
        "Content-Type" => "application/json",
        "X-Redmine-API-Key" => @api_key
      }
    end

    def format(tag, time, record)
      [tag, time, record].to_msgpack
    end

    def write(chunk)
      chunk.msgpack_each do |tag, time, record|
        subject = @subject_expander.bind(make_record(tag, record))
        desc = @description_expander.bind(make_record(tag, record))
        begin
          submit_ticket(subject, desc, record)
        rescue => e
          log.error "out_redmine: failed to create ticket to #{@redmine_uri}, subject: #{subject}, description: #{desc}, error_class: #{e.class}, error_message: #{e.message}, error_backtrace: #{e.backtrace.first}"
          raise e
        end
      end
    end

    def submit_ticket(subject, desc, record)
      request = Net::HTTP::Post.new(
        @redmine_uri.request_uri,
        initheader = @redmine_request_header
      )
      request.body = JSON.generate(make_payload(subject, desc, record))

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

    def make_payload(subject, desc, record)
      priority_id = @priority_id_key.nil? ? @priority_id : (record[@priority_id_key] || @priority_id).to_i
      category_id = @category_id_key.nil? ? @category_id : (record[@category_id_key] || @category_id).to_i
      custom_fields = @custom_fields_key.nil? ? @custom_fields : (record[@custom_fields_key] || [])
      issue = {
        project_id: @project_id,
        category_id: category_id,
        subject: subject,
        description: desc
      }
      issue[:tracker_id] = @tracker_id unless @tracker_id.nil?
      issue[:priority_id] = priority_id unless priority_id.nil?
      issue[:custom_fields] = custom_fields unless custom_fields.empty?
      { issue: issue }
    end

    private

    def make_record(tag, record)
      dest = {}
      dest[:"#{@tag_key}"] = tag
      record.map do |key, value|
        dest[:"#{key}"] = value
      end
      dest
    end

    class TemplateExpander
      attr_reader :template, :placeholders

      EMPTY = ''

      def initialize(template)
        @template = template
        @placeholders = []
        @template.gsub(/%{([^}]+)}/) do
          @placeholders << $1 unless @placeholders.include?($1)
        end
      end

      def bind(values)
        @placeholders.each do |key|
          key_ = :"#{key}"
          values[key_] = EMPTY unless values.key?(key_)
        end
        @template % values
      end
    end

  end

end
