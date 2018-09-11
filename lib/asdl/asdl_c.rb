require_relative 'visitor_base'


module ASDL

  class TypeDefVisitor < EmitVisitor

    def visit_Module(mod)
      mod.defns.each{ |dfn| visit(dfn)}
    end

    def visit_Type(type, depth = 0)
      self.visit(type.value, type.name, depth)
    end

    def visit_Sum(sum,name,depth)
      if simple_sum?(sum)
        self.simple_sum(sum,name,depth)
      else
        self.sum_with_constructors(sum,name,depth)
      end

    end

    def simple_sum(sum,name,depth)
      enums = []
      sum.types.each_with_index do |t, idx|
        type = t
        enums.append("%s=%d" % [t.name, idx + 1])
      end
      enums = enums.join(", ")
      ctype = get_c_type(name)
      s = "typedef enum _#{name} { #{enums} } #{ctype};"
      self.emit(s,depth)
      self.emit("", depth)

    end

    def sum_with_constructors(sum,name,depth)
      ctype = get_c_type(name)
      s = "typedef struct _#{name} *#{ctype};"
      emit(s, depth)
      emit("",depth)

      def visit_Product(product,name,depth)
        ctype = get_c_type(name)
        s = "typedef struct _#{name} *#{ctype};"
        emit(s,depth)
        emit("",depth)
      end

    end

  end


  # Visitor to generate typedefs for AST.
  class StructVisitor < EmitVisitor

    def visit_Module(mod)
      mod.defns.each{|dfn| visit(dfn)}
    end

    def visit_Type(type, depth=0)
      self.visit(type.value, type.name, depth)
    end

    def visit_Sum(sum,name,depth)
      unless simple_sum?(sum)
        sum_with_constructors(sum,name,depth)
      end

    end

    def enum_string_from_types(types, prefix: "", suffix: "")
      enum = []
      types.each_with_index do |t, idx|
        enum << "#{prefix}#{t.name}#{suffix}=#{idx + 1}"
      end
      enum.join(", ")
    end


    def sum_with_constructors(sum,name,depth)
      enum_string = enum_string_from_types(sum.types, suffix: "_kind")
      emit "enum _#{name}_kind { #{enum_string} };"
      emit("struct _#{name} {")
      emit("enum _#{name}_kind kind;", depth +1)
      emit("union {", depth + 1)
      #  binding.pry if name == "stmt"
      sum.types.each{|t| visit(t, depth + 2)}
      emit("} v;", depth + 1)
      sum.attributes.each do |field|
        type = field.type.to_s
        raise unless ASDL.builtin_type? type
        emit("#{type} #{field.name};", depth + 1)
      end
      emit("};")
      emit("")
    end


    def visit_Constructor(cons,depth)
      unless cons.fields.empty?
        emit("struct {", depth)

        cons.fields.each{|f| visit(f, depth + 1)}
        emit("} #{cons.name};", depth)
        emit("", depth)
      end
    end


    def visit_Field(field,depth)
      ctype = get_c_type(field.type)
      name =  field.name
      if field.seq?
        if field.type == 'cmpop'
          emit("asdl_int_seq *#{name};", depth)
        else
          emit("asdl_seq *#{name};", depth)
        end
      else
        emit("#{ctype} #{name};", depth)
      end
    end

    def visit_Product(product, name, depth)
      emit("struct _#{name} {", depth)
      product.fields.each{|f| visit(f, depth + 1)}
      product.attributes.each do |field|
        type = field.type.to_s
        raise unless ASDL.builtin_type? type
        emit("#{type} #{field.name}", depth + 1)
      end
      emit("};", depth)
      emit("", depth)
    end

  end

  # Generate function prototypes for the .h file"
  class PrototypeVisitor < EmitVisitor


    def visit_Module(mod)
      mod.defns.each{|dfn| visit(dfn)}
    end

    def visit_Type(type)
      visit(type.value, type.name)
    end

    def visit_Sum(sum,name)
      if simple_sum?(sum)
      #pass
      else
        sum.types.each{|t| visit(t, name, sum.attributes)}
      end
    end


    # returns list of C argument into, one for each field
    # argument info is 3-tuple of a C type, variable name, and flag
    # that is true if type can be null
    def get_args(fields)
      args = []
      unnamed = []
      fields.each do |f|
        if f.name.nil?
          name = f.type
          c = unnamed[name] = unnamed.fetch(name,0) + 1
          if c > 1
            name = "name%d" % [c -1]
          end
        else
          name = f.name
        end
        if f.seq?
          if f.type == 'cmpop'
            ctype = "asdl_int_seq *"
          else
            ctype = "asdl_seq *"
          end
        else
          ctype = get_c_type(f.type)
        end
        args.append( [ctype, name, f.opt || f.seq ])
      end
      return args
    end

    def visit_Constructor(cons,type , attrs)
      args = get_args(cons.fields)
      attrs = get_args(attrs)
      ctype = get_c_type(type)
      emit_function(cons.name, ctype, args, attrs)
    end

    def emit_function(name, ctype, args, attrs, union = true)
      args = args + attrs
      if args
        argstr = args.map{|atype,aname| "#{atype} #{aname}"}.join(", ")
        argstr << ", PyArena *arena"
      else
        argstr = "PyArena *arena"
      end
      margs = "a0"
      1.upto(args.size) do |idx|
        margs += ", a%d" % idx
      end
      emit("#define %s(%s) _Py_%s(%s)" % [name,margs,name,margs], 0, reflow=false)
      emit("%s _Py_%s(%s);" % [ctype, name, argstr],0)
    end

    def visit_Product(prod,name)
      emit_function(name, get_c_type(name),
                    self.get_args(prod.fields), [], union=false)
    end

  end


  #visitor to generate constructor functions for AST"
  class FunctionVisitor < PrototypeVisitor

    def emit_function(name,ctype,args,attrs, union = true)
      argstr = (args + attrs).map{ |atype, aname| "#{atype} #{aname}"}.join(", ")

      if argstr
        argstr = "#{argstr}, PyArena *arena"
      else
        argstr = "PyArena *arena"
      end
      emit("#{ctype}")
      emit("#{name}(#{argstr})")
      emit("{")
      emit("#{ctype} p;", 1)
      args.each do |argtype, argname, opt|
        if not opt and argtype != "int"
          emit("if (!#{argname}) {", 1)
          emit("PyErr_SetString(PyEXC_ValueError,", 2)
          msg = "field #{argname} is required for #{name}"
          emit("           #{msg}",2, false)
          emit('return NULL;', 2)
          emit('}',1)
        end
      end
      emit("p=(#{ctype})PyArena_Malloc(arena, sizeof(*p));", 1)
      emit("if (!p)", 1)
      emit("return NULL;", 2)
      if union
        emit_body_union(name,args, attrs)
      else
        emit_body_struct(name,args,attrs)
      end
      emit("return p;", 1)
      emit("}")
      emit("")
    end


    def emit_body_union(name,args,attrs)
      emit("p=>kind=#{name}_kind;" , 1)
      args.each do |argtype, argname, opt|
        emit("p->v.%s.%s = %s;" % [name, argname, argname] , 1)
      end
      attrs.each do |argtype, argname, opt|
        emit("p->%s = %s;" % [argname, argname], 1)
      end
    end


    def emit_body_struct(name,args,attrs)
      args.each do |argtype,argname, opt|
        emit("p->%s = %s;" % [argname, argname], 1)
      end
      attrs.each do |argtype, argname, opt|
        emit("p->%s = %s;" % [argname, argname], 1)
      end
    end


  end

  class PickleVisitor < EmitVisitor

    def visit_Module(mod)
      mod.defns.each{|dfn| visit(dfn)}
    end

    def visit_Type(type)
      visit(type.value, type.name)
    end

    def visit_Sum(sum,name)
    end


    def visit_Product(sum,name)
    end

    def visit_Constructor(cons,name)
    end

    def visit_Field(sum)
    end

  end


  class Obj2ModPrototypeVisitor < PickleVisitor

    def visit_Product(prod,name)
      code = "static int obj2ast_%s(PyObject* obj, %s* out, PyArena* arena);"
      emit(code % [name, get_c_type(name)], 0)
    end


    def visit_Sum(prod,name)
      visit_Product(prod,name)
    end

  end

  class Obj2ModVisitor < PickleVisitor

    def func_header(name)
      ctype = get_c_type(name)
      emit("int")
      emit("obj2ast#{name}(PyObject* obj, #{ctype}* out, PyArena* arena)")
      emit("{")
      emit("int isinstance;",1)
      emit("",0)
    end

    def sum_trailer(name, add_label=false)
      emit("",0)

    end


  end





end
