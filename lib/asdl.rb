require "asdl/version"
require "asdl/app"
require "asdl/check_visitor"
require 'set'
require 'dry/view'
require 'erb'
require 'asdl/container'

module ASDL

  class PythonView < Dry::View

    config.paths = Container.root.join('templates/python')

  end

  class RubyView < Dry::View
    config.paths =  Container.root.join('templates/ruby')
  end

  class << self

    def check(mod)
      CheckVisitor.check(mod)
    end

    def parse(filename)
      mod = open(filename) do |f|
        parser = ASDL::Parser.new
        parser.parse(f)
      end
      mod
    end

  end

end
