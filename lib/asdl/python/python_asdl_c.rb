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
      argstr = (args + attrs).map{ |atype, aname,_| "#{atype} #{aname}"}.join(", ")

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
          emit("PyErr_SetString(PyExc_ValueError,", 2)
          msg = "field #{argname} is required for #{name}"
          emit(%[                "#{msg}");],2, false)
          emit('return NULL;', 2)
          emit('}',1)
        end
      end
      emit("p = (#{ctype})PyArena_Malloc(arena, sizeof(*p));", 1)
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
      emit("p->kind = #{name}_kind;" , 1)
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
      # there's really nothing more we can do if this fails ...
      error = "expected some sort of %s, but got %%R" % name
      str = %[PyErr_Format(PyExc_TypeError, "#{error}", obj);]
      emit(str , 1, false)
      if add_label
        emit("failed:", 1)
        emit("Py_XDECREF(tmp);", 1)
      end
      emit("return 1;", 1)
      emit("}", 0)
      emit("", 0)
    end

    def simple_sum(sum,name)
      func_header(name)
      sum.types.each do |t|
        emit("isinstance = PyObject_IsInstance(obj, (PyObject *)#{t.name}_type);",1)
        emit("if (isinstance == -1) {", 1)
        emit("return 1;", 2)
        emit("}", 1)
        emit("if (isinstance) {", 1)
        emit("*out = #{t.name};", 2)
        emit("return 0;", 2)
        emit("}", 1)
      end
      sum_trailer(name)
    end

    def build_args(fields)
      (fields + ["arena"]).join(", ")
    end

    def complex_sum(sum,name)
      func_header(name)
      emit("PyObject *tmp = NULL;", 1)
      sum.attributes.each{|a| visit_attribute_declaration(a,name, sum: sum)}
      emit("", 0)
      # XXX: should we only do this for 'expr'?
      emit("if (obj == Py_None) {", 1)
      emit("*out = NULL;", 2)
      emit("return 0;", 2)
      emit("}", 1)
      sum.attributes.each{|a| visit_Field(a,name,sum: sum, depth: 1)}
      sum.types.each do |t|
        line = "isinstance = PyObject_IsInstance(obj, (PyObject*)%s_type);"
        emit(line % [t.name,], 1)
        emit("if (isinstance == -1) {", 1)
        emit("return 1;", 2)
        emit("}", 1)
        emit("if (isinstance) {", 1)
        t.fields.each{|f| visit_field_declaration(f,t.name,sum: sum, depth: 2) }
        emit("", 0)
        t.fields.each{|f| visit_Field(f, t.name, sum: sum, depth: 2)}
        args = t.fields.map{|f| f.name} + sum.attributes.map{|a| a.name}
        emit("*out = %s(%s);" % [t.name, build_args(args)], 2)
        emit("if (*out == NULL) goto failed;", 2)
        emit("return 0;", 2)
        emit("}", 1)
      end

      self.sum_trailer(name, true)
    end

    def visit_attribute_declaration(a,name,sum: nil)
      ctype = get_c_type(a.type)
      emit("%s %s;" % [ctype, a.name], 1)
    end


    def visit_Sum(sum, name)
      if simple_sum?(sum)
        simple_sum(sum, name)
      else
        complex_sum(sum, name)
      end
    end

    def visit_Product(prod, name)
      ctype = get_c_type(name)
      emit("int", 0)
      emit("obj2ast_%s(PyObject* obj, %s* out, PyArena* arena)" % [name, ctype], 0)
      emit("{", 0)
      emit("PyObject* tmp = NULL;", 1)
      prod.fields.each{|f| visit_field_declaration(f,name, prod: prod, depth: 1)}
      emit("", 0)
      prod.fields.each{|f| visit_Field(f,name, prod: prod, depth: 1) }
      args = prod.fields.map{|f| f.name}
      emit("*out = %s(%s);" % [name, build_args(args)], 1)
      emit("return 0;", 1)
      emit("failed:", 0)
      emit("Py_XDECREF(tmp);", 1)
      emit("return 1;", 1)
      emit("}", 0)
      emit("", 0)
    end

    def visit_field_declaration(field, name, sum: nil, prod: nil, depth: 0)
      ctype = get_c_type(field.type)
      if field.seq?
        if simple_type?(field)
          emit("asdl_int_seq* #{field.name};" , depth)
        else
          emit("asdl_seq* #{field.name};", depth)
        end
      else
        ctype = get_c_type(field.type)
        emit("%s %s;" % [ctype, field.name], depth)
      end
    end

    # can the members of this list be determined automatically
    def is_simple_sum?(field)
      %w(expr_context boolop operator unaryop cmpop).include? field.type
    end

    def numeric?(field)
      %w(int boolean).include? get_c_type(field.type)
    end

    def simple_type?(field)
      is_simple_sum?(field) or numeric?(field)
    end

    def visit_Field(field, name, sum: nil, prod: nil, depth: 0)
      ctype = get_c_type(field.type)
      if field.opt?
        check = "exists_not_none(obj, &PyId_%s)" % [field.name]
      else
        check = "_PyObject_HasAttrId(obj, &PyId_%s)" % [field.name]
      end
      emit("if (#{check}) {" , depth, false)
      emit("int res;", depth+1)
      if field.seq?
        emit("Py_ssize_t len;", depth+1)
        emit("Py_ssize_t i;", depth+1)
      end
      emit("tmp = _PyObject_GetAttrId(obj, &PyId_#{field.name});" , depth+1)
      emit("if (tmp == NULL) goto failed;", depth+1)
      if field.seq?
        emit("if (!PyList_Check(tmp)) {", depth+1)
        msg = %[PyErr_Format(PyExc_TypeError, "#{name} field \\\"#{field.name}\\" must be a list, not a %.200s", tmp->ob_type->tp_name);]
        emit(msg, depth + 2, false)
        emit("goto failed;", depth+2)
        emit("}", depth+1)
        emit("len = PyList_GET_SIZE(tmp);", depth+1)
        if simple_type?(field)
          emit("#{field.name} = _Py_asdl_int_seq_new(len, arena);" , depth+1)
        else
          emit("#{field.name} = _Py_asdl_seq_new(len, arena);" , depth+1)
        end

        emit("if (%s == NULL) goto failed;" % [field.name], depth+1)
        emit("for (i = 0; i < len; i++) {", depth+1)
        emit("%s value;" % [ctype], depth+2)
        emit("res = obj2ast_%s(PyList_GET_ITEM(tmp, i), &value, arena);" %
             [field.type], depth+2, false)
        emit("if (res != 0) goto failed;", depth+2)
        emit("asdl_seq_SET(#{field.name}, i, value);" , depth+2)
        emit("}", depth+1)
      else
        emit("res = obj2ast_%s(tmp, &%s, arena);" %
             [field.type, field.name], depth+1)
        emit("if (res != 0) goto failed;", depth+1)
      end
      emit("Py_CLEAR(tmp);", depth+1)
      emit("} else {", depth)
      if not field.opt?
        message = "required field \\\"%s\\\" missing from %s" % [field.name, name]
        format = "PyErr_SetString(PyExc_TypeError, \"%s\");"
        emit(format % [message], depth+1, false)
        emit("return 1;", depth+1)
      else
        if numeric?(field)
          emit("%s = 0;" % [field.name], depth+1)
        elsif not simple_type?(field)
          emit("%s = NULL;" % [field.name], depth+1)
        else
          raise TypeError("could not determine the default value for #{field.name}")
        end
      end
      emit("}", depth)
    end

  end


  class MarshalPrototypeVisitor < PickleVisitor

    def prototype(sum, name)
      ctype = get_c_type(name)
      self.emit("static int marshal_write_#{name}(PyObject **, int *, #{ctype});",0)
    end

    def visit_Sum(sum,name)
      prototype(sum,name)
    end

  end

  class PyTypesDeclareVisitor < PickleVisitor

    def visit_Product(prod, name)
      emit("static PyTypeObject *#{name}_type;", 0)
      emit("static PyObject* ast2obj_#{name}(void*);" , 0)
      unless prod.attributes.empty?
        prod.attributes.each{|a| emit_identifier(a.name)}
        emit("static char *#{name}_attributes[] = {" , 0)
        prod.attributes.each do |a|
          emit(%["#{a.name}",], 1)
        end
        emit("};", 0)
      end
      unless prod.fields.empty?
        prod.fields.each{|f| emit_identifier(f.name)}
        emit("static char *#{name}_fields[]={" ,0)
        prod.fields.each do |f|
          emit(%["#{f.name}",], 1)
        end
        emit("};", 0)
      end
    end

    def visit_Sum(sum, name)
      emit("static PyTypeObject *#{name}_type;" , 0)
      unless sum.attributes.empty?
        sum.attributes.each{|a| emit_identifier(a.name)}
        emit("static char *#{name}_attributes[] = {" , 0)
        sum.attributes.each do |a|
          emit(%["#{a.name}",], 1)
        end
        emit("};", 0)
      end
      ptype = "void*"
      if simple_sum?(sum)
        ptype = get_c_type(name)
        tnames = []
        tnames = sum.types.map{|t| "#{t.name}_singleton"}
        tnames = tnames.join(", *")
        emit("static PyObject *%s;" % [tnames], 0)
      end
      emit("static PyObject* ast2obj_#{name}(#{ptype});" , 0)
      sum.types.each{|t| visit_Constructor(t,name)}
    end

    def visit_Constructor(cons, name)
      emit("static PyTypeObject *#{cons.name}_type;" , 0)
      unless cons.fields.empty?
        cons.fields.each{|t| emit_identifier(t.name)}
        emit("static char *#{cons.name}_fields[]={" , 0)
        cons.fields.each do |t|
          emit(%["#{t.name}",], 1)
        end
        emit("};",0)
      end
    end

  end



  class PyTypesVisitor < PickleVisitor

    def visit_Module(mod)
      str = <<-C_CODE
typedef struct {
    PyObject_HEAD
    PyObject *dict;
} AST_object;

static void
ast_dealloc(AST_object *self)
{
    Py_CLEAR(self->dict);
    Py_TYPE(self)->tp_free(self);
}

static int
ast_traverse(AST_object *self, visitproc visit, void *arg)
{
    Py_VISIT(self->dict);
    return 0;
}

static void
ast_clear(AST_object *self)
{
    Py_CLEAR(self->dict);
}

static int
ast_type_init(PyObject *self, PyObject *args, PyObject *kw)
{
    _Py_IDENTIFIER(_fields);
    Py_ssize_t i, numfields = 0;
    int res = -1;
    PyObject *key, *value, *fields;
    fields = _PyObject_GetAttrId((PyObject*)Py_TYPE(self), &PyId__fields);
    if (!fields)
        PyErr_Clear();
    if (fields) {
        numfields = PySequence_Size(fields);
        if (numfields == -1)
            goto cleanup;
    }
    res = 0; /* if no error occurs, this stays 0 to the end */
    if (PyTuple_GET_SIZE(args) > 0) {
        if (numfields != PyTuple_GET_SIZE(args)) {
            PyErr_Format(PyExc_TypeError, "%.400s constructor takes %s"
                         "%zd positional argument%s",
                         Py_TYPE(self)->tp_name,
                         numfields == 0 ? "" : "either 0 or ",
                         numfields, numfields == 1 ? "" : "s");
            res = -1;
            goto cleanup;
        }
        for (i = 0; i < PyTuple_GET_SIZE(args); i++) {
            /* cannot be reached when fields is NULL */
            PyObject *name = PySequence_GetItem(fields, i);
            if (!name) {
                res = -1;
                goto cleanup;
            }
            res = PyObject_SetAttr(self, name, PyTuple_GET_ITEM(args, i));
            Py_DECREF(name);
            if (res < 0)
                goto cleanup;
        }
    }
    if (kw) {
        i = 0;  /* needed by PyDict_Next */
        while (PyDict_Next(kw, &i, &key, &value)) {
            res = PyObject_SetAttr(self, key, value);
            if (res < 0)
                goto cleanup;
        }
    }
  cleanup:
    Py_XDECREF(fields);
    return res;
}

/* Pickling support */
static PyObject *
ast_type_reduce(PyObject *self, PyObject *unused)
{
    PyObject *res;
    _Py_IDENTIFIER(__dict__);
    PyObject *dict = _PyObject_GetAttrId(self, &PyId___dict__);
    if (dict == NULL) {
        if (PyErr_ExceptionMatches(PyExc_AttributeError))
            PyErr_Clear();
        else
            return NULL;
    }
    if (dict) {
        res = Py_BuildValue("O()O", Py_TYPE(self), dict);
        Py_DECREF(dict);
        return res;
    }
    return Py_BuildValue("O()", Py_TYPE(self));
}

static PyMethodDef ast_type_methods[] = {
    {"__reduce__", ast_type_reduce, METH_NOARGS, NULL},
    {NULL}
};

static PyGetSetDef ast_type_getsets[] = {
    {"__dict__", PyObject_GenericGetDict, PyObject_GenericSetDict},
    {NULL}
};

static PyTypeObject AST_type = {
    PyVarObject_HEAD_INIT(&PyType_Type, 0)
    "_ast.AST",
    sizeof(AST_object),
    0,
    (destructor)ast_dealloc, /* tp_dealloc */
    0,                       /* tp_print */
    0,                       /* tp_getattr */
    0,                       /* tp_setattr */
    0,                       /* tp_reserved */
    0,                       /* tp_repr */
    0,                       /* tp_as_number */
    0,                       /* tp_as_sequence */
    0,                       /* tp_as_mapping */
    0,                       /* tp_hash */
    0,                       /* tp_call */
    0,                       /* tp_str */
    PyObject_GenericGetAttr, /* tp_getattro */
    PyObject_GenericSetAttr, /* tp_setattro */
    0,                       /* tp_as_buffer */
    Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE | Py_TPFLAGS_HAVE_GC, /* tp_flags */
    0,                       /* tp_doc */
    (traverseproc)ast_traverse, /* tp_traverse */
    (inquiry)ast_clear,      /* tp_clear */
    0,                       /* tp_richcompare */
    0,                       /* tp_weaklistoffset */
    0,                       /* tp_iter */
    0,                       /* tp_iternext */
    ast_type_methods,        /* tp_methods */
    0,                       /* tp_members */
    ast_type_getsets,        /* tp_getset */
    0,                       /* tp_base */
    0,                       /* tp_dict */
    0,                       /* tp_descr_get */
    0,                       /* tp_descr_set */
    offsetof(AST_object, dict),/* tp_dictoffset */
    (initproc)ast_type_init, /* tp_init */
    PyType_GenericAlloc,     /* tp_alloc */
    PyType_GenericNew,       /* tp_new */
    PyObject_GC_Del,         /* tp_free */
};


static PyTypeObject* make_type(char *type, PyTypeObject* base, char**fields, int num_fields)
{
    PyObject *fnames, *result;
    int i;
    fnames = PyTuple_New(num_fields);
    if (!fnames) return NULL;
    for (i = 0; i < num_fields; i++) {
        PyObject *field = PyUnicode_FromString(fields[i]);
        if (!field) {
            Py_DECREF(fnames);
            return NULL;
        }
        PyTuple_SET_ITEM(fnames, i, field);
    }
    result = PyObject_CallFunction((PyObject*)&PyType_Type, "s(O){sOss}",
                    type, base, "_fields", fnames, "__module__", "_ast");
    Py_DECREF(fnames);
    return (PyTypeObject*)result;
}

static int add_attributes(PyTypeObject* type, char**attrs, int num_fields)
{
    int i, result;
    _Py_IDENTIFIER(_attributes);
    PyObject *s, *l = PyTuple_New(num_fields);
    if (!l)
        return 0;
    for (i = 0; i < num_fields; i++) {
        s = PyUnicode_FromString(attrs[i]);
        if (!s) {
            Py_DECREF(l);
            return 0;
        }
        PyTuple_SET_ITEM(l, i, s);
    }
    result = _PyObject_SetAttrId((PyObject*)type, &PyId__attributes, l) >= 0;
    Py_DECREF(l);
    return result;
}

/* Conversion AST -> Python */

static PyObject* ast2obj_list(asdl_seq *seq, PyObject* (*func)(void*))
{
    Py_ssize_t i, n = asdl_seq_LEN(seq);
    PyObject *result = PyList_New(n);
    PyObject *value;
    if (!result)
        return NULL;
    for (i = 0; i < n; i++) {
        value = func(asdl_seq_GET(seq, i));
        if (!value) {
            Py_DECREF(result);
            return NULL;
        }
        PyList_SET_ITEM(result, i, value);
    }
    return result;
}

static PyObject* ast2obj_object(void *o)
{
    if (!o)
        o = Py_None;
    Py_INCREF((PyObject*)o);
    return (PyObject*)o;
}
#define ast2obj_singleton ast2obj_object
#define ast2obj_identifier ast2obj_object
#define ast2obj_string ast2obj_object
#define ast2obj_bytes ast2obj_object

static PyObject* ast2obj_int(long b)
{
    return PyLong_FromLong(b);
}

/* Conversion Python -> AST */

static int obj2ast_singleton(PyObject *obj, PyObject** out, PyArena* arena)
{
    if (obj != Py_None && obj != Py_True && obj != Py_False) {
        PyErr_SetString(PyExc_ValueError,
                        "AST singleton must be True, False, or None");
        return 1;
    }
    *out = obj;
    return 0;
}

static int obj2ast_object(PyObject* obj, PyObject** out, PyArena* arena)
{
    if (obj == Py_None)
        obj = NULL;
    if (obj) {
        if (PyArena_AddPyObject(arena, obj) < 0) {
            *out = NULL;
            return -1;
        }
        Py_INCREF(obj);
    }
    *out = obj;
    return 0;
}

static int obj2ast_identifier(PyObject* obj, PyObject** out, PyArena* arena)
{
    if (!PyUnicode_CheckExact(obj) && obj != Py_None) {
        PyErr_SetString(PyExc_TypeError, "AST identifier must be of type str");
        return 1;
    }
    return obj2ast_object(obj, out, arena);
}

static int obj2ast_string(PyObject* obj, PyObject** out, PyArena* arena)
{
    if (!PyUnicode_CheckExact(obj) && !PyBytes_CheckExact(obj)) {
        PyErr_SetString(PyExc_TypeError, "AST string must be of type str");
        return 1;
    }
    return obj2ast_object(obj, out, arena);
}

static int obj2ast_bytes(PyObject* obj, PyObject** out, PyArena* arena)
{
    if (!PyBytes_CheckExact(obj)) {
        PyErr_SetString(PyExc_TypeError, "AST bytes must be of type bytes");
        return 1;
    }
    return obj2ast_object(obj, out, arena);
}

static int obj2ast_int(PyObject* obj, int* out, PyArena* arena)
{
    int i;
    if (!PyLong_Check(obj)) {
        PyErr_Format(PyExc_ValueError, "invalid integer value: %R", obj);
        return 1;
    }

    i = (int)PyLong_AsLong(obj);
    if (i == -1 && PyErr_Occurred())
        return 1;
    *out = i;
    return 0;
}

static int add_ast_fields(void)
{
    PyObject *empty_tuple, *d;
    if (PyType_Ready(&AST_type) < 0)
        return -1;
    d = AST_type.tp_dict;
    empty_tuple = PyTuple_New(0);
    if (!empty_tuple ||
        PyDict_SetItemString(d, "_fields", empty_tuple) < 0 ||
        PyDict_SetItemString(d, "_attributes", empty_tuple) < 0) {
        Py_XDECREF(empty_tuple);
        return -1;
    }
    Py_DECREF(empty_tuple);
    return 0;
}

static int exists_not_none(PyObject *obj, _Py_Identifier *id)
{
    int isnone;
    PyObject *attr = _PyObject_GetAttrId(obj, id);
    if (!attr) {
        PyErr_Clear();
        return 0;
    }
    isnone = attr == Py_None;
    Py_DECREF(attr);
    return !isnone;
}
C_CODE
      emit(str, 0, false)
      emit("static int init_types(void)",0)
      emit("{", 0)
      emit("static int initialized;", 1)
      emit("if (initialized) return 1;", 1)
      emit("if (add_ast_fields() < 0) return 0;", 1)
      mod.defns.each{|dfn| visit(dfn)}
      emit("initialized = 1;", 1)
      emit("return 1;", 1);
      emit("}", 0)
    end

    def visit_Product(prod,name)
      if !(prod.fields.empty?)
        fields = "#{name}_fields"
      else
        fields = "NULL"
      end
      emit(%[%s_type = make_type("%s", &AST_type, %s, %d);] % [name, name, fields, prod.fields.size], 1)
      emit("if (!#{name}_type) return 0;" , 1)
      unless prod.attributes.empty?
        emit("if (!add_attributes(%s_type, %s_attributes, %d)) return 0;" %
             [name, name, prod.attributes.size], 1)
      else
        emit("if (!add_attributes(#{name}_type, NULL, 0)) return 0;" , 1)
      end
    end

    def visit_Sum(sum,name)
      emit(%[%s_type = make_type("%s", &AST_type, NULL, 0);] %
           [name, name], 1)
      emit("if (!#{name}_type) return 0;" , 1)
      unless sum.attributes.empty?
        emit("if (!add_attributes(%s_type, %s_attributes, %d)) return 0;" %
             [name, name, sum.attributes.size], 1)
      else
        emit("if (!add_attributes(#{name}_type, NULL, 0)) return 0;" , 1)
      end

      simple = simple_sum?(sum)
      sum.types.each{|t| visit_Constructor(t,name,simple)}
    end

    def visit_Constructor(cons,name,simple)
      if !(cons.fields.empty?)
        fields = "#{cons.name}_fields"
      else
        fields = "NULL"
      end
      emit(%[%s_type = make_type("%s", %s_type, %s, %d);] %
           [cons.name, cons.name, name, fields, cons.fields.size], 1)
      emit("if (!#{cons.name}_type) return 0;" , 1)
      if simple
        emit("%s_singleton = PyType_GenericNew(%s_type, NULL, NULL);" %
             [cons.name, cons.name], 1)
        emit("if (!#{cons.name}_singleton) return 0;" , 1)
      end
    end

  end

  class ASTModuleVisitor < PickleVisitor

    def visit_Module(mod)
      emit("static struct PyModuleDef _astmodule = {", 0)
      emit('  PyModuleDef_HEAD_INIT, "_ast"', 0)
      emit("};", 0)
      emit("PyMODINIT_FUNC", 0)
      emit("PyInit__ast(void)", 0)
      emit("{", 0)
      emit("PyObject *m, *d;", 1)
      emit("if (!init_types()) return NULL;", 1)
      emit('m = PyModule_Create(&_astmodule);', 1)
      emit("if (!m) return NULL;", 1)
      emit("d = PyModule_GetDict(m);", 1)
      emit('if (PyDict_SetItemString(d, "AST", (PyObject*)&AST_type) < 0) return NULL;', 1)
      emit('if (PyModule_AddIntMacro(m, PyCF_ONLY_AST) < 0)', 1)
      emit("return NULL;", 2)
      mod.defns.each{|dfn| visit(dfn)}
      emit("return m;", 1)
      emit("}", 0)
    end

    def visit_Product(prod,name)
      add_obj(name)
    end

    def visit_Sum(sum,name)
      add_obj(name)
      sum.types.each{|t| visit_Constructor(t,name)}
    end

    def visit_Constructor(cons,name)
      add_obj(cons.name)
    end

    def add_obj(name)
      emit('if (PyDict_SetItemString(d, "%s", (PyObject*)%s_type) < 0) return NULL;' % [name, name], 1)
    end

  end

  class StaticVisitor < PickleVisitor

    attr_reader :code

    def initialize(f)
      super
      set_code
    end

    def visit(object)
      emit(code, 0, false)
    end

  end

  class ObjVisitor < PickleVisitor

    def func_begin(name)
      ctype = get_c_type(name)
      emit("PyObject*", 0)
      emit("ast2obj_%s(void* _o)" % (name), 0)
      emit("{", 0)
      emit("%s o = (%s)_o;" % [ctype, ctype], 1)
      emit("PyObject *result = NULL, *value = NULL;", 1)
      emit('if (!o) {', 1)
      emit("Py_INCREF(Py_None);", 2)
      emit('return Py_None;', 2)
      emit("}", 1)
      emit('', 0)
    end

    def func_end
      emit("return result;", 1)
      emit("failed:", 0)
      emit("Py_XDECREF(value);", 1)
      emit("Py_XDECREF(result);", 1)
      emit("return NULL;", 1)
      emit("}", 0)
      emit("", 0)
    end

    def visit_Sum(sum,name)
      if simple_sum?(sum)
        simple_sum(sum,name)
        return
      end
      func_begin(name)
      emit("switch (o->kind) {", 1)
      sum.types.each.with_index do |t, i|
        visit_Constructor(t, i + 1, name)
      end
      emit("}", 1)
      sum.attributes.each do |a|
        emit("value = ast2obj_%s(o->%s);" % [a.type, a.name], 1)
        emit("if (!value) goto failed;", 1)
        emit(%[if (_PyObject_SetAttrId(result, &PyId_#{a.name}, value) < 0)], 1)
        emit('goto failed;', 2)
        emit('Py_DECREF(value);', 1)
      end
      self.func_end()
    end

    def simple_sum(sum, name)
      emit("PyObject* ast2obj_%s(%s_ty o)" % [name, name], 0)
      emit("{", 0)
      emit("switch(o) {", 1)
      sum.types.each do |t|
        emit("case #{t.name}:" , 2)
        emit("Py_INCREF(#{t.name}_singleton);" , 3)
        emit("return #{t.name}_singleton;" , 3)
      end
      emit("default:", 2)
      emit('/* should never happen, but just in case ... */', 3)
      emit("PyErr_Format(PyExc_SystemError, \"unknown #{name} found\");" , 3, false)
      emit("return NULL;", 3)
      emit("}", 1)
      emit("}", 0)
    end

    def visit_Product(prod,name)
      self.func_begin(name)
      emit("result = PyType_GenericNew(#{name}_type, NULL, NULL);" , 1);
      emit("if (!result) return NULL;", 1)
      prod.fields.each{|f| visit_Field(f,name, 1, true)}
      prod.attributes.each do |a|
        emit("value = ast2obj_%s(o->%s);" % [a.type, a.name], 1)
        emit("if (!value) goto failed;", 1)
        emit(%[if (_PyObject_SetAttrId(result, &PyId_#{a.name}, value) < 0)] , 1)
        emit('goto failed;', 2)
        emit('Py_DECREF(value);', 1)
      end
      self.func_end()
    end

    def visit_Constructor(cons,enum,name)
      emit("case #{cons.name}_kind:" , 1)
      emit("result = PyType_GenericNew(#{cons.name}_type, NULL, NULL);" , 2);
      emit("if (!result) goto failed;", 2)
      cons.fields.each{|f| visit_Field(f,cons.name,2,false)}
      emit("break;", 2)
    end

    def visit_Field(field, name, depth,product)
      f_emit = ->(s,d){ emit(s, depth + d)}

      if product
        value = "o->#{field.name}"
      else
        value = "o->v.#{name}.#{field.name}"
      end
      self.set(field,value,depth)
      f_emit.call("if (!value) goto failed;", 0)
      f_emit.call(%[if (_PyObject_SetAttrId(result, &PyId_#{field.name}, value) == -1)], 0)
      f_emit.call("goto failed;", 1)
      f_emit.call("Py_DECREF(value);", 0)
    end

    def emit_sequence(field,value,depth,emit)
      emit("seq = %s;" % value, 0)
      emit("n = asdl_seq_LEN(seq);", 0)
      emit("value = PyList_New(n);", 0)
      emit("if (!value) goto failed;", 0)
      emit("for (i = 0; i < n; i++) {", 0)
      self.set("value", field, "asdl_seq_GET(seq, i)", depth + 1)
      emit("if (!value1) goto failed;", 1)
      emit("PyList_SET_ITEM(value, i, value1);", 1)
      emit("value1 = NULL;", 1)
      emit("}", 0)
    end

    def set(field,value,depth)
      if field.seq
        # XXX should really check for is_simple, but that requires a symbol table
        if field.type == "cmpop"
          # While the sequence elements are stored as void*,
          # ast2obj_cmpop expects an enum
          emit("{", depth)
          emit("Py_ssize_t i, n = asdl_seq_LEN(#{value});", depth+1)
          emit("value = PyList_New(n);", depth+1)
          emit("if (!value) goto failed;", depth+1)
          emit("for(i = 0; i < n; i++)", depth+1)
          # This cannot fail, so no need for error handling
          emit("PyList_SET_ITEM(value, i, ast2obj_cmpop((cmpop_ty)asdl_seq_GET(#{value}, i)));" ,
               depth+2, false)
          emit("}", depth)
        else
          emit("value = ast2obj_list(%s, ast2obj_%s);" % [value, field.type], depth)
        end
      else
        ctype = get_c_type(field.type)
        emit("value = ast2obj_#{field.type}(#{value});" , depth, false)
      end
    end

  end


  class PartingShots < StaticVisitor

    def set_code
      str = <<-CODE
PyObject* PyAST_mod2obj(mod_ty t)
{
    if (!init_types())
        return NULL;
    return ast2obj_mod(t);
}

/* mode is 0 for "exec", 1 for "eval" and 2 for "single" input */
mod_ty PyAST_obj2mod(PyObject* ast, PyArena* arena, int mode)
{
    mod_ty res;
    PyObject *req_type[3];
    char *req_name[] = {"Module", "Expression", "Interactive"};
    int isinstance;

    req_type[0] = (PyObject*)Module_type;
    req_type[1] = (PyObject*)Expression_type;
    req_type[2] = (PyObject*)Interactive_type;

    assert(0 <= mode && mode <= 2);

    if (!init_types())
        return NULL;

    isinstance = PyObject_IsInstance(ast, req_type[mode]);
    if (isinstance == -1)
        return NULL;
    if (!isinstance) {
        PyErr_Format(PyExc_TypeError, "expected %s node, got %.400s",
                     req_name[mode], Py_TYPE(ast)->tp_name);
        return NULL;
    }
    if (obj2ast_mod(ast, &res, arena) != 0)
        return NULL;
    else
        return res;
}

int PyAST_Check(PyObject* obj)
{
    if (!init_types())
        return -1;
    return PyObject_IsInstance(obj, (PyObject*)&AST_type);
}
CODE
      @code = str
    end


  end

end
