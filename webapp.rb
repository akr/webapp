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
#     response.header_object.add 'Content-Type', 'text/plain'
#     response.body_object.puts Time.now
#     request.header_object.each {|k, v|
#       response.body_object.puts "#{k}: #{v}"
#     }
#   }

require 'stringio'

module WebApp
  def WebApp.run_cgi # CGI
    req = Request.new
    res = Response.new
    trap_exception(req, res) {
      req.make_request_header_from_cgi_env(ENV)
      if ENV.include?('CONTENT_LENGTH')
        len = env['CONTENT_LENGTH'].to_i
        req.body_object << $stdin.read(len)
      end
      yield req, res
    }
    res.output_cgi_status_field($stdout)
    res.output_message($stdout)
  end

  def WebApp.run_fcgi # FastCGI
    require 'fcgi'
    FCGI.each_request {|fcgi_request|
      req = Request.new
      res = Response.new
      trap_exception(req, res) {
        req.make_request_header_from_cgi_env(fcgi_request.env)
        if content = fcgi_request.in.read
          req.body_object << content
        end
        yield req, res
      }
      res.output_cgi_status_field(fcgi_request.out)
      res.output_message(fcgi_request.out)
      fcgi_request.finish
    }
  end

  def WebApp.run_rbx # mod_ruby
    rbx_request = Apache.request
    req = Request.new
    res = Response.new
    trap_exception(req, res) {
      req.make_request_header_from_cgi_env(rbx_request.subprocess_env)
      if content = rbx_request.read
        req.body_object << content
      end
      yield req, res
    }
    res.output_cgi_status_field($stdout)
    rbx_request.status_line = "#{res.status_line}"
    res.header_object.each {|k, v|
      rbx_request.headers_out[k] = v
    }
    rbx_request.write res.body_object.string
  end

  def WebApp.trap_exception(req, res)
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
    def Header.capitalize_field_name(field_name)
      field_name.gsub(/[A-Za-z]+/) {|s| s.capitalize }
    end

    def initialize
      @fields = []
    end

    def clear
      @fields.clear
    end

    def add(field_name, field_body)
      @fields << [field_name.downcase, field_name, field_body]
    end

    def [](field_name)
      k1 = field_name.downcase
      @fields.each {|k2, field_name, field_body|
        return field_body if k1 == k2
      }
      nil
    end

    def lookup_all(field_name)
      k1 = field_name.downcase
      result = []
      @fields.each {|k2, field_name, field_body|
        result << field_body if k1 == k2
      }
      result
    end

    def each
      @fields.each {|_, field_name, field_body|
        yield field_name, field_body
      }
    end
  end

  class Message
    def initialize(header={}, body='')
      @header = Header.new
      case header
      when Hash
        header.each_pair {|k, v|
          raise ArgumentError, "unexpected header field name: #{k.inspect}" unless k.respond_to? :to_str
          raise ArgumentError, "unexpected header field body: #{v.inspect}" unless v.respond_to? :to_str
          @header.add_header k.to_str, v.to_str
        }
      when Array
        header.each {|k, v|
          raise ArgumentError, "unexpected header field name: #{k.inspect}" unless k.respond_to? :to_str
          raise ArgumentError, "unexpected header field body: #{v.inspect}" unless v.respond_to? :to_str
          @header.add_header k.to_str, v.to_str
        }
      else
        raise ArgumentError, "unexpected header argument: #{header.inspect}"
      end
      raise ArgumentError, "unexpected body: #{body.inspect}" unless body.respond_to? :to_str
      @body_object = StringIO.new(body.to_str)
    end
    attr_reader :body_object
    def header_object() @header end

    def output_message(out)
      content = @body_object.length
      @header.each {|k, v|
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
        @header.add k, v
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
    def initialize(status_line='200 OK', header={}, body='')
      @status_line = status_line
      super header, body
    end
    attr_accessor :status_line

    def output_cgi_status_field(out)
      out << "Status: #{self.status_line}\n"
    end
  end
end

def WebApp(&block)
  $SAFE = 1 if $SAFE < 1
  if defined?(Apache::Request) && Apache.request.kind_of?(Apache::Request)
    WebApp.run_rbx(&block)
  elsif $stdin.respond_to?(:stat) && $stdin.stat.socket?
    WebApp.run_fcgi(&block)
  elsif ENV.include?('REQUEST_METHOD')
    WebApp.run_cgi(&block)
  else
    raise "not CGI/FastCGI/mod_ruby environment."
  end
end
