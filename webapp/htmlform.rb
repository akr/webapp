require 'htree'

class WebApp
  class QueryString
    # decode self as application/x-www-form-urlencoded and returns
    # HTMLFormQuery object.
    def decode_as_application_x_www_form_urlencoded
      # xxx: warning if invalid?
      pairs = []
      @escaped_query_string.scan(/([^&;=]*)=([^&;]*)/) {|key, val|
        key.gsub!(/\+/, ' ')
        key.gsub!(/%([0-9A-F][0-9A-F])/i) { [$1].pack("H*") }
        val.gsub!(/\+/, ' ')
        val.gsub!(/%([0-9A-F][0-9A-F])/i) { [$1].pack("H*") }
        pairs << [key.freeze, val.freeze]
      }
      HTMLFormQuery.new(pairs)
    end
  end

  # HTMLFormQuery represents a query submitted by HTML form. 
  class HTMLFormQuery
    def HTMLFormQuery.each_string_key_pair(arg, &block) # :nodoc:
      if arg.respond_to? :to_ary
        arg = arg.to_ary
        if arg.length == 2 && arg.first.respond_to?(:to_str)
          yield WebApp.make_frozen_string(arg.first), arg.last
        else
          arg.each {|elt|
            HTMLFormQuery.each_string_key_pair(elt, &block)
          }
        end
      elsif arg.respond_to? :to_pair
        arg.each_pair {|key, val|
          yield WebApp.make_frozen_string(key), val
        }
      else
        raise ArgumentError, "non-pairs argument: #{arg.inspect}"
      end
    end

    def initialize(*args)
      @param = []
      HTMLFormQuery.each_string_key_pair(args) {|key, val|
        @param << [key, val]
      }
      @param.freeze
    end

    def each
      @param.each {|key, val|
        yield key.dup, val.dup
      }
    end

    def [](key)
      if pair = @param.assoc(key)
        return pair.last.dup
      end
      return nil
    end

    def lookup_all(key)
      result = []
      @param.each {|k, val|
        result << val if k == key
      }
      return result
    end

    def keys
      @param.map {|key, val| key }.uniq
    end
  end

  class HTMLFormValidator
    def initialize(form, form_id=nil)
      form_tree = extract_html_form_tree(form, form_id)
      @radio_nonempty = []
      @select_nonempty = []
      @controls, @other_submits = extract_html_form_controls(form_tree)
      @radio_nonempty.uniq!
      @method = form_tree.get_attr('method')
      @method ||= 'GET'
      @enctype = form_tree.get_attr('enctype')
      @enctype ||= 'application/x-www-form-urlencoded'
      @accept_content_type = form_tree.get_attr('accept')
      @accept_charset = form_tree.get_attr('accept-charset')

      if %r{\Aapplication/x-www-form-urlencoded\z} !~ @enctype
        raise ArgumentError, "enctype not supported: #{@enctype}"
      end
        
    end

    def extract_html_form_tree(form, id=nil) # :nodoc:
      form_tree = nil
      tree = HTree(form)
      tree.traverse_element("{http://www.w3.org/1999/xhtml}form", "form") {|e|
        if id
          if e.get_attr("id") == id || e.get_attr("name") == id
            form_tree = e
            break
          end
        else
          form_tree = e
          break
        end
      }
      raise ArgumentError, "no form: #{form.inspect}" if !form_tree
      form_tree
    end

    def extract_html_form_controls(form_tree) # :nodoc:
      controls = []
      successfulable_submits = false
      other_submits = false
      form_tree.traverse_element(
        'form', '{http://www.w3.org/1999/xhtml}form',
        'input', '{http://www.w3.org/1999/xhtml}input',
        'select', '{http://www.w3.org/1999/xhtml}select',
        'textarea', '{http://www.w3.org/1999/xhtml}textarea',
        'button', '{http://www.w3.org/1999/xhtml}button') {|e|
        c = {}
        case e.element_name.local_name
        when /\Aform\z/i
          next if e.equal? form_tree
          raise ArgumentError, "nested form"
        when /\Ainput\z/i
          c[:elem] = :input
          c[:type] = e.get_attr('type') || 'text'
          unless c[:name] = e.get_attr('name')
            other_submits = true if /\Asubmit\z/i =~ c[:type]
            next
          end
          c[:value] = e.get_attr('value')
          c[:disabled] = e.get_attr('disabled')
          case c[:type]
          when /\A(?:text|password)\z/i
            c[:value] ||= ''
            c[:readonly] = e.get_attr('readonly')
            if maxlength = e.get_attr('maxlength')
              if /\A[0-9]+\z/ !~ maxlength
                raise ArgumentError, "non-number maxlength: #{maxlength.inspect}"
              end
              maxlength = maxlength.to_i
            end
            c[:maxlength] = maxlength
          when /\A(?:checkbox|radio)\z/i
            c[:checked] = e.get_attr('checked')
            unless c[:value]
              raise ArgumentError, "no value #{c[:type].downcase} input"
            end
            if /\Aradio\z/i =~ c[:type] && c[:checked]
              @radio_nonempty << c[:name]
            end
          when /\Asubmit\z/i
            unless c[:value]
              raise ArgumentError,
                "submit with name but without value is not portable."
            end
            successfulable_submits = true
          when /\Areset\z/i
            next
          when /\Afile\z/i
            c[:accept] = e.get_attr('accept')
            raise ArgumentError, "file upload not supported yet"
          when /\Ahidden\z/i
            raise ArgumentError, "hidden input without value" unless c[:value]
          when /\Aimage\z/i
            cx = c.dup
            cx[:name] = "#{c[:name]}.x"
            cx[:type] = 'image-x'
            controls << cx
            cy = c.dup
            cy[:name] = "#{c[:name]}.y"
            cy[:type] = 'image-y'
            controls << cy
            successfulable_submits = true
          when /\Abutton\z/i
            next unless c[:value]
          else
            raise ArgumentError,
              "unexpected input element type: #{c[:type].inspect}"
          end
        when /\Aselect\z/
          select = {}
          select[:elem] = :select
          next unless select[:name] = e.get_attr('name')
          select[:multiple] = e.get_attr('multiple')
          select[:disabled] = e.get_attr('disabled')
          has_selected = false
          # xxx: disabled optgroup is not supported yet.
          e.traverse_element(
            'option', '{http://www.w3.org/1999/xhtml}option') {|option|
            c = {:elem=>:option, :name=>select[:name], :select=>select}
            c[:disabled] = option.get_attr('disabled') || select[:disabled]
            c[:value] = option.get_attr('value') || option.extract_text.to_s
            has_selected = true if option.get_attr('selected')
            controls << c
          }
          if has_selected && !select[:multiple]
            @select_nonempty << select[:name]
          end
          next
        when /\Atextarea\z/
          c[:elem] = :textarea
          next unless c[:name] = e.get_attr('name')
          c[:disabled] = e.get_attr('disabled')
          c[:readonly] = e.get_attr('readonly')
          c[:value] = e.extract_text if c[:readonly]
        when /\Abutton\z/
          c[:elem] = :button
          c[:type] = e.get_attr('type') || 'submit'
          unless c[:name] = e.get_attr('name')
            other_submits = true if /\Asubmit\z/i =~ c[:type]
            next 
          end
          c[:value] = e.get_attr('value')
          if /\A(button|submit|reset)\z/i !~ c[:type]
            raise ArgumentError,
              "unexpected button element type: #{c[:type].inspect}"
          end
          next if /\Areset\z/i =~ c[:type]
          c[:disabled] = e.get_attr('disabled')
          successfulable_submits = true if /\Asubmit\z/i =~ c[:type]
        end
        controls << c
      }
      other_submits = true if !successfulable_submits
      [controls, other_submits]
    end

    def validate(webapp)
      if @method.downcase != webapp.request_method.downcase
        raise QueryValidationFailure,
          "method mismatch: #{webapp.request_method} (expected: #{method})"
      end
      case @enctype
      when %r{\Aapplication/x-www-form-urlencoded\z}i
        case @method
        when /\Aget\z/i
          q = webapp.query_html_get_application_x_www_form_urlencoded
        when /\Apost\z/i
          q = webapp.query_html_post_application_x_www_form_urlencoded
        else
          raise ArgumentError, "unsupported method: #{method}"
        end
      else
        raise ArgumentError, "unsupported enctype: #{enctype}"
      end
      successful = []
      cs = @controls.reject {|c| c[:disabled] }
      i = 0
      q.each {|key, val|
        k = nil
        i.upto(i+cs.length-1) {|j|
          j -= cs.length if cs.length <= j
          if corresponding_control?(cs[j], key, val)
            k = j
            break
          end
        }
        unless k
          raise QueryValidationFailure,
            "extra parameter: #{key.inspect}=#{val.inspect}"
        end
        successful << cs[k]
        cs[k, 1] = []
        i = k
      }
      cs.each {|c|
        if always_successful? c
          raise QueryValidationFailure, "parameter lacks: #{c[:name].inspect}"
        end
      }
      validate_combination(successful)
      q
    end

    def validate_combination(successful)
      count_radio = Hash.new(0)
      count_submit = 0
      count_option = Hash.new(0)
      image_x_basenames = []
      image_y_basenames = []
      radio_nonempty = @radio_nonempty.dup
      select_nonempty = @select_nonempty.dup
      successful.each {|c|
        case c[:elem]
        when :input
          case c[:type]
          when /\Aradio\z/i
            count_radio[c[:name]] += 1
            radio_nonempty.delete(c[:name])
          when /\Asubmit\z/i
            count_submit += 1
          when /\Aimage-x\z/i
            count_submit += 1
            image_x_basenames << c[:name][0...-2]
          when /\Aimage-y\z/i
            image_y_basenames << c[:name][0...-2]
          end
        when :option
          unless c[:select][:multiple]
            count_option[[c[:select], c[:select].object_id]] += 1
            select_nonempty.delete(c[:select][:name])
          end
        when :button
          case c[:type]
          when /\Asubmit\z/i
            count_submit += 1
          end
        end
      }
      count_radio.each {|name, count|
        raise QueryValidationFailure,
          "multiple radio buttons selected: #{name.inspect}" if 1 < count
      }
      raise QueryValidationFailure,
        "multiple submits selected" if 1 < count_submit
      if count_submit == 0 && !@other_submits
        raise QueryValidationFailure, "no submit selected"
      end
      count_option.each {|(select, select_id), count|
        raise QueryValidationFailure,
          "multiple options selected: #{select[:name].inspect}" if 1 < count
      }
      if image_x_basenames.sort != image_y_basenames.sort
        diffs = (image_x_basenames - image_y_basenames) |
                (image_y_basenames - image_x_basenames)
        diff.sort!
        raise QueryValidationFailure,
          "non-pair image position: selected: #{diffs.map {|d| d.inspect }.join(' ')}"
      end
      unless radio_nonempty.empty?
        raise QueryValidationFailure,
          "radio button not checked: #{radio_nonempty.map {|d| d.inspect }.join(' ')}"
      end
      unless select_nonempty.empty?
        raise QueryValidationFailure,
          "menu not selected: #{select_nonempty.map {|d| d.inspect }.join(' ')}"
      end
    end

    def corresponding_control?(control, name, val)
      return false if control[:name] != name
      if fixed_value_control?(control)
        v1 = control[:value]
        v1 = HTree::Text.new(v1) unless HTree::Text === v1
        v2 = val
        v2 = HTree::Text.new(v2) unless HTree::Text === v2
        if v1 != v2
          return false
        end
      else
        begin
          validate_value(control, name, val)
        rescue QueryValidationFailure
          return false
        end
      end
      return true
    end

    def fixed_value_control?(control)
      return true if control[:readonly]
      case control[:elem]
      when :input
        case control[:type]
        when /\Atext\z/i then false
        when /\Apassword\z/i then false
        when /\Acheckbox\z/i then true
        when /\Aradio\z/i then true
        when /\Asubmit\z/i then true
        when /\Areset\z/i then true
        when /\Afile\z/i then false
        when /\Ahidden\z/i then true
        when /\Aimage-x\z/i then false
        when /\Aimage-y\z/i then false
        when /\Aimage\z/i then true
        when /\Abutton\z/i then true
        else
          raise ArgumentError,
            "unexpected form input type: #{control[:type].inspect}"
        end
      when :button then true
      when :option then true
      when :textarea then false
      else
        raise ArgumentError,
          "unexpected form control element: #{control[:elem].inspect}"
      end
    end

    def always_successful?(control)
      return false if control[:disabled]
      case control[:elem]
      when :input
        case control[:type]
        when /\Atext\z/i then true
        when /\Apassword\z/i then true
        when /\Acheckbox\z/i then false
        when /\Aradio\z/i then false
        when /\Asubmit\z/i then false
        when /\Areset\z/i then false
        when /\Afile\z/i then false # xxx
        when /\Ahidden\z/i then true
        when /\Aimage-x\z/i then false
        when /\Aimage-y\z/i then false
        when /\Aimage\z/i then false
        when /\Abutton\z/i then false
        else
          raise ArgumentError,
            "unexpected form input type: #{control[:type].inspect}"
        end
      when :button then false
      when :option then false
      when :textarea then true
      else
        raise ArgumentError,
          "unexpected form control element: #{control[:elem].inspect}"
      end
    end

    def validate_value(control, name, val)
      case control[:elem]
      when :input
        case control[:type]
        when /\A(?:text|password)\z/i
          if control[:maxlength] && control[:maxlength] < val.length
            # xxx: this is # of bytes instead of # of characters.
            raise QueryValidationFailure, "longer than maxlength: #{name.inspect}"
          end
        when /\Afile\z/i
          # xxx: check control[:accept] and @accept_content_type
          raise ArgumentError, "file upload not supported yet"
        when /\Aimage-[xy]\z/i
          if /\A[0-9]+\z/ !~ val
            raise QueryValidationFailure, "non-number click-position: #{name.inspect}"
          end
        else
          raise ArgumentError,
            "unexpected form input type: #{control[:type].inspect}"
        end
      when :textarea
      else
        raise ArgumentError,
          "unexpected form control element: #{control[:elem].inspect}"
      end
    end

  end
end
