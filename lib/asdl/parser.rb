require_relative 'lexer'
require_relative 'ast'
require_relative 'visitor_base'


class ASDL::SyntaxError < StandardError

  def initialize(message, lineno)
    msg = "#{message} (found on line #{lineno})"
    super(msg)
    @lineno = lineno
  end


end

module ASDL

  class Parser

    def self.parse(filename)
      mod = File.open(filename) do |f|
        parser = new()
        parser.parse(f)
      end
      mod
    end


    attr_accessor :cur_token
    attr_reader :tokenizer, :lexer,:tokenizer_klazz

    def initialize(tokenizer_klazz: Lexer.new)
      @tokenizer_klazz = tokenizer_klazz
      @cur_token = nil
    end

    def parse(buf)
      buf = buf.read if buf.class == File
      @tokenizer = tokenizer_klazz.lex(buf)
      _advance()

      _parse_module
    end


    def _advance()
      begin
        cur_value = if cur_token.nil?
                      nil
                    else
                      cur_token.value
                    end

        token = @tokenizer.next
        @cur_token = token
      rescue StopIteration
        @cur_token = nil
      rescue StandardError => e
         raise e.message
      end
      cur_value
    end


    def _at_keyword(keyword)
      return false unless cur_token
      cur_token.name == :TYPEID && cur_token.value == keyword
    end

    def _parse_module
      if self._at_keyword('module')
        self._advance
      else
        raise ASDL::SyntaxError.new(%[Expected "module" (found #{cur_token.value})], cur_token.line)
      end

      name = _match(_id_kinds)
      _match(:LBRACE)
      defs = _parse_definitions()
      _match(:RBRACE)
      Module.new(name,defs)
    end


    def _parse_definitions
      defs = []
      while cur_token.name == :TYPEID
        typename = _advance()
        _match(:EQUALS)
        type = _parse_type()
        defs << Type.new(typename, type)
      end
      return defs
    end


    def _parse_type
      if cur_token.name == :LPAREN
        # if we see a (, it's a product
        return _parse_product
      else #sum - look for ConstructorId
        sumlist = [ Constructor.new( _match(:CONSTRUCTID),
                                     _parse_optional_fields())]
      end
      while cur_token.name == :PIPE
        _advance()
        sumlist << Constructor.new( _match(:CONSTRUCTID),
                                    _parse_optional_fields())

      end
      Sum.new( sumlist, _parse_optional_attributes())
    end

    def _parse_product
      Product.new(_parse_fields(), _parse_optional_attributes)
    end


    def _parse_fields
      fields = []
      _match(:LPAREN)
      while cur_token.name == :TYPEID
        typename = _advance()
        is_seq, is_opt = _parse_optional_field_quantifiers()
        if _id_kinds.include? cur_token.name
          id = _advance()
        else
          id = nil
        end
        fields << Field.new(typename, id, seq: is_seq, opt: is_opt)
        if cur_token.name == :RPAREN
          break
        elsif cur_token.name == :COMMA
          _advance()
        end
      end

      _match(:RPAREN)
      fields
    end

    def _parse_optional_fields
      if cur_token.name == :LPAREN
        _parse_fields
      else
        nil
      end
    end

    def _parse_optional_attributes
      if _at_keyword('attributes')
        _advance()
        return _parse_fields
      else
        nil
      end
    end

    def _parse_optional_field_quantifiers
      is_seq, is_opt = false, false
      if cur_token.name == :ASTERISK
        is_seq = true
        _advance
      elsif cur_token.name == :QUESTION
        is_opt = true
        _advance
      end
      [is_seq, is_opt]
    end




    def _id_kinds
      @_id_kinds ||= [:CONSTRUCTID, :TYPEID]
    end


    def _match(kind)
      if ((kind.class == Array) && (kind.include? cur_token.name)) or (cur_token.name == kind)
        myvalue = cur_token.value
        _advance()
        return myvalue
      else
        msg = "Unmatched #{kind} (found #{cur_token.name}"
        raise ASDL::SyntaxError.new(msg, cur_token.line)
      end
    end

  end

end
