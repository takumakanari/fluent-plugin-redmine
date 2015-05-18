require "helper"
require "webrick"
require "thread"
require "net/http"
require "uri"
require "fluent/plugin/out_redmine"


class RedmineOutputTest < Test::Unit::TestCase

  CONFIG_DEFAULT = %[
    type redmine
    url http://localhost:4000
    api_key test-api-key
    tag_key test
    project_id 1
    tracker_id 2
    priority_id 3
    category_id 4
    subject awesome
    description this is description %{d1} - %{d2} - %{d3}
  ]

  CONFIG_WITH_PROPERTY_ALIAS_KEYS = %[
    type redmine
    url http://localhost:4000
    api_key test-api-key
    tag_key test
    project_id 1
    tracker_id 2
    priority_id 3
    category_id 4
    priority_id_key key_of_priority_id
    category_id_key key_of_category_id
    subject awesome
    description this is description %{d1} - %{d2} - %{d3}
  ]

  CONFIG_HTTPS = %[
    type redmine
    url https://localhost:4000
    api_key test-api-key
    tag_key test
    project_id 1
    tracker_id 2
    priority_id 3
    subject awesome
    description this is description %{d1} - %{d2} - %{d3}
  ]

  CONFIG_TO_FORMAT = %[
    type redmine
    url http://localhost:4000
    api_key test-api-key
    project_id 1
    tracker_id 2
    priority_id 3
    subject %{tag}: awesome %{name}, %{age}, %{message}, unknown:%{unknown}
    description %{tag}: this is description %{name}, %{age}, %{message}, unknown:%{unknown}
  ]

  def setup
    Fluent::Test.setup
    boot_dummy_redmine_server
  end

  def boot_dummy_redmine_server
    @tickets = []
    @dummy_redmine = Thread.new do
      s = WEBrick::HTTPServer.new({
        :BindAddress => "127.0.0.1",
        :Port => 4000,
        :DoNotReverseLookup => true
      })
      begin
        s.mount_proc("/") do |req, res|
          unless req.request_method == "POST"
            res.status = 405
            res.body = "request method mismatch"
            next
          end
          if req.path == "/"
            res.status = 200
          elsif req.path == "/issues.json"
            @tickets << JSON.parse(req.body)
            res.status = 201
          else
            res.status = 404
            next
          end
          res.body = "OK"
        end
        s.start
      ensure
        s.shutdown
      end
    end

    cv = ConditionVariable.new

    watcher = Thread.new {
      connected = false
      while not connected
        begin
          client = Net::HTTP.start("localhost", 4000)
          connected = client.request_post("/", "").code.to_i == 200
          puts connected
        rescue Errno::ECONNREFUSED
          sleep 0.1
        rescue StandardError => e
          p e
          sleep 0.1
        end
      end
      cv.signal
    }
    mutex = Mutex.new
    mutex.synchronize {
      cv.wait(mutex)
    }
  end

  def teardown
    @dummy_redmine.kill
    @dummy_redmine.join
  end

  def create_driver(conf=CONFIG_OUT_KEYS,tag='test')
    Fluent::Test::OutputTestDriver.new(Fluent::RedmineOutput, tag).configure(conf)
  end

  def test_configure_http
    p = nil
    assert_nothing_raised { p = create_driver(CONFIG_DEFAULT).instance }
    assert_equal "http://localhost:4000", p.url
    assert_equal "test", p.tag_key
    assert_equal "1", p.project_id
    assert_equal 2, p.tracker_id
    assert_equal 3, p.priority_id
    assert_equal 4, p.category_id
    assert_equal "awesome", p.subject
    assert_equal "this is description %{d1} - %{d2} - %{d3}", p.description
    assert_nil p.priority_id_key
    assert_nil p.category_id_key
  end

  def test_configure_property_alias_keys
    p = nil
    assert_nothing_raised { p = create_driver(CONFIG_WITH_PROPERTY_ALIAS_KEYS).instance }
    assert_equal "key_of_priority_id", p.priority_id_key
    assert_equal "key_of_category_id", p.category_id_key
  end

  def test_configure_https
    p = nil
    assert_nothing_raised { p = create_driver(CONFIG_HTTPS).instance }
    assert_equal "https://localhost:4000", p.url
    assert_equal "test", p.tag_key
    assert_equal "1", p.project_id
    assert_equal 2, p.tracker_id
    assert_equal 3, p.priority_id
    assert_equal "awesome", p.subject
    assert_equal "this is description %{d1} - %{d2} - %{d3}", p.description
  end

  def test_configure_fail_by_url
    assert_raise(Fluent::ConfigError){ create_driver(<<CONFIG) }
  type redmine
  api_key test-api-key
  project_id 1
  tracker_id 2
  priority_id 3
  subject awesome
  description this is description
CONFIG
  end

  def test_configure_fail_by_api_key
    assert_raise(Fluent::ConfigError){ create_driver(<<CONFIG) }
  type redmine
  url http://localhost:4000
  project_id 1
  tracker_id 2
  priority_id 3
  subject awesome
  description this is description
CONFIG
  end

  def test_make_payload
    p = create_driver(CONFIG_DEFAULT).instance
    record = {
      "name" => "John",
      "age" => 25,
      "message" => "this is message!"
    }
    ret = p.make_payload("subject", "description", record)
    assert_equal "subject", ret[:issue][:subject]
    assert_equal "description", ret[:issue][:description]
    assert_equal p.project_id, ret[:issue][:project_id]
    assert_equal p.tracker_id, ret[:issue][:tracker_id]
    assert_equal p.priority_id, ret[:issue][:priority_id]
  end

  def test_make_payload_with_alias_keys
    p = create_driver(CONFIG_WITH_PROPERTY_ALIAS_KEYS).instance
    record = {
      "key_of_priority_id" => "123",
      "key_of_category_id" => "456"
    }
    ret = p.make_payload("subject", "description", record)
    assert_equal 123, ret[:issue][:priority_id]
    assert_equal 456, ret[:issue][:category_id]
  end

  def test_make_payload_with_alias_keys_use_default_ids
    p = create_driver(CONFIG_WITH_PROPERTY_ALIAS_KEYS).instance
    ret = p.make_payload("subject", "description", {})
    assert_equal 3, ret[:issue][:priority_id]
    assert_equal 4, ret[:issue][:category_id]
  end

  def test_emit
    d = create_driver(CONFIG_TO_FORMAT)
    record = {
      "name" => "John",
      "age" => 25,
      "message" => "this is message!"
    }
    t = Time.now
    d.run do
      d.emit(record, t.to_i)
    end

    assert_equal @tickets.size, 1

    issue = @tickets.first["issue"]

    assert_equal "1", issue["project_id"]
    assert_equal 2, issue["tracker_id"]
    assert_equal 3, issue["priority_id"]
    assert_equal "test: awesome John, 25, this is message!, unknown:", issue["subject"]
    assert_equal "test: this is description John, 25, this is message!, unknown:", issue["description"]
  end

end

