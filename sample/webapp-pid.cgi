#!/usr/bin/env ruby

require 'webapp'

count = 0
WebApp {|webapp|
  webapp.puts <<"End"
pid: #$$
count: #{count}
End
  count += 1
}
