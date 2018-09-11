require_relative 'visitor_base'


module ASDL

  class CheckVisitor < VisitorBase

    def self.check(mod)
      visitor = new()
      visitor.visit(mod)
      visitor.types.keys.each do |t|
        if not(mod.types.include? t) and !(ASDL.built_in_type?(t))
          visitor.errors += 1
          uses = visitor.types[t].join(", ")
          puts "Undefined type #{t}, used in #{uses}"
        end
      end
      return visitor.errors <=0
    end

    attr_accessor :errors
    attr_reader  :types, :cons

    def initialize
      super()
      @cons = {}
      @errors = 0
      @types = {}
    end

    def visit_Module(mod)
      mod.defns.each do  |d|
        visit(d)
      end
    end

    def visit_Type(type)
      visit(type.value, type.name.to_s)
    end

    def visit_Sum(sum,name)
      sum.types.each{|t| visit(t,name)}
    end

    def visit_Constructor(cons, name)
      key = cons.name.to_s
      conflict = self.cons[key]
      unless conflict
        self.cons[key] = name
      else
        puts "Redefinition of constructor #{key}"
        puts "Defined in #{conflict} and #{name}"
        errors += 1
      end
      cons.fields.each{|f| self.visit(f, key)}
    end

    def visit_Field(field,name)
      key = field.type.to_s
      l = if self.types[key].nil?
            self.types[key] = []
          else
            self.types[key]
          end
      l << name
    end

    def visit_Product(prod,name)
      prod.fields.each{|f| visit(f,name)}
    end

  end

end
