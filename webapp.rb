# = webapp.rb - unified web application interface for CGI, FastCGI and mod_ruby.
#
# == example
#
# Following script works as CGI(*.cgi), FastCGI(*.fcgi) and mod_ruby(*.rbx)
# without any modification.
#
#   #!/path/to/ruby
#
#   require 'webapp'
#  
#   WebApp {|request, response|
#     response.set_header 'Content-Type', 'text/plain'
#     response.puts <<"End"
#   current time: #{Time.now}
#   pid: #{$$}
#   self: #{self.inspect}
#   
#   request_method: #{request.request_method}
#   server_name: #{request.server_name}
#   server_port: #{request.server_port}
#   script_name: #{request.script_name}
#   path_info: #{request.path_info}
#   query_string: #{request.query_string}
#   server_protocol: #{request.server_protocol}
#   remote_addr: #{request.remote_addr}
#   content_type: #{request.content_type}
#   
#   --- request headers ---
#   End
#     request.each_header {|k, v|
#       response.puts "#{k}: #{v}"
#     }
#   }
#

require 'stringio'
require 'forwardable'

class WebApp
  def initialize(app_class, app_block) # :nodoc:
    @app_class = app_class
    @app_block = app_block
  end

  # CGI
  def run_cgi # :nodoc:
    setup_request = lambda {|req|
      req.make_request_header_from_cgi_env(ENV)
      if ENV.include?('CONTENT_LENGTH')
        len = ENV['CONTENT_LENGTH'].to_i
        req << $stdin.read(len)
      end
    }
    output_response = lambda {|res|
      res.output_cgi_status_field($stdout)
      res.output_message($stdout)
    }
    primitive_run(setup_request, output_response)
  end

  # FastCGI
  def run_fcgi # :nodoc:
    require 'fcgi'
    FCGI.each_request {|fcgi_request|
      setup_request = lambda {|req|
        req.make_request_header_from_cgi_env(fcgi_request.env)
        if content = fcgi_request.in.read
          req << content
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

  # mod_ruby
  def run_rbx # :nodoc:
    rbx_request = Apache.request
    setup_request = lambda {|req|
      req.make_request_header_from_cgi_env(rbx_request.subprocess_env)
      if content = rbx_request.read
        req << content
      end
    }
    output_response =  lambda {|res|
      rbx_request.status_line = "#{res.status_line}"
      res.each_header {|k, v|
        rbx_request.headers_out[k] = v
      }
      res.rewind
      rbx_request.write res.read
    }
    primitive_run(setup_request, output_response)
  end

  def primitive_run(setup_request, output_response) # :nodoc:
    req = Request.new
    res = Response.new
    trap_exception(req, res) {
      setup_request.call(req)
      req.freeze
      app = @app_class.new
      if @app_block
        class << app; self end.__send__(:define_method, :webapp_main, &@app_block)
      end
      app.webapp_main(req, res)
    }
    output_response.call(res)
  end

  def trap_exception(req, res) # :nodoc:
    begin
      yield
    rescue Exception => e
      res.status_line = '500 Internal Server Error'
      res.clear_header
      res.add_header 'Content-Type', 'text/plain'
      res.truncate(0)
      res.puts "#{e.message} (#{e.class})"
      e.backtrace.each {|f| res.puts f }
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
      #query = hash[:query]
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

      if fragment
        fragment = "#" + uric_escape(fragment)
      else
        fragment = ''
      end

      #rel_path + query + fragment
      rel_path + fragment
    end

    private

    # :stopdoc:
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
    # :startdoc:
  end

  class Header
    def Header.capitalize_field_name(field_name) # :nodoc:
      field_name.gsub(/[A-Za-z]+/) {|s| s.capitalize }
    end

    def initialize # :nodoc:
      @fields = []
    end

    def freeze # :nodoc:
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

    def make_frozen_string(str)
      raise ArgumentError, "not a string: #{str.inspect}" unless str.respond_to? :to_str
      str = str.to_str
      str = str.dup.freeze unless str.frozen?
      str
    end
    private :make_frozen_string

    def add(field_name, field_body)
      field_name = make_frozen_string(field_name)
      field_body = make_frozen_string(field_body)
      @fields << [field_name.downcase.freeze, field_name, field_body]
    end

    def set(field_name, field_body)
      field_name = make_frozen_string(field_name)
      remove(field_name)
      add(field_name, field_body)
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
    def initialize(header={}, body='') # :nodoc:
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

    def freeze # :nodoc:
      @header_object.freeze
      unless @body_object.string.frozen?
        @body_object = StringIO.new(@body_object.string.freeze)
      end
      super
    end

    def output_message(out) # :nodoc:
      content = @body_object.length
      @header_object.each {|k, v|
        out << "#{k}: #{v}\n"
      }
      out << "\n"
      out << @body_object.string
    end

    extend Forwardable
    def_delegators :@body_object,
      :<<,
      :each, :each_line, :each_byte, :eof, :eof?,
      :getc, :gets, :pos, :tell, :pos=,
      :print, :printf, :putc, :puts,
      :read, :readchar, :readline, :readlines,
      :rewind, :seek, :ungetc, :write,
      :truncate

    def_delegator :@header_object, :set, :set_header
    def_delegator :@header_object, :add, :add_header
    def_delegator :@header_object, :clear, :clear_header
    def_delegator :@header_object, :[], :get_header
    def_delegator :@header_object, :each, :each_header
  end

  class Request < Message
    def initialize(request_line=nil, header={}, body='') # :nodoc:
      @request_line = request_line
      super header, body
    end
    attr_reader :request_method,
                :server_name, :server_port,
                :script_name, :path_info,
                :query_string,
                :server_protocol,
                :remote_addr, :content_type

    def make_request_header_from_cgi_env(env) # :nodoc:
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
      @query_string = env['QUERY_STRING'] || ''
      @server_protocol = env['SERVER_PROTOCOL'] || ''
      @remote_addr = env['REMOTE_ADDR'] || ''
      @content_type = env['CONTENT_TYPE'] || ''

      # non-standard:
      @request_uri = env['REQUEST_URI'] # Apache

      @requri = ReqURI.new(@script_name, @path_info)
    end

    def make_relative_uri(hash)
      @requri.make_relative_uri(hash)
    end
  end

  class Response < Message
    def initialize(status_line='200 OK', header={}, body='') # :nodoc:
      @status_line = status_line
      super header, body
    end
    attr_accessor :status_line

    def output_cgi_status_field(out) # :nodoc:
      out << "Status: #{self.status_line}\n"
    end

    def content_type=(media_type)
      set_header 'Content-Type', media_type
    end
  end
end

# WebApp is a main routine of web application.
# It should be called from a toplevel of a CGI/FastCGI/mod_ruby script.
#
# WebApp yields with a request and response object.
# The request object represents information from a client.
# The reseponse object represents information to a client which is initially empty.
# In the block, self is replaced by newly created _application_class_ object.
#
def WebApp(application_class=Object, &block) # :yields: request, response
  $SAFE = 1 if $SAFE < 1
  webapp = WebApp.new(application_class, block)
  if defined?(Apache::Request) && Apache.request.kind_of?(Apache::Request)
    webapp.run_rbx
  elsif $stdin.respond_to?(:stat) && $stdin.stat.socket?
    webapp.run_fcgi
  elsif ENV.include?('REQUEST_METHOD')
    webapp.run_cgi
  else
    raise "not CGI/FastCGI/mod_ruby environment."
  end
end
