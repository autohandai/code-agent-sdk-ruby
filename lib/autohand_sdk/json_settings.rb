# frozen_string_literal: true

require_relative "errors"

module AutohandSDK
  # Copy native JSON without changing literal keys, false values, arrays or nulls.
  module JsonSettings
    module_function

    def copy_json(value, ancestors = {}.compare_by_identity, depth = 0)
      raise ConfigurationError, "Run settings exceed maximum nesting depth" if depth > 256

      case value
      when NilClass, TrueClass, FalseClass, String, Integer then value
      when Float
        raise ConfigurationError, "Run settings must contain finite JSON numbers" unless value.finite?

        value
      when Array, Hash
        raise ConfigurationError, "Run settings must not contain cycles" if ancestors[value]

        ancestors[value] = true
        begin
          if value.is_a?(Array)
            value.map { |item| copy_json(item, ancestors, depth + 1) }
          else
            value.to_h do |key, item|
              unless (key.is_a?(String) || key.is_a?(Symbol)) && !%w[__proto__ prototype constructor].include?(key.to_s)
                raise ConfigurationError, "Run settings contain an unsafe setting path"
              end

              [key.to_s, copy_json(item, ancestors, depth + 1)]
            end
          end
        ensure
          ancestors.delete(value)
        end
      else raise ConfigurationError, "Run settings must contain plain JSON values"
      end
    end

    def merge!(target, source)
      source.each do |key, value|
        if value.is_a?(Hash) && target[key].is_a?(Hash)
          merge!(target[key], value)
        else
          target[key] = value
        end
      end
      target
    end
  end
end
