require 'dry/system/container'
require 'dry/system/components'

module ASDL
  class Container < Dry::System::Container
    use :logging
    use :env, inferrer: -> {ENV.fetch('ASDL_ENV', :ruby).to_sym}
    configure do |config|
      config.root = File.expand_path('..',__dir__)
      config.default_namespace = 'asdl'
      config.auto_register = 'lib'
      
    end
    load_paths!('lib\asdl', 'system')
  end
end
