require_relative "visitor_base"

module Asdl
  class CheckVisitor < VisitorBase
    def self.check(mod)
      visitor = new
      visitor.visit(mod)
      visitor.types.keys.each do |t|
        if !mod.types.include?(t) and !Asdl.built_in_type?(t)
          visitor.errors += 1
          uses = visitor.types[t].join(", ")
          puts "Undefined type #{t}, used in #{uses}"
        end
      end
      visitor.errors <= 0
    end

    attr_accessor :errors
    attr_reader :types, :cons

    def initialize
      super()
      @cons = {}
      @errors = 0
      @types = {}
    end

    def visit_Module(mod)
      mod.defns.each do |d|
        visit(d)
      end
    end

    def visit_Type(type)
      visit(type.value, type.name.to_s)
    end

    def visit_Sum(sum, name)
      sum.types.each { |t| visit(t, name) }
    end

    def visit_Constructor(cons, name)
      key = cons.name.to_s
      conflict = self.cons[key]
      if conflict
        puts "Redefinition of constructor #{key}"
        puts "Defined in #{conflict} and #{name}"
        errors += 1
      else
        self.cons[key] = name
      end
      cons.fields.each { |f| visit(f, key) }
    end

    def visit_Field(field, name)
      key = field.type.to_s
      l = if types[key].nil?
        types[key] = []
      else
        types[key]
      end
      l << name
    end

    def visit_Product(prod, name)
      prod.fields.each { |f| visit(f, name) }
    end
  end
end
