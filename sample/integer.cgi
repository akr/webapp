#!/usr/bin/env ruby
require 'webapp'

M = HTree.compile_template <<'End'
<html _template=int(n)>
  <head>
    <title _text>n</title>
  </head>
  <body>
    <h1 _text>n</h1>
    <ul>
    <li><a name=prev _attr_href='WebApp.reluri(:path_info=>"/#{n-1}", :fragment=>"prev")'>prev (<span _text="n-1"/>)</a>
    <li><a name=next _attr_href='WebApp.reluri(:path_info=>"/#{n+1}", :fragment=>"next")'>next (<span _text="n+1"/>)</a>
    </ul>
  </body>
</html>
End

WebApp {|webapp|
  n = webapp.path_info[/-?\d+/].to_i
  HTree.expand_template(webapp) {'<html _call="M.int(n)"/>'}
}
