= webapp - easy-to-use CGI/FastCGI/mod_ruby/WEBrick interface

== Features

* very easy-to-use API
* works under CGI, FastCGI and mod_ruby without modification
* works under WEBrick
  (WEBrick based server must require "webapp/webrick-servlet", though.)
* works as usual command (CLI)
  xxx.cgi [options] [/path_info] [?query_string]
* path_info aware relative URI generation
* HTML form parameter varidation by HTML form (sample/query.cgi)
* automatic Content-Type generation
* a web application can be used as a web site with WEBrick
  (URL will be http://host/path_info?query.
  No path component to specify a web application.)
* a response is gzipped automatically if the browser accepts.

== Home Page

((<URL:http://cvs.m17n.org/~akr/webapp/>))

== Download

* ((<URL:http://cvs.m17n.org/viewcvs/ruby/webapp.tar.gz>))

== How to Install

  % ruby install.rb

To see the list of files to install: ruby install.rb -n

== Reference Manual

((<URL:doc/index.html>))

== Example

=== Hello World

The script follows works under CGI, FastCGI and mod_ruby without modification.
(Although it depends on web server configuration, the filename of the script
should be "hello.cgi", "hello.fcgi" or "hello.rbx".)

  require 'webapp'
  WebApp {|webapp|
    webapp.puts "Hello World."
  }

The script also works under WEBrick based server such as follows.
In this case, the script filename should be "hello.webrick".

  require 'webapp/webrick-servlet'
  httpd = WEBrick::HTTPServer.new(:DocumentRoot => Dir.getwd, :Port => 10080)
  trap(:INT){ httpd.shutdown }
  httpd.start 

== TODO

* file upload (multipart/form-data) support
* session support
* customizable cookie support

== Requirements

* Ruby 1.8.2
* htree 0.2
* fcgi 0.8.4 (if you use FastCGI)
* mod_ruby 1.2.2 (if you use mod_ruby)

== License

Ruby's

== Author
Tanaka Akira <akr@m17n.org>
