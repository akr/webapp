#!/usr/bin/env ruby

require 'webapp'

WebApp {|webapp|
  webapp.setup_redirection 301, 'http://www.ruby-lang.org/'
}
