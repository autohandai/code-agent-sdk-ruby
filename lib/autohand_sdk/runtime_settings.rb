# frozen_string_literal: true

require "json"
require "uri"
require_relative "errors"
require_relative "json_settings"

module AutohandSDK
  # Private settings are applied before CLI runtime construction and never saved.
  module RuntimeSettings
    FEATURE_ALIASES = %w[remote_overrides usage_v2 aws_bedrock_provider slash_goal token_usage_status
                         experimental_fork experimental_clone experimental_handoff].to_h do |key|
      parts = key.split("_")
      [key, parts.first + parts.drop(1).map(&:capitalize).join]
    end.freeze

    module_function

    def build(config)
      fork_reference(config)
      settings = JsonSettings.copy_json(config.run_settings || {})
      raise ConfigurationError, "Run settings must be a JSON object" unless settings.is_a?(Hash)

      if config.features
        features = config.features.to_h.transform_keys { |key| FEATURE_ALIASES.fetch(key.to_s, key.to_s) }
        JsonSettings.merge!(settings, { "features" => JsonSettings.copy_json(features) })
      end
      unless config.provider
        if [config.api_key, config.base_url, config.autohand_ai_plan, config.port].any? { |value| !value.nil? }
          raise ConfigurationError, "A provider is required for provider credentials and settings"
        end

        return settings
      end
      provider = config.provider
      section = provider_options(config, settings)
      return settings if section.empty?

      overlay = if provider.start_with?("custom:")
                  { "customProviders" => { provider.delete_prefix("custom:") => section } }
                elsif provider.start_with?("extension:")
                  { "extensionProviders" => { provider => section } }
                else
                  { provider => section }
                end
      JsonSettings.merge!(settings, overlay)
    end

    def provider_options(config, settings)
      provider = config.provider
      section = {}
      section["model"] = config.model unless config.model.nil?
      unless config.api_key.nil?
        section[provider == "vertexai" ? "authToken" : "apiKey"] = config.api_key
        section["authMode"] = "api-key" if %w[autohandai openai xai].include?(provider)
        section["authMethod"] = "api-key" if provider == "azure"
        section["authMode"] = "bedrock-api-key" if provider == "bedrock"
      end
      if config.base_url
        key = %w[vertexai bedrock].include?(provider) ? "endpoint" : "baseUrl"
        section[key] = provider == "vertexai" ? vertex_endpoint(config.base_url) : config.base_url
      elsif config.port && %w[ollama llamacpp mlx].include?(provider)
        section["baseUrl"] = "http://localhost:#{config.port}"
      end
      if provider == "autohandai"
        if config.autohand_ai_plan
          section["plan"] = config.autohand_ai_plan
        elsif (config.api_key || config.base_url) && !settings.fetch(provider, {}).key?("plan")
          section["plan"] = "cloud"
        end
      end
      section
    end

    def fork_reference(config)
      return if config.fork.nil? || config.fork == false

      source = config.fork == true ? config.session_id || config.session_path : config.fork

      unless source.is_a?(String) && !source.strip.empty?
        raise ConfigurationError, "Fork requires an explicit session ID or path"
      end

      source
    end

    def needed?(config)
      return true unless config.features.nil? && config.run_settings.nil?
      return false unless config.provider && config.provider != "autohandai"

      [config.api_key, config.base_url, config.port].any? { |value| !value.nil? }
    end

    def vertex_endpoint(value)
      uri = URI.parse(value.include?("://") ? value : "https://#{value}")
      unless uri.scheme == "https" && uri.host && !uri.userinfo && uri.port == 443 &&
             [nil, "", "/"].include?(uri.path) && !uri.query && !uri.fragment
        raise ConfigurationError, "Vertex endpoint must be an HTTPS origin or hostname"
      end

      uri.host
    rescue URI::InvalidURIError
      raise ConfigurationError, "Vertex endpoint must be an HTTPS origin or hostname"
    end
  end
end
