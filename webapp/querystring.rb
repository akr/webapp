class WebApp
  # QueryString represents a query component of URI.
  class QueryString
    class << self
      alias primitive_new_for_raw_query_string new
      undef new
    end

    def initialize(escaped_query_string)
      @escaped_query_string = escaped_query_string
    end

    def inspect
      "#<#{self.class}: #{@escaped_query_string}>"
    end
    alias to_s inspect
  end
end
