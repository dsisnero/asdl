require "asdl/version"
require "asdl/app"
require "asdl/check_visitor"
require 'set'

module ASDL

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
