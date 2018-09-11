lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "asdl/version"

Gem::Specification.new do |spec|
  spec.name          = "asdl"
  spec.version       = ASDL::VERSION
  spec.authors       = ["Dominic Sisneros"]
  spec.email         = ["dsisnero@gmail.com"]

  spec.summary       = %q{Creates ruby AST Classes from a ZEPHYR ASDL file}
  spec.description   = %q{This gem is a command line app to generate ruby C extension\n
files for Abstract Syntax Trees from a ASDL file}

  spec.license       = ""

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "to-do: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "bin"
  spec.executables   = "asdl"
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency('rdoc')
  spec.add_dependency('methadone', '~> 2.0.0')
  spec.add_development_dependency('test-unit')
  spec.add_development_dependency('pry')
end
