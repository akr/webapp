#!/usr/bin/env ruby

require 'webapp'

WebApp {|webapp|
  webapp.content_type = 'text/plain'
  webapp.puts "Hello World."
}
