require 'webapp'
require 'webrick'

class WebApp
  class WEBrickServletHandler < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, name)
      super
      @name = name
    end

    def do_GET(req, res)
      begin
        Thread.current[:webapp_webrick] = [req, res]
        procdure = WebApp.load_webapp_procedure(@name)
        procdure.call
      ensure
        Thread.current[:webapp_webrick] = nil
      end
    end
    alias do_POST do_GET
  end
end
WEBrick::HTTPServlet::FileHandler.add_handler('webrick',
  WebApp::WEBrickServletHandler)

if $0 == __FILE__
  httpd = WEBrick::HTTPServer.new(:DocumentRoot => ".", :Port => 10080)
  trap(:INT){ httpd.shutdown }
  httpd.start
end
