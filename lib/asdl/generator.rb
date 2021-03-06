require 'pathname'
require 'logger'
require 'asdl/parser'

module ASDL

  class Generator


    class <<self
      def set_visitor(name)
        @visitor_file = name
      end

      def visitor_file
        @visitor_file
      end

    end


    attr_reader :mod, :logger

    def initialize(logger=default_logger)
      @logger = logger
    end

    def visitor_file
      self.class.visitor_file
    end

    def default_logger
      Logger.new(STDOUT)
    end


    def auto_gen_message(fname= visitor_file)
      %[/* File Automatically generated by #{visitor_file} */\n\n]
    end

    def include_name_from_mod(mod)
      "#{mod.name}-ast.h"
    end

    def c_src_name_from_mod(mod)
      "#{mod.name}-ast.c"
    end


    def generate(asdl_file, src_dir: '.', inc_dir: '.')
      @mod = ASDL::Parser.parse(asdl_file)
      @logger = logger
      inc_dir = inc_dir ? Pathname(inc_dir) : Pathname.getwd
      inc_outfile = (inc_dir + include_name_from_mod(mod)).expand_path
      File.open(inc_outfile, 'w') do |f|
        generate_include_file(mod, f)
      end
      logger.info("Generated #{inc_outfile}")

      src_dir = src_dir ? Pathname(src_dir) : Pathname.getwd
      src_outfile = (src_dir + c_src_name_from_mod(mod)).expand_path
      File.open(src_outfile, 'w') do |f|
        generate_c_file(mod, f)
      end

      logger.info("Generated #{src_outfile}")

    end


  end

end
