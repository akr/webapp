require 'test/unit'
require 'webapp'

class URIGenTest < Test::Unit::TestCase
  def check_reluri_1(expected, hash)
    requri = WebApp::URIGen.new('http', "host", 80, "/foo/bar.cgi", "/baz/qux")
    assert_equal(expected, requri.make_relative_uri(hash).to_s)
  end

  def test_path_info
    check_reluri_1("../hoge"              , :path_info=>"/hoge")
    check_reluri_1("fuga"                 , :path_info=>"/baz/fuga")
    check_reluri_1("./"                   , :path_info=>"/baz/")
    check_reluri_1("../"                  , :path_info=>"/")
    check_reluri_1("../../bar.cgi"        , {})
    check_reluri_1("../../funyo.cgi"      , :script=>"funyo.cgi")
    check_reluri_1("../../punyo/gunyo.cgi", :script=>"punyo/gunyo.cgi")
    check_reluri_1("../../../genyo.cgi"   , :script=>"../genyo.cgi")
    check_reluri_1("../../bar.cgi#sec1"   , :fragment=>"sec1")
    check_reluri_1("../h%3F%23o/x%20y"    , :path_info=>"/h?#o/x y")
    check_reluri_1("../../ho%25o.cgi"     , :script=>"ho%o.cgi")
    check_reluri_1("../../bar.cgi#sp%20ce", :fragment=>"sp ce")
  end

  def check_reluri_2(expected, hash)
    requri = WebApp::URIGen.new('http', "host", 80, "/foo/bar.cgi", '')
    assert_equal(expected, requri.make_relative_uri(hash).to_s)
  end

  def test_query
    check_reluri_2("bar.cgi", :query=>{})
    check_reluri_2("bar.cgi?a=b", :query=>{'a'=>'b'})
    check_reluri_2("bar.cgi?a=b;a=c", :query=>{'a'=>['b','c']})
    check_reluri_2("bar.cgi?a+b=c+d", :query=>{'a b'=>'c d'})
  end

  def test_reluri_unexpected
    requri = WebApp::URIGen.new('http', "host", 80, "/foo.cgi", '')
    assert_raise(ArgumentError) {
      requri.make_relative_uri({:script_name=>"bar.cgi"})
    }
  end

  def test_reluri_colon
    assert_equal("./a:b", 
      WebApp::URIGen.new('http', "host", 80, "/foo.cgi", '').make_relative_uri({:script=>"/a:b"}).to_s)
    assert_equal("./a:b", 
      WebApp::URIGen.new('http', "host", 80, "/foo.cgi", '/bar').make_relative_uri({:path_info=>"a:b"}).to_s)
  end

  def check_absuri(expected, hash)
    requri = WebApp::URIGen.new('http', "host", 80, "/foo/bar.cgi", "/baz/qux")
    assert_equal(expected, requri.make_absolute_uri(hash).to_s)
  end

  def test_absuri
    check_absuri("http://host/foo/bar.cgi", {})
    check_absuri("http://host/foo/bar.cgi/hoge", :path_info=>"/hoge")
  end
end
