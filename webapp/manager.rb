require 'stringio'
require 'pathname'
require 'zlib'
require 'htree'
require 'webapp/message'

class WebApp
  # :stopdoc:
  WebAPPDevelopHost = ENV['WEBAPP_DEVELOP_HOST']

  class Manager
    def initialize(app_block)
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
        @app_block.call(webapp)
        complete_response(webapp, res)
      }
      output_response.call(res)
    end

    def complete_response(webapp, res)
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
      gzip_content(webapp, res) unless res.header_object.has? 'Content-Encoding'
      unless res.header_object.has? 'Content-Length'
        res.header_object.set 'Content-Length', res.body_object.length.to_s
      end
    end

    def gzip_content(webapp, res, level=nil)
      # xxx: parse the Accept-Encoding field body
      if accept_encoding = webapp.get_request_header('Accept-Encoding') and
         /gzip/ =~ accept_encoding and
         /\A\037\213/ !~ res.body_object.string # already gzipped
        level ||= Zlib::DEFAULT_COMPRESSION
        content = res.body_object.string
        Zlib::GzipWriter.wrap(StringIO.new(gzipped = ''), level) {|gz|
          gz << content
        }
        if gzipped.length < content.length
          content.replace gzipped
          res.header_object.set 'Content-Encoding', 'gzip'
        end
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
        if devlopper_host? req.remote_addr
          generate_debug_page(req, res, e)
        else
          generate_error_page(req, res, e)
        end
      end
    end

    def devlopper_host?(addr)
      return true if addr == '127.0.0.1'
      return false if %r{\A(\d+)\.(\d+)\.(\d+)\.(\d+)\z} !~ addr
      addr_arr = [$1.to_i, $2.to_i, $3.to_i, $4.to_i]
      addr_bin = addr_arr.pack("CCCC").unpack("B*")[0]
      case WebAPPDevelopHost
      when %r{\A(\d+)\.(\d+)\.(\d+)\.(\d+)\z}
        dev_arr = [$1.to_i, $2.to_i, $3.to_i, $4.to_i]
        return true if dev_arr == addr_arr
      when %r{\A(\d+)\.(\d+)\.(\d+)\.(\d+)/(\d+)\z}
        dev_arr = [$1.to_i, $2.to_i, $3.to_i, $4.to_i]
        dev_bin = dev_arr.pack("CCCC").unpack("B*")[0]
        dev_len = $5.to_i
        return true if addr_bin[0, dev_len] == dev_bin[0, dev_len]
      end
      return false
    end

    def generate_error_page(req, res, exc)
      backtrace = "#{exc.message} (#{exc.class})\n"
      exc.backtrace.each {|f| backtrace << f << "\n" }
      $stderr.puts backtrace # output to error.log
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
</html>
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
