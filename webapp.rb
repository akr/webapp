# = webapp.rb - unified web application interface for CGI, FastCGI mod_ruby and WEBrick.
#
# == Features
#
# * very easy-to-use API.
# * works under CGI, FastCGI and mod_ruby without modification.
# * works uner WEBrick.
#   WEBrick based server must require "webapp/webrick-servlet", though.
#   link:files/webapp/webrick-servlet_rb.html
# * path_info aware relative URI generation.
# * HTML form parameter varidation by HTML form. (sample/query.cgi)
# * automatic Content-Type generation.
# * a web application can be used as a web site with WEBrick.
#   (URL will be http://host/path_info?query.
#   No path component to specify a web application.)
#   link:files/webapp/webrick-servlet_rb.html
#
# == Example
#
# Following script works as CGI(*.cgi), FastCGI(*.fcgi) and mod_ruby(*.rbx)
# without any modification.
# It also works as WEBrick servlet (*.webrick) if the WEBrick based server
# requires "webapp/webapp/webrick-servlet".
#
#   #!/path/to/ruby
#
#   require 'webapp'
#  
#   WebApp {|webapp|
#     webapp.content_type = 'text/plain'
#     webapp.puts <<"End"
#   current time: #{Time.now}
#   pid: #{$$}
#   self: #{self.inspect}
#   
#   request_method: #{webapp.request_method}
#   server_name: #{webapp.server_name}
#   server_port: #{webapp.server_port}
#   script_name: #{webapp.script_name}
#   path_info: #{webapp.path_info}
#   query_string: #{webapp.query_string}
#   server_protocol: #{webapp.server_protocol}
#   remote_addr: #{webapp.remote_addr}
#   content_type: #{webapp.content_type}
#   
#   --- request headers ---
#   End
#     webapp.each_request_header {|k, v|
#       webapp.puts "#{k}: #{v}"
#     }
#   }
#
# == recommended directory layout for web application
#
# I recommend following directory layout to develop a web application.
#
# * PROJECT/PROJECT.cgi         primary CGI
# * PROJECT/.htaccess           deny access except to *.cgi
# * PROJECT/config.yml.dist     sample configuration file
# * PROJECT/TEMPLATE.html       HTree template
# * PROJECT/PROJECT.rb          library entry file
# * PROJECT/PROJECT/SUBLIB.rb   library component
# * PROJECT/bin/COMMAND         runnable command
# * PROJECT/cgistub.erb         stub template
# * PROJECT/Makefile            stub generator
# * PROJECT/test-all.rb         test runner
# * PROJECT/test/test-XXXX.rb   unit test
#
# * PROJECT/config.yml          configuration file
# * PROJECT/cgi-bin/PROJECT.cgi stub file generated by cgistub.erb
#
# This layout is not so hierarchical.
# It is intended for ease-of-development. 
#
# Since the current directory of CGI process is initialized to
# the directry which contains the CGI script,
# PROJECT.cgi can require PROJECT.rb.
# It is because '.' is contained in a load path if ruby starts with $SAFE == 0,
# it is usual.
#

require 'stringio'
require 'forwardable'
require 'pathname'
require 'htree'
require 'webapp/urigen'
require 'webapp/message'
require 'webapp/htmlform'

