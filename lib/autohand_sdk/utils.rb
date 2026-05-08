# frozen_string_literal: true

module AutohandSDK
  module Utils
    module_function

    def normalize_key(key)
      key.to_s
         .gsub(/([A-Z]+)([A-Z][a-z])/, "\\1_\\2")
         .gsub(/([a-z\d])([A-Z])/, "\\1_\\2")
         .tr("-", "_")
         .downcase
         .to_sym
    end

    def normalize_hash(hash)
      hash.to_h.each_with_object({}) do |(key, value), normalized|
        normalized[normalize_key(key)] = normalize_value(value)
      end
    end

    def normalize_value(value)
      case value
      when Hash
        normalize_hash(value)
      when Array
        value.map { |item| normalize_value(item) }
      else
        value
      end
    end

    def compact_hash(hash)
      hash.compact
    end

    def with_rpc_aliases(hash)
      data = hash.transform_keys(&:to_s)
      alias_key(data, "request_id", "requestId")
      alias_key(data, "thinking_level", "thinkingLevel")
      alias_key(data, "agents_md", "agentsMd")
      alias_key(data, "include_context", "includeContext")
      alias_key(data, "max_thinking_tokens", "maxThinkingTokens")
      compact_hash(data)
    end

    def alias_key(hash, from, to)
      return unless hash.key?(from)

      hash[to] = hash.delete(from)
    end
  end
end
