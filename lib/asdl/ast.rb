module ASDL

  class AST

    attr_reader :value,:name

    def inspect
      raise NotImplementedError
    end

  end

  class Module < AST

    attr_reader :name, :defns, :types

    def initialize(name,defns)
      @name = name
      @defns = defns
      @types = defns.each_with_object({}) do |type,hsh|
        #    binding.pry
        hsh[type.name] = type.value
      end
    end

    def inspect
      "Module(#@name, #@defns)"
    end

  end

  class Type < AST

    attr_reader :name, :value

    def initialize(name, value)
      @name = name
      @value = value

    end

    def inspect
      "Type(#@name, #@value)"
    end

  end

  class Constructor < AST

    attr_reader :name, :fields

    def initialize(name, fields=nil)
      @name = name
      @fields = fields || []
    end

    def inspect
      "Constructor(#@name, #@fields)"
    end

  end

  class Field < AST

    attr_reader :type, :name, :seq, :opt

    def initialize(type, name = nil, seq: false, opt: false)
      @type = type
      @name = name
      @seq = seq
      @opt = opt
    end

    def seq?
      @seq
    end

    def opt?
      @opt
    end

    def inspect
      if seq
        extra = ", seq=True"
      elsif opt
        extra = ", opt = True"
      else
        extra = ""
      end
      if name
        return "Field(#{type}, #{name}#{extra})"
      else
        return "Field(#{type}#{extra})"
      end
    end

  end

  class Sum < AST

    attr_reader :types, :attributes

    def initialize(types, attributes = nil)
      @types = types
      @attributes = attributes || []
    end

    def inspect
      if @attributes.empty?
        return "Sum(#@types)"
      else
        return "Sum(#{@types}, #@attributes)"
      end
    end
  end


  class Product < AST

    attr_reader :fields,:attributes

    def initialize(fields, attributes = nil)
      @fields = fields
      @attributes = attributes || []
    end

    def inspect
      if @attributes.empty?
        return "Product(#{@fields})"
      else
        return "Product(#{@fields}, #@attributes)"
      end
    end

  end

end