class WebApp
  def initialize(manager, request, response) # :nodoc:
    @manager = manager
    @request = request
    @request_header = request.header_object
    @request_body = request.body_object
    @response = response
    @response_header = response.header_object
    @response_body = response.body_object
    @urigen = URIGen.new('http', # xxx: https?
      @request.server_name, @request.server_port,
      @request.script_name, @request.path_info)
  end

  extend Forwardable
  def_delegators :@response_body, :<<, :print, :printf, :putc, :puts, :write

  def_delegator :@request_header, :each, :each_request_header
  def_delegator :@request_header, :[], :get_request_header

  def_delegator :@request, :request_method, :request_method
  def_delegator :@request, :server_name, :server_name
  def_delegator :@request, :server_port, :server_port
  def_delegator :@request, :script_name, :script_name
  def_delegator :@request, :path_info, :path_info
  def_delegator :@request, :query_string, :query_string
  def_delegator :@request, :server_protocol, :server_protocol
  def_delegator :@request, :remote_addr, :remote_addr
  def_delegator :@request, :content_type, :request_content_type

  def_delegator :@response_header, :set, :set_header
  def_delegator :@response_header, :add, :add_header
  def_delegator :@response_header, :remove, :remove_header
  def_delegator :@response_header, :clear, :clear_header
  def_delegator :@response_header, :has?, :has_header?
  def_delegator :@response_header, :[], :get_header
  def_delegator :@response_header, :each, :each_header

  def content_type=(media_type)
    @response_header.set 'Content-Type', media_type
  end
  def content_type
    @response_header.set 'Content-Type', media_type
  end

  # returns a Pathname object.
  # _path_ is interpreted as a relative path from the directory
  # which a web application exists.
  #
  # If /home/user/public_html/foo/bar.cgi is a web application which
  # WebApp {} calls, webapp.resource_path("baz") returns a pathname points to
  # /home/user/public_html/foo/baz.
  def resource_path(arg)
    path = Pathname.new(arg)
    raise ArgumentError, "absolute path: #{arg.inspect}" if !path.relative?
    path.each_filename {|f|
      raise ArgumentError, "path contains .. : #{arg.inspect}" if f == '..'
    }
    @manager.resource_basedir + path
  end

  # call-seq:
  #   open_resource(path)
  #   open_resource(path) {|io| ... }
  #
  # opens _path_ as relative from a web application directory.
  def open_resource(path, &block) 
    resource_path(path).open(&block)
  end

  # call-seq:
  #   reluri(:script=>string, :path_info=>string, :query=>query, :fragment=>string) -> URI
  #   make_relative_uri(:script=>string, :path_info=>string, :query=>query, :fragment=>string) -> URI
  # 
  # make_relative_uri returns a relative URI which base URI is the URI the
  # web application is invoked.
  #
  # The argument should be a hash which may have following components.
  # - :script specifies script_name relative from the directory containing
  #   the web application script.
  #   If it is not specified, the web application itself is assumed.
  # - :path_info specifies path_info component for calling web application.
  #   It should begin with a slash.
  #   If it is not specified, "" is assumed.
  # - :query specifies query a component.
  #   It should be a Hash or a WebApp::QueryString.
  # - :fragment specifies a fragment identifier.
  #   If it is not specified, a fragment identifier is not appended to
  #   the result URL.
  #
  # Since the method escapes the components properly,
  # you should specify them in unescaped form.
  #
  # In the example follow, assume that the web application bar.cgi is invoked
  # as http://host/foo/bar.cgi/baz/qux.
  #
  #   webapp.reluri(:path_info=>"/hoge") => URI("../hoge")
  #   webapp.reluri(:path_info=>"/baz/fuga") => URI("fuga"
  #   webapp.reluri(:path_info=>"/baz/") => URI("./")
  #   webapp.reluri(:path_info=>"/") => URI("../")
  #   webapp.reluri() => URI("../../bar.cgi")
  #   webapp.reluri(:script=>"funyo.cgi") => URI("../../funyo.cgi")
  #   webapp.reluri(:script=>"punyo/gunyo.cgi") => URI("../../punyo/gunyo.cgi")
  #   webapp.reluri(:script=>"../genyo.cgi") => URI("../../../genyo.cgi")
  #   webapp.reluri(:fragment=>"sec1") => URI("../../bar.cgi#sec1")
  #)
  #   webapp.reluri(:path_info=>"/h?#o/x y") => URI("../h%3F%23o/x%20y")
  #   webapp.reluri(:script=>"ho%o.cgi") => URI("../../ho%25o.cgi")
  #   webapp.reluri(:fragment=>"sp ce") => URI("../../bar.cgi#sp%20ce")
  #
  def make_relative_uri(hash={})
    @urigen.make_relative_uri(hash)
  end
  alias reluri make_relative_uri

  # call-seq:
  #   make_absolute_uri(:script=>string, :path_info=>string, :query=>query, :fragment=>string) -> URI
  # 
  # make_absolute_uri returns a absolute URI which base URI is the URI of the
  # web application is invoked.
  #
  # The argument is same as make_relative_uri.
  def make_absolute_uri(hash={})
    @urigen.make_absolute_uri(hash)
  end

  # :stopdoc:
  StatusMessage = { # RFC 2616
    100 => 'Continue',
    101 => 'Switching Protocols',
    200 => 'OK',
    201 => 'Created',
    202 => 'Accepted',
    203 => 'Non-Authoritative Information',
    204 => 'No Content',
    205 => 'Reset Content',
    206 => 'Partial Content',
    300 => 'Multiple Choices',
    301 => 'Moved Permanently',
    302 => 'Found',
    303 => 'See Other',
    304 => 'Not Modified',
    305 => 'Use Proxy',
    307 => 'Temporary Redirect',
    400 => 'Bad Request',
    401 => 'Unauthorized',
    402 => 'Payment Required',
    403 => 'Forbidden',
    404 => 'Not Found',
    405 => 'Method Not Allowed',
    406 => 'Not Acceptable',
    407 => 'Proxy Authentication Required',
    408 => 'Request Timeout',
    409 => 'Conflict',
    410 => 'Gone',
    411 => 'Length Required',
    412 => 'Precondition Failed',
    413 => 'Request Entity Too Large',
    414 => 'Request-URI Too Long',
    415 => 'Unsupported Media Type',
    416 => 'Requested Range Not Satisfiable',
    417 => 'Expectation Failed',
    500 => 'Internal Server Error',
    501 => 'Not Implemented',
    502 => 'Bad Gateway',
    503 => 'Service Unavailable',
    504 => 'Gateway Timeout',
    505 => 'HTTP Version Not Supported',
  }
  # :startdoc:

  # setup_redirect makes a status line and a Location header appropriate as
  # redirection.
  #
  # _status_ specifies the status line.
  # It should be a Fixnum 3xx or String '3xx ...'.
  #
  # _uri_ specifies the Location header body.
  # It should be a URI, String or Hash.
  # If a Hash is given, make_absolute_uri is called to convert to URI.
  # If given URI is relative, it is converted as absolute URI.
  def setup_redirection(status, uri)
    case status
    when Fixnum
      if status < 300 || 400 <= status
        raise ArgumentError, "unexpected status: #{status.inspect}"
      end
      status = "#{status} #{StatusMessage[status]}"
    when String
      unless /\A3\d\d(\z| )/ =~ status
        raise ArgumentError, "unexpected status: #{status.inspect}"
      end
      if status.length == 3
        status = "#{status} #{StatusMessage[status.to_i]}"
      end
    else
      raise ArgumentError, "unexpected status: #{status.inspect}"
    end
    case uri
    when URI
      uri = @urigen.base_uri + uri if uri.relative?
    when String
      uri = URI.parse(uri)
      uri = @urigen.base_uri + uri if uri.relative?
    when Hash
      uri = make_absolute_uri(uri)
    else
      raise ArgumentError, "unexpected uri: #{uri.inspect}"
    end
    @response.status_line = status
    @response_header.set 'Location', uri.to_s
  end

  def query_html_get_application_x_www_form_urlencoded
    @request.query_string.decode_as_application_x_www_form_urlencoded
  end

  def query_html_post_application_x_www_form_urlencoded
    if /\Apost\z/i =~ @request.request_method # xxx: should be checkless?
      q = QueryString.primitive_new_for_raw_query_string(@request.body_object.read)
      q.decode_as_application_x_www_form_urlencoded
    else
      # xxx: warning?
      HTMLFormQuery.new
    end
  end

  class QueryValidationFailure < StandardError
  end
  def validate_html_query(form, form_id=nil)
    HTMLFormValidator.new(form, form_id).validate(self)
  end

  # QueryString represents a query component of URI.
  class QueryString
    class << self
      alias primitive_new_for_raw_query_string new
      undef new
    end

    def initialize(escaped_query_string)
      @escaped_query_string = escaped_query_string
    end

    def inspect
      "#<#{self.class}: #{@escaped_query_string}>"
    end
  end

  # :stopdoc:
  def WebApp.make_frozen_string(str)
    raise ArgumentError, "not a string: #{str.inspect}" unless str.respond_to? :to_str
    str = str.to_str
    str = str.dup.freeze unless str.frozen?
    str
  end

  LoadedWebAppProcedures = {}
  def WebApp.load_webapp_procedure(path)
    unless LoadedWebAppProcedures[path]
      begin
        Thread.current[:webapp_delay] = true
        load path, true
        LoadedWebAppProcedures[path] = Thread.current[:webapp_proc]
      ensure
        Thread.current[:webapp_delay] = nil
        Thread.current[:webapp_proc] = nil
      end
    end
    unless LoadedWebAppProcedures[path]
      raise RuntimeError, "not a web application: #{path}"
    end
    LoadedWebAppProcedures[path]
  end

  def WebApp.run_webapp_via_stub(path)
    if Thread.current[:webrick_load_servlet]
      load path, true
      return
    end
    WebApp.load_webapp_procedure(path).call
  end

  class Manager
    def initialize(app_class, app_block)
      @app_class = app_class
      @app_block = app_block
      @resource_basedir = Pathname.new(eval("__FILE__", app_block)).dirname
    end
    attr_reader :resource_basedir

    # CGI, Esehttpd
    def run_cgi
      setup_request = lambda {|req|
        req.make_request_header_from_cgi_env(ENV)
        if ENV.include?('CONTENT_LENGTH')
          len = ENV['CONTENT_LENGTH'].to_i
          req.body_object << $stdin.read(len)
        end
      }
      output_response = lambda {|res|
        res.output_cgi_status_field($stdout)
        res.output_message($stdout)
      }
      primitive_run(setup_request, output_response)
    end

    # FastCGI
    def run_fcgi
      require 'fcgi'
      FCGI.each_request {|fcgi_request|
        setup_request = lambda {|req|
          req.make_request_header_from_cgi_env(fcgi_request.env)
          if content = fcgi_request.in.read
            req.body_object << content
          end
        }
        output_response =  lambda {|res|
          res.output_cgi_status_field(fcgi_request.out)
          res.output_message(fcgi_request.out)
          fcgi_request.finish
        }
        primitive_run(setup_request, output_response)
      }
    end

    # mod_ruby with Apache::RubyRun
    def run_rbx
      rbx_request = Apache.request
      setup_request = lambda {|req|
        req.make_request_header_from_cgi_env(rbx_request.subprocess_env)
        if content = rbx_request.read
          req.body_object << content
        end
      }
      output_response =  lambda {|res|
        rbx_request.status_line = "#{res.status_line}"
        res.header_object.each {|k, v|
          case k
          when /\AContent-Type\z/i
            rbx_request.content_type = v
          else
            rbx_request.headers_out[k] = v
          end
        }
        rbx_request.write res.body_object.string
      }
      primitive_run(setup_request, output_response)
    end

    # WEBrick with webapp/webrick-servlet.rb
    def run_webrick
      Thread.current[:webrick_load_servlet] = lambda {|webrick_req, webrick_res|
        setup_request = lambda {|req|
          req.make_request_header_from_cgi_env(webrick_req.meta_vars)
          webrick_req.body {|chunk|
            req.body_object << chunk
          }
        }
        output_response =  lambda {|res|
          webrick_res.status = res.status_line.to_i
          res.header_object.each {|k, v|
            webrick_res[k] = v
          }
          webrick_res.body = res.body_object.string
        }
        primitive_run(setup_request, output_response)
      }
    end

    def primitive_run(setup_request, output_response)
      req = Request.new
      res = Response.new
      trap_exception(req, res) {
        setup_request.call(req)
        req.freeze
        req.body_object.rewind
        webapp = WebApp.new(self, req, res)
        app = @app_class.new
        if RUBY_RELEASE_DATE <= "2004-09-13" # xxx: avoid core dump [ruby-dev:24228]
          warn 'self in WebApp block is not replaced.'
          @app_block.call(webapp)
          complete_response(res)
          next
        end
        if @app_block
          class << app; self end.__send__(:define_method, :webapp_main, &@app_block)
        end
        app.webapp_main(webapp)
        complete_response(res)
      }
      output_response.call(res)
    end

    def complete_response(res)
      unless res.header_object.has? 'Content-Type'
        case res.body_object.string
        when /\A\z/
          content_type = nil
        when /\A\211PNG\r\n\032\n/
          content_type = 'image/png'
        when /\A#{HTree::Pat::XmlDecl_C}\s*#{HTree::Pat::DocType_C}/io
          charset = $3 || $4
          rootelem = $7
          content_type = make_xml_content_type(rootelem, charset)
        when /\A#{HTree::Pat::XmlDecl_C}\s*<(#{HTree::Pat::Name})[\s>]/io
          charset = $3 || $4
          rootelem = $7
          content_type = make_xml_content_type(rootelem, charset)
        when /\A<html[\s>]/io
          content_type = 'text/html'
        when /\0/
          content_type = 'application/octet-stream'
        else
          content_type = 'text/plain'
        end
        res.header_object.set 'Content-Type', content_type if content_type
      end
      unless res.header_object.has? 'Content-Length'
        res.header_object.set 'Content-Length', res.body_object.length.to_s
      end
    end

    def make_xml_content_type(rootelem, charset)
      case rootelem
      when /\Ahtml\z/i
        result = 'text/html'
      else
        result = 'application/xml'
      end
      result << "; charset=\"#{charset}\"" if charset
      result
    end

    def trap_exception(req, res)
      begin
        yield
      rescue Exception => e
        if localhost? req.remote_addr # xxx: accept devlopper's addresses if specified.
          generate_debug_page(req, res, e)
        else
          generate_error_page(req, res, e)
        end
      end
    end

    def localhost?(addr)
      addr == '127.0.0.1'
    end

    def generate_error_page(req, res, exc)
      backtrace = "#{exc.message} (#{exc.class})\n"
      exc.backtrace.each {|f| backtrace << f << "\n" }
      $stderr.puts backtrace
      res.status_line = '500 Internal Server Error'
      header = res.header_object
      header.clear
      header.add 'Content-Type', 'text/html'
      body = res.body_object
      body.rewind
      body.truncate(0)
      body.puts <<'End'
