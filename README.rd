= webapp - easy-to-use CGI/FastCGI/mod_ruby/WEBrick interface

== Features

* very easy-to-use API
* works under CGI, FastCGI and mod_ruby without modification
* works uner WEBrick.
  (WEBrick based server must require "webapp/webrick-servlet", though.)
* path_info aware relative URI generation
* HTML form parameter varidation by HTML form

== How to Install

Just a single command as follows.

% ruby install.rb

To see the list of files to install: ruby install.rb -n

== Example

=== Hello World

The script follows works under CGI, FastCGI and mod_ruby without modification.
(Although it depends on web server configuration, the filename of the script
should be "hello.cgi", "hello.fcgi" or "hello.rbx".)

  require 'webapp'
  WebApp {|webapp|
    webapp.content_type = 'text/plain'
    webapp.puts "Hello World."
  }

The script also works under WEBrick based server such as follows.
In this case, the script filename should be "hello.webrick".

  require 'webapp/webrick-servlet'
  httpd = WEBrick::HTTPServer.new(:DocumentRoot => ".", :Port => 10080)
  trap(:INT){ httpd.shutdown }
  httpd.start 

== TODO

* session support
* file upload (multipart/form-data) support
* customizable cookie support

== Requirements

* Ruby 1.8
* htree 0.2
