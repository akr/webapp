require 'test/unit'
require 'webapp'

class WebApPTest < Test::Unit::TestCase
  def unescape(s)
    s.gsub(/%([0-9a-f][0-9a-f])/i) { [$1].pack("H2") }
  end

  def new
    self
  end

  def webapp_test(method, uri, content='', &block)
    uri = URI.parse(uri)
    env = {}
    env['REQUEST_METHOD'] = method
    env['SERVER_NAME'] = uri.host
    env['SERVER_PORT'] = uri.port
    %r{\.cgi(?:\z|(?=/))} =~ uri.path
    env['SCRIPT_NAME'] = unescape($` + $&)
    env['PATH_INFO'] = unescape($')
    env['QUERY_STRING'] = uri.query
    env['SERVER_PROTOCOL'] = 'HTTP/1.0'
    env['REMOTE_ADDR'] = '127.0.0.1'
    env['CONTENT_TYPE'] = content
    exc = nil
    manager = WebApp::Manager.new(self, lambda {|webapp|
      begin
        block.call(webapp)
      rescue Exception
        exc = $!
      end
    })
    setup_request = lambda {|req|
      req.make_request_header_from_cgi_env(env)
      req.body_object << content
    }
    response = nil
    output_response = lambda {|res|
      response = res
    }
    manager.primitive_run(setup_request, output_response)
    raise exc if exc
    response
  end

  def test_webapp
    webapp_test('GET', 'http://host/foo/b%61r.cgi/b%61z?hoge=fug%61') {|webapp|
      assert_equal('host', webapp.server_name)
      assert_equal(80, webapp.server_port)
      assert_equal('/foo/bar.cgi', webapp.script_name)
      assert_equal('/baz', webapp.path_info)
      assert_equal('hoge=fug%61',
        webapp.query_string.instance_eval { @escaped_query_string })
    }
  end

  def test_redirect
    res = webapp_test('GET', 'http://host/script.cgi') {|webapp|
      webapp.setup_redirection 301, 'http://www.ruby-lang.org/'
    }
    assert_equal('301 Moved Permanently', res.status_line)
    assert_equal('http://www.ruby-lang.org/', res.header_object['Location'])
  end

  def test_content_type
    f = lambda {|expected, content|
      res = webapp_test('GET', 'http://host/script.cgi') {|webapp|
        webapp << content
      }
      assert_equal(expected, res.header_object['Content-Type'])
    }
    f.call(nil, '')
    f.call('text/html', '<html></html>')
    f.call('text/html; charset="euc-jp"', '<?xml version="1.0" encoding="euc-jp"?><html>')
  end

  def test_resource_path
    webapp_test('GET', 'http://host/script.cgi') {|webapp|
      assert_raise(ArgumentError) { webapp.resource_path('/etc/passwd') }
      assert_raise(ArgumentError) { webapp.resource_path('../../etc/passwd') }
    }
  end

end
