require 'test/unit'
require 'webapp'

class HTMLFormQueryTest < Test::Unit::TestCase
  def d(str)
    WebApp::HTMLFormQuery.decode_x_www_form_urlencoded(str)
  end

  def test_decode_x_www_form_urlencoded
    assert_equal("b", d("a=b").get("a"))
  end
end
