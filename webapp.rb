# = webapp.rb - unified web application interface for CGI, FastCGI mod_ruby and WEBrick.
#
# == example
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

require 'stringio'
require 'forwardable'
require 'webapp/htmlform'
require 'pathname'
require 'htree'

class WebApp
  def initialize(manager, request, response) # :nodoc:
    @manager = manager
    @request = request
    @request_header = request.header_object
    @request_body = request.body_object
    @response = response
    @response_header = response.header_object
    @response_body = response.body_object
    @requri = ReqURI.new(@request.script_name, @request.path_info)
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
  # If /foo/bar/baz.cgi is a web application which WebApp {} calls,
  # webapp.resource_path("qux") returns a pathname points to /foo/bar/qux.
  def resource_path(path)
    @manager.resource_basedir + path
  end

  # call-seq:
  #   open_resource(path)
  #   open_resource(path) {|io| ... }
  # opens _path_ as relative from a web application directory.
  def open_resource(path, &block) 
    resource_path(path).open(&block)
  end

  # call-seq:
  #   make_relative_uri(:script=>string, :path_info=>string, :query=>query, :fragment=>string) -> string
  # 
  # make a relative URI which base URI is the URI the web application is
  # invoked.
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
  # Since make_relative_uri escapes the components properly,
  # you should specify them in unescaped form.
  #
  # In the example follow, assume that the web application bar.cgi is invoked
  # as http://host/foo/bar.cgi/baz/qux.
  #
  #   webapp.make_relative_uri(:path_info=>"/hoge") => "../hoge"
  #   webapp.make_relative_uri(:path_info=>"/baz/fuga") => "fuga"
  #   webapp.make_relative_uri(:path_info=>"/baz/") => "./"
  #   webapp.make_relative_uri(:path_info=>"/") => "../"
  #   webapp.make_relative_uri() => "../../bar.cgi"
  #   webapp.make_relative_uri(:script=>"funyo.cgi") => "../../funyo.cgi"
  #   webapp.make_relative_uri(:script=>"punyo/gunyo.cgi") => "../../punyo/gunyo.cgi"
  #   webapp.make_relative_uri(:script=>"../genyo.cgi") => "../../../genyo.cgi"
  #   webapp.make_relative_uri(:fragment=>"sec1") => "../../bar.cgi#sec1"
  #
  #   webapp.make_relative_uri(:path_info=>"/h?#o/x y") => "../h%3F%23o/x%20y"
  #   webapp.make_relative_uri(:script=>"ho%o.cgi") => "../../ho%25o.cgi"
  #   webapp.make_relative_uri(:fragment=>"sp ce") => "../../bar.cgi#sp%20ce"
  #
  def make_relative_uri(hash={})
    @requri.make_relative_uri(hash)
  end
  alias reluri make_relative_uri

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
        @app_block.call(webapp); complete_response(res); next # xxx: avoid core dump [ruby-dev:24228]
        #if @app_block
        #  class << app; self end.__send__(:define_method, :webapp_main, &@app_block)
        #end
        #app.webapp_main(webapp)
        #complete_response(res)
      }
      output_response.call(res)
    end

    def complete_response(res)
      unless res.header_object.has? 'Content-Type'
        case res.body_object.string
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
        res.header_object.set 'Content-Type', content_type
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

  class ReqURI
    def initialize(script_name, path_info)
      @script_name = script_name
      @path_info = path_info
    end

    def make_relative_uri(hash)
      script = hash[:script]
      path_info = hash[:path_info]
      query = hash[:query]
      fragment = hash[:fragment]

      if !script
        script = @script_name
      elsif %r{\A/} !~ script
        script = @script_name.sub(%r{[^/]*\z}) { script }
        while script.sub!(%r{/[^/]*/\.\.(?=/|\z)}, '')
        end
        script.sub!(%r{\A/\.\.(?=/|\z)}, '')
      end

      path_info = '/' + path_info if %r{\A[^/]} =~ path_info

      dst = "#{script}#{path_info}"
      dst.sub!(%r{\A/}, '')
      dst.sub!(%r{[^/]*\z}, '')
      dst_basename = $&

      src = "#{@script_name}#{@path_info}"
      src.sub!(%r{\A/}, '')
      src.sub!(%r{[^/]*\z}, '')

      while src[%r{\A[^/]*/}] == dst[%r{\A[^/]*/}]
        if $~
          src.sub!(%r{\A[^/]*/}, '')
          dst.sub!(%r{\A[^/]*/}, '')
        else
          break
        end
      end

      rel_path = '../' * src.count('/')
      rel_path << dst << dst_basename
      rel_path = './' if rel_path.empty?

      rel_path.gsub!(%r{[^/]+}) {|segment| pchar_escape(segment) }

      if query
        case query
        when QueryString
          query = query.instance_eval { @escaped_query_string }
        when Hash
          query = query.map {|k, v|
            case v
            when String
              "#{form_escape(k)}=#{form_escape(v)}"
            when Array
              v.map {|e|
                unless String === e
                  raise ArgumentError, "unexpected query value: #{e.inspect}"
                end
                "#{form_escape(k)}=#{form_escape(e)}"
              }
            else
              raise ArgumentError, "unexpected query value: #{v.inspect}"
            end
          }.join(';')
        else
          raise ArgumentError, "unexpected query: #{query.inspect}"
        end
        unless query.empty?
          query = '?' + uric_escape(query)
        end
      else
        query = ''
      end

      if fragment
        fragment = "#" + uric_escape(fragment)
      else
        fragment = ''
      end

      rel_path + query + fragment
    end

    Alpha = 'a-zA-Z'
    Digit = '0-9'
    AlphaNum = Alpha + Digit
    Mark = '\-_.!~*\'()'
    Unreserved = AlphaNum + Mark
    PChar = Unreserved + ':@&=+$,'
    def pchar_escape(s)
      s.gsub(/[^#{PChar}]/on) {|c| sprintf("%%%02X", c[0]) }
    end

    Reserved = ';/?:@&=+$,'
    Uric = Reserved + Unreserved
    def uric_escape(s)
      s.gsub(/[^#{Uric}]/on) {|c| sprintf("%%%02X", c[0]) }
    end

    def form_escape(s)
      s.gsub(/[#{Reserved}\x00-\x1f\x7f-\xff]/on) {|c|
        sprintf("%%%02X", c[0])
      }.gsub(/ /on) { '+' }
    end
  end

  class Header
    def Header.capitalize_field_name(field_name)
      field_name.gsub(/[A-Za-z]+/) {|s| s.capitalize }
    end

    def initialize
      @fields = []
    end

    def freeze
      @fields.freeze
      super
    end

    def clear
      @fields.clear
    end

    def remove(field_name)
      k1 = field_name.downcase
      @fields.reject! {|k2, _, _| k1 == k2 }
      nil
    end

    def add(field_name, field_body)
      field_name = WebApp.make_frozen_string(field_name)
      field_body = WebApp.make_frozen_string(field_body)
      @fields << [field_name.downcase.freeze, field_name, field_body]
    end

    def set(field_name, field_body)
      field_name = WebApp.make_frozen_string(field_name)
      remove(field_name)
      add(field_name, field_body)
    end

    def has?(field_name)
      @fields.assoc(field_name.downcase) != nil
    end

    def [](field_name)
      k1 = field_name.downcase
      @fields.each {|k2, field_name, field_body|
        return field_body.dup if k1 == k2
      }
      nil
    end

    def lookup_all(field_name)
      k1 = field_name.downcase
      result = []
      @fields.each {|k2, field_name, field_body|
        result << field_body.dup if k1 == k2
      }
      result
    end

    def each
      @fields.each {|_, field_name, field_body|
        field_name = field_name.dup
        field_body = field_body.dup
        yield field_name, field_body
      }
    end
  end

  class Message
    def initialize(header={}, body='')
      @header_object = Header.new
      case header
      when Hash
        header.each_pair {|k, v|
          raise ArgumentError, "unexpected header field name: #{k.inspect}" unless k.respond_to? :to_str
          raise ArgumentError, "unexpected header field body: #{v.inspect}" unless v.respond_to? :to_str
          @header_object.add k.to_str, v.to_str
        }
      when Array
        header.each {|k, v|
          raise ArgumentError, "unexpected header field name: #{k.inspect}" unless k.respond_to? :to_str
          raise ArgumentError, "unexpected header field body: #{v.inspect}" unless v.respond_to? :to_str
          @header_object.add k.to_str, v.to_str
        }
      else
        raise ArgumentError, "unexpected header argument: #{header.inspect}"
      end
      raise ArgumentError, "unexpected body: #{body.inspect}" unless body.respond_to? :to_str
      @body_object = StringIO.new(body.to_str)
    end
    attr_reader :header_object, :body_object

    def freeze
      @header_object.freeze
      @body_object.string.freeze
      super
    end

    def output_message(out)
      content = @body_object.length
      @header_object.each {|k, v|
        out << "#{k}: #{v}\n"
      }
      out << "\n"
      out << @body_object.string
    end
  end

  class Request < Message
    def initialize(request_line=nil, header={}, body='')
      @request_line = request_line
      super header, body
    end
    attr_reader :request_method,
                :server_name, :server_port,
                :script_name, :path_info,
                :query_string,
                :server_protocol,
                :remote_addr, :content_type

    def make_request_header_from_cgi_env(env)
      env.each {|k, v|
        next if /\AHTTP_/ !~ k
        k = Header.capitalize_field_name($')
        k.gsub!(/_/, '-')
        @header_object.add k, v
      }
      @request_method = env['REQUEST_METHOD']
      @server_name = env['SERVER_NAME'] || ''
      @server_port = env['SERVER_PORT'].to_i
      @script_name = env['SCRIPT_NAME'] || ''
      @path_info = env['PATH_INFO'] || ''
      @query_string = QueryString.primitive_new_for_raw_query_string(env['QUERY_STRING'] || '')
      @server_protocol = env['SERVER_PROTOCOL'] || ''
      @remote_addr = env['REMOTE_ADDR'] || ''
      @content_type = env['CONTENT_TYPE'] || ''

      # non-standard:
      @request_uri = env['REQUEST_URI'] # Apache
    end
  end

  class Response < Message
    def initialize(status_line='200 OK', header={}, body='')
      @status_line = status_line
      super header, body
    end
    attr_accessor :status_line

    def output_cgi_status_field(out)
      out << "Status: #{self.status_line}\n"
    end
  end
  # :startdoc:
end

# WebApp is a main routine of web application.
# It should be called from a toplevel of a CGI/FastCGI/mod_ruby/WEBrick script.
#
# WebApp yields with an object of the class WebApp.
# The object contains request and response.
#
# In the block, self is replaced by newly created _application_class_ object.
#
# WebApp rise $SAFE to 1.
#
def WebApp(application_class=Object, &block) # :yields: webapp
  $SAFE = 1 if $SAFE < 1
  webapp = WebApp::Manager.new(application_class, block)
  if defined?(Apache::Request) && Apache.request.kind_of?(Apache::Request)
    run = lambda { webapp.run_rbx }
  elsif Thread.current[:webrick_load_servlet]
    run = lambda { webapp.run_webrick }
  elsif $stdin.respond_to?(:stat) && $stdin.stat.socket?
    run = lambda { webapp.run_fcgi }
  elsif ENV.include?('REQUEST_METHOD')
    run = lambda { webapp.run_cgi }
  else
    raise "not CGI/FastCGI/mod_ruby/WEBrick environment."
  end
  if Thread.current[:webapp_delay]
    Thread.current[:webapp_proc] = run
  else
    run.call
  end
end
