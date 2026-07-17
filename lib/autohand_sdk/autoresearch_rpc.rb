# frozen_string_literal: true

module AutohandSDK
  module AutoresearchRPC
    def start_autoresearch(params)
      request(RPCClient::RPC_METHODS.fetch(:start_autoresearch), autoresearch_params(params))
    end

    def get_autoresearch_status
      request(RPCClient::RPC_METHODS.fetch(:get_autoresearch_status), {})
    end

    def stop_autoresearch
      request(RPCClient::RPC_METHODS.fetch(:stop_autoresearch), {})
    end

    def get_autoresearch_history
      request(RPCClient::RPC_METHODS.fetch(:get_autoresearch_history), {})
    end

    def replay_autoresearch(params)
      request(RPCClient::RPC_METHODS.fetch(:replay_autoresearch), autoresearch_params(params))
    end

    def rescore_autoresearch(params)
      request(RPCClient::RPC_METHODS.fetch(:rescore_autoresearch), autoresearch_params(params))
    end

    def compare_autoresearch(params)
      request(RPCClient::RPC_METHODS.fetch(:compare_autoresearch), autoresearch_params(params))
    end

    def get_autoresearch_pareto
      request(RPCClient::RPC_METHODS.fetch(:get_autoresearch_pareto), {})
    end

    def pin_autoresearch(params)
      request(RPCClient::RPC_METHODS.fetch(:pin_autoresearch), autoresearch_params(params))
    end

    def prune_autoresearch(params = {})
      request(RPCClient::RPC_METHODS.fetch(:prune_autoresearch), autoresearch_params(params))
    end

    private

    def autoresearch_params(params)
      camelize_hash(Utils.normalize_hash(params))
    end

    def camelize_hash(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, item), result|
          parts = key.to_s.split("_")
          camel_key = parts.first + parts.drop(1).map(&:capitalize).join
          result[camel_key] = camelize_hash(item)
        end
      when Array
        value.map { |item| camelize_hash(item) }
      else
        value
      end
    end
  end
end
