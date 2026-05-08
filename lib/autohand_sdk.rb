# frozen_string_literal: true

require_relative "autohand_sdk/version"
require_relative "autohand_sdk/errors"
require_relative "autohand_sdk/configuration"
require_relative "autohand_sdk/transport"
require_relative "autohand_sdk/rpc_client"
require_relative "autohand_sdk/client"
require_relative "autohand_sdk/agent"
require_relative "autohand_sdk/json_output"

module AutohandSDK
  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end

    def reset_configuration!
      @config = Configuration.new
    end

    def client(**)
      Client.new(config.merge(**))
    end

    def agent(instructions: nil, **options)
      Agent.create(config.merge(**options), instructions: instructions)
    end
  end
end

require_relative "autohand_sdk/railtie" if defined?(Rails::Railtie)
