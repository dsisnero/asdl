require "dry/system/container"
require "dry/system/components"

module Asdl
  class Container < Dry::System::Container
    use :logging
    use :env, inferrer: -> { ENV.fetch("ASDL_ENV", :ruby).to_sym }
    configure do |config|
      config.root = Pathname(__dir__).join("../..")
      config.name = :asdl
      config.component_dirs.add "lib" do |dir|
        dir.namespaces.add "asdl", key: nil
      end
    end

    add_to_load_path! "lib"
  end
end
