require 'asdl/generator'
require_relative 'python_asdl_c.rb'


module ASDL

  class PythonGenerator < Generator

    set_visitor 'python_asdl_c.rb'

    def generate_include_file(mod, f)
      f.write(auto_gen_message)
      f.write %[#include "asdl.h"\n\n]
      c = ASDL.chain_of_visitors(
        TypeDefVisitor.new(f),
        StructVisitor.new(f),
        PrototypeVisitor.new(f),
      )
      c.visit(mod)
      f.write("PyObject* PyAST_mod2obj(mod_ty t);\n")
      f.write("mod_ty PyAST_obj2mod(PyObject* ast, PyArena* arena, int mode);\n")
      f.write("int PyAST_Check(PyObject* obj);\n")
    end

    def generate_c_file(asdl_file, f)
      f.write(auto_gen_message)
      f.write %[#include <stddef.h>\n]
      f.write("\n")
      f.write %[#include "Python.h"\n]
      f.write %[#include "#{mod.name}-ast.h"\n]
      f.write("\n")
      f.write("static PyTypeObject AST_type;\n")
      v = ASDL.chain_of_visitors(
        PyTypesDeclareVisitor.new(f),
        PyTypesVisitor.new(f),
        Obj2ModPrototypeVisitor.new(f),
        FunctionVisitor.new(f),
        ObjVisitor.new(f),
        Obj2ModVisitor.new(f),
        ASTModuleVisitor.new(f),
        PartingShots.new(f),
      )
      v.visit(mod)
    end
  end

end
