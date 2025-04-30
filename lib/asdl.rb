require "asdl/version"
require "asdl/app"
require "asdl/check_visitor"
require "set"
require "dry/view"
require "erb"
require "asdl/container"

module Asdl
  class PythonView < Dry::View
    config.paths = Container.root.join("templates/python")
  end

  class RubyView < Dry::View
    config.paths = Container.root.join("templates/ruby")
  end

  class << self
    def check(mod)
      CheckVisitor.check(mod)
    end

    def parse(filename)
      open(filename) do |f|
        parser = Asdl::Parser.new
        parser.parse(f)
      end
    end
  end
end
