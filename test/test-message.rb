require 'test/unit'
require 'webapp'

class MessageTest < Test::Unit::TestCase
  def test_header_dup
    h1 = WebApp::Header.new
    h1.add 'foo', 'bar'
    h2 = h1.dup
    h1.add 'baz', 'qux'
    assert_equal('qux', h1['baz'])
    assert_equal(nil, h2['baz'])
  end
end
