#!/usr/bin/env ruby

require "webapp"
require "htree" # http://raa.ruby-lang.org/project/htree/
require "sqlite" # http://raa.ruby-lang.org/project/sqlite-ruby/
require 'yaml'

config = YAML.load(File.read("#{File.dirname(__FILE__)}/view-sqlite.yml"))
$db_path = config.fetch('db_path')

def sqlite
  if !defined?($db_conn)
    $db_conn = SQLite::Database.open($db_path)
  end
  $db_conn
end

def quote(str)
  "'" + SQLite::Database.quote(str) + "'"
end

def foreach_table
  sqlite.execute(<<'End') {|row| yield row['name'] }
SELECT name FROM sqlite_master
WHERE type IN ('table','view')
ORDER BY 1
End
end

def list_tables(req, out)
  HTree.expand_template(out) {<<'End'}
<html>
  <head>
    <title>table list of SQLite</title>
  </head>
  <body>
    <table border=1>
      <tr><th>table name
      <div _iter="foreach_table//table_name">
        <tr><td><a _attr_href='req.make_relative_uri(:path_info=>"/table/#{table_name}")'
                   _text=table_name>table entry
      </div>
    </table>
  </body>
</html>
End
end

def foreach_row(table_name, beg, num, cont=nil)
  col_names = nil
  sqlite.execute(<<"End") {|row|
SELECT * FROM #{quote table_name}
WHERE #{beg} <= _ROWID_ and _ROWID_ <= #{beg+num+1}
End
    unless col_names
      numcols = row.size / 2
      oid2cid = {}
      0.upto(numcols-1) {|i|
        oid2cid[row[i].object_id] = i
      }
      col_names = row.keys.grep(String).sort_by {|n| oid2cid[row[n].object_id] }
      yield true, col_names
    end
    num -= 1
    next if num < 0
    yield false, col_names.map {|col| row[col] }
  }
  if cont
    cont[0] = num < 0
  end
end

def show_table(req, out, table_name, beg=0, num=100)
  beg = 0 if beg < 0
  num = 100 if 100 < num
  num = 1 if num < 1
  HTree.expand_template(out) {<<'End'}
<html>
  <head>
    <title>table content of SQLite</title>
  </head>
  <body>
    <table border=1>
      <div _template="table_head(names)">
        <tr><th _text=table_name _attr_colspan="names.length">table name
        <tr><th _iter="names.each//n"><span _text="n">column name
      </div>
      <div _iter="foreach_row(table_name, beg, num, cont=[nil])//head_p,row">
        <tr _if="!head_p" _else="table_head(row)">
          <td _iter="row.each//v"><span _text="v">value
      </div>
    </table>
    <span _if="0 < beg" _else="no_prev">
      <a _attr_href='req.make_relative_uri(:path_info=>"/table/#{table_name}/#{[beg-num,0].max}-#{beg-1}")'>[prev]</a>
    </span>
    <span _template="no_prev">[prev]</span>
    <span _if="cont[0]" _else="no_next">
      <a _attr_href='req.make_relative_uri(:path_info=>"/table/#{table_name}/#{beg+num}-#{beg+num+num-1}")'>[next]</a>
    </span>
    <span _template="no_next">[next]</span>
    <hr>
    <a _attr_href='req.make_relative_uri(:path_info=>"")'>back to table list</a>
  </body>
</html>
End
end

WebApp {|request, response|
  response.header_object.set 'Content-Type', 'text/html'
  out = response.body_object

  _, command, *args = request.path_info.split(%r{/})
  case command
  when nil, ''
    list_tables(request, out)
  when 'table'
    table, range, = args
    beg = 0
    num = 100
    case range
    when /\A(\d+)-(\d+)\z/
      beg = $1.to_i
      num = $2.to_i - beg + 1
    when /\A(\d+)-\z/
      beg = $1.to_i
      num = 100
    end
    show_table(request, out, table, beg, num)
  else
    raise "unexpected command: #{command}"
  end
}
