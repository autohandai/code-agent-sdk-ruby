# frozen_string_literal: true

module AutohandSDK
  ResetParams = Data.define do
    def to_rpc
      {}
    end
  end

  ResetResult = Data.define(:session_id) do
    def self.from_rpc(value)
      new(session_id: value.fetch("sessionId").to_s)
    end
  end
end
