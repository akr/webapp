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
#     response.header_object.set 'Content-Type', 'text/plain'
#     body = response.body_object
#     body.puts <<"End"
#   current time: #{Time.now}
#   pid: #{$$}
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
#     request.header_object.each {|k, v|
#       body.puts "#{k}: #{v}"
#     }
#   }
#

require 'stringio'

module WebApp
  # CGI
  def WebApp.run_cgi # :nodoc:
    req = Request.new
    res = Response.new
    trap_exception(req, res) {
      req.make_request_header_from_cgi_env(ENV)
      if ENV.include?('CONTENT_LENGTH')
        len = env['CONTENT_LENGTH'].to_i
        req.body_object << $stdin.read(len)
      end
      req.freeze
      yield req, res
    }
    res.output_cgi_status_field($stdout)
    res.output_message($stdout)
  end

  # FastCGI
  def WebApp.run_fcgi # :nodoc:
    require 'fcgi'
    FCGI.each_request {|fcgi_request|
      req = Request.new
      res = Response.new
      trap_exception(req, res) {
        req.make_request_header_from_cgi_env(fcgi_request.env)
        if content = fcgi_request.in.read
          req.body_object << content
        end
        req.freeze
        yield req, res
      }
      res.output_cgi_status_field(fcgi_request.out)
      res.output_message(fcgi_request.out)
      fcgi_request.finish
    }
  end

  # mod_ruby
  def WebApp.run_rbx # :nodoc:
    rbx_request = Apache.request
    req = Request.new
    res = Response.new
    trap_exception(req, res) {
      req.make_request_header_from_cgi_env(rbx_request.subprocess_env)
      if content = rbx_request.read
        req.body_object << content
      end
      req.freeze
      yield req, res
    }
    res.output_cgi_status_field($stdout)
    rbx_request.status_line = "#{res.status_line}"
    res.header_object.each {|k, v|
      rbx_request.headers_out[k] = v
    }
    rbx_request.write res.body_object.string
  end

  def WebApp.trap_exception(req, res) # :nodoc:
    begin
      yield
    rescue Exception => e
      res.status_line = '500 Internal Server Error'
      res.header_object.clear
      res.header_object.add 'Content-Type', 'text/plain'
      res.body_object.truncate(0)
      res.body_object.print "#{e.message} (#{e.class})\n"
      e.backtrace.each {|f| res.body_object.puts f }
    end
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

    def make_frozen_copy_string(str)
      raise ArgumentError, "not a string: #{str.inspect}" unless str.respond_to? :to_str
      str = str.to_str
      str = str.dup.freeze unless str.frozen?
      str
    end
    private :make_frozen_copy_string

    def add(field_name, field_body)
      field_name = make_frozen_copy_string(field_name)
      field_body = make_frozen_copy_string(field_body)
      @fields << [field_name.downcase.freeze, field_name, field_body]
    end

    def set(field_name, field_body)
      field_name = make_frozen_copy_string(field_name)
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
    attr_reader :body_object, :header_object

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
  end
end

def WebApp
  $SAFE = 1 if $SAFE < 1
  if defined?(Apache::Request) && Apache.request.kind_of?(Apache::Request)
    WebApp.run_rbx {|request, response| yield request, response }
  elsif $stdin.respond_to?(:stat) && $stdin.stat.socket?
    WebApp.run_fcgi {|request, response| yield request, response }
  elsif ENV.include?('REQUEST_METHOD')
    WebApp.run_cgi {|request, response| yield request, response }
  else
    raise "not CGI/FastCGI/mod_ruby environment."
  end
end
