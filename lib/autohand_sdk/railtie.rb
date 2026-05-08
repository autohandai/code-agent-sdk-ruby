# frozen_string_literal: true

module AutohandSDK
  class Railtie < Rails::Railtie
    initializer "autohand_sdk.configure_logger" do
      AutohandSDK.configure do |config|
        config.logger = Rails.logger unless config.logger_configured?
      end
    end
  end
end
