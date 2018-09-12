require 'pathname'
require_relative 'generator'
require 'logger'
require 'asdl/python_generator'


module ASDL

  class App

    attr_reader :logger, :generator_klass


    def initialize(generator: PythonGenerator, logger: default_logger)
      @logger = logger
      @generator_klass = generator
    end

    def generate(srcfile, inc_dir: nil, src_dir: nil)
      gen = generator_klass.new(logger)
      gen.generate(srcfile, inc_dir: inc_dir, src_dir: src_dir)
    end

    def default_logger
      Logger.new(STDOUT)
    end

  end

end

  if $0 == __FILE__

    app = ASDL::App.new
    require 'pry'
    src = ARGV[0]
    raise 'Need a ASDL src' unless src
    #binding.pry
    app.generate(src)

  end
