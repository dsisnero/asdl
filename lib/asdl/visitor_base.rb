require 'set'
require_relative 'reflow'
require 'pry' if $DEBUG


module ASDL

  @builtin_types = Set['identifier', 'string', 'bytes', 'int', 'object', 'singleton']

  class << self
    def builtin_types
      @builtin_types
    end

    def builtin_type?(t)
      @builtin_types.include? t
    end


    def chain_of_visitors(*visitors)
      ChainOfVisitors.new(visitors)
    end

  end


  class VisitorBase

    def self.chain_of_visitors(*visitors)
      ChainOfVisitors.new(visitors)
    end

    attr_reader :cache


    def initialize
      @cache = {}
    end

    def visit(obj, *args)
      klass = obj.class
      meth = cache[klass]
      unless meth
        class_name = klass.name.sub("ASDL::","")
        methname = "visit_#{class_name}"
        meth =  self.method(methname) rescue nil
        cache[klass] = meth
      end
      if meth
        begin
          meth.call(obj,*args)
        rescue StandardError => e
          puts "Error visiting #{obj}: #{e.message}"
          if $DEBUG
            puts e
            puts e.backtrace
          end
        end
      end
    end

    def get_c_type(name)
      if ASDL.builtin_type?( name)
        name
      else
        return "#{name}_ty"
      end
    end

     # Return true if sum is a simple
    # A sum is simple if its types have no fields
    # unaryop = Invert | Not | UADD |USub
    def simple_sum?(sum)
      sum.types.all?{|t| t.fields.empty?}
    end

  end

  class ChainOfVisitors

    attr_reader :visitors

    def initialize(visitors)
      @visitors = visitors
    end

    def visit(object)
      visitors.each do |v|
        v.emit_comment{ "Generated from #{v.class}"}
        v.visit(object)
        v.emit("",0)
      end
    end

  end


  class EmitVisitor < ASDL::VisitorBase

    attr_reader :file, :identifiers
    attr_reader :identifier, :reflow_klass, :tabsize, :file

    def self.for_file(f, tabsize: 4, max_col: 80)
      visitor = new(f, tabsize, max_col)
    end

    def initialize(file, tabsize: 4, max_col: 80 , reflow: nil)
      @file = file
      @identifiers = Set.new
      @tabsize = tabsize
      @max_col = max_col
      @reflow_klass = reflow || init_reflow(tabsize, max_col)
      super()
    end

    def init_reflow(tab,col)
      Reflow.new(tabsize: tab,max_col: col)
    end

    def space_before(depth)
      (" " * tabsize * depth)
    end

    def emit_comment
      emit("/* ")
      cmt = yield
      emit(cmt)
      emit("*/\n")
    end

    def reflow_lines(s,depth)
      reflow_klass.reflow_lines(s, depth)
    end

    def emit_identifier(name)
      lname = name.to_s
      return if identifiers.include? lname
      emit("_Py_IDENTIFIER(#{lname});")
      identifiers << lname
    end

    def emit(s, depth=0, reflow=true)
      if reflow
        #   binding.pry if s.size > 80
        lines = reflow_lines(s,depth)
      else
        lines = [s]
      end
      lines.each do |line|
        line = "#{space_before(depth)}#{line}\n"
        file.write line
      end
    end

  end


end
