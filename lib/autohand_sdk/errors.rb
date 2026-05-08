# frozen_string_literal: true

module AutohandSDK
  class Error < StandardError; end

  class ConfigurationError < Error; end

  class TransportError < Error; end

  class TransportNotStartedError < TransportError; end

  class RequestTimeoutError < TransportError; end

  class RPCError < Error
    attr_reader :code, :data

    def initialize(message, code: nil, data: nil)
      super(message)
      @code = code
      @data = data
    end
  end

  class StructuredOutputError < Error
    attr_reader :raw_response

    def initialize(message, raw_response)
      @raw_response = raw_response
      super("#{message}\n\nRaw response preview:\n#{preview(raw_response)}")
    end

    private

    def preview(text)
      trimmed = text.to_s.strip
      return "<empty>" if trimmed.empty?
      return trimmed if trimmed.length <= 1_200

      "#{trimmed[0, 1_200]}\n..."
    end
  end
end
