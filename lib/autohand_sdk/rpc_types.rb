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

  BrowserHandoffCreateParams = Data.define(:extension_id, :install_url) do
    def to_rpc
      { "extensionId" => extension_id, "installUrl" => install_url }.compact
    end
  end

  BrowserHandoffCreateResult = Data.define(
    :token,
    :session_id,
    :workspace_root,
    :created_at,
    :expires_at,
    :url
  ) do
    def self.from_rpc(value)
      new(
        token: value.fetch("token").to_s,
        session_id: value.fetch("sessionId").to_s,
        workspace_root: value.fetch("workspaceRoot").to_s,
        created_at: value.fetch("createdAt").to_s,
        expires_at: value.fetch("expiresAt").to_s,
        url: value.fetch("url").to_s
      )
    end
  end

  BrowserHandoffAttachParams = Data.define(:token) do
    def to_rpc
      { "token" => token.to_s }
    end
  end

  BrowserHandoffAttachResult = Data.define(:success, :session_id, :workspace_root, :message_count) do
    def self.from_rpc(value)
      new(
        success: value.fetch("success"),
        session_id: value["sessionId"],
        workspace_root: value["workspaceRoot"],
        message_count: value["messageCount"]
      )
    end

    alias_method :success?, :success
  end

  BrowserHandoffAttachLatestParams = Data.define do
    def to_rpc
      {}
    end
  end
  BrowserHandoffAttachLatestResult = BrowserHandoffAttachResult
end