<html><head><title>500 Internal Server Error</title></head>
<body><h1>500 Internal Server Error</h1>
<p>The dynamic page you requested is failed to generate.</p></body>
End
    end

    def generate_debug_page(req, res, exc)
      backtrace = "#{exc.message} (#{exc.class})\n"
      exc.backtrace.each {|f| backtrace << f << "\n" }
      res.status_line = '500 Internal Server Error'
      header = res.header_object
      header.clear
      header.add 'Content-Type', 'text/plain'
      body = res.body_object
      body.rewind
      body.truncate(0)
      body.puts backtrace
    end
  end
  # :startdoc:
end

# WebApp is a main routine of web application.
# It should be called from a toplevel of a CGI/FastCGI/mod_ruby/WEBrick script.
#
# WebApp is used as follows.
#
#   #!/usr/bin/env ruby
#   
#   require 'webapp'
#   
#   ... class/method definitions ... # run once per process.
#   
#   WebApp {|webapp| # This block runs once per request.
#     ... process a request ...
#   }
#
# WebApp yields with an object of the class WebApp.
# The object contains request and response.
#
# In the block, self is replaced by newly created _application_class_ object.
#
# WebApp rise $SAFE to 1.
#
# WebApp catches all kind of exception raised in the block.
# If HTTP connection is made from localhost, the backtrace is sent back to
# the browser.
# Otherwise, the backtrace is sent to stderr usually which is redirected to
# error.log.
#
def WebApp(application_class=Object, &block) # :yields: webapp
  $SAFE = 1 if $SAFE < 1
  manager = WebApp::Manager.new(application_class, block)
  if defined?(Apache::Request) && Apache.request.kind_of?(Apache::Request)
    run = lambda { manager.run_rbx }
  elsif Thread.current[:webrick_load_servlet]
    run = lambda { manager.run_webrick }
  elsif STDIN.respond_to?(:stat) && STDIN.stat.socket? &&
        begin
          require 'socket'
          # getpeername(FCGI_LISTENSOCK_FILENO) causes ENOTCONN for FastCGI
          # cf. http://www.fastcgi.com/devkit/doc/fcgi-spec.html
          sock = Socket.for_fd(0)
          sock.getpeername
          false
        rescue Errno::ENOTCONN
          true
        rescue SystemCallError
          false
        end
    run = lambda { manager.run_fcgi }
  elsif ENV.include?('REQUEST_METHOD')
    run = lambda { manager.run_cgi }
  else
    raise "not CGI/FastCGI/mod_ruby/WEBrick environment."
  end
  if Thread.current[:webapp_delay]
    Thread.current[:webapp_proc] = run
  else
    run.call
  end
end
