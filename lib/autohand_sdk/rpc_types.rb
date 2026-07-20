# frozen_string_literal: true

# The immutable RPC request and response values form one public contract.
# rubocop:disable Metrics/ModuleLength
module AutohandSDK
  module RPCValidation
    module_function

    def object(value, context = "RPC value")
      return value if value.is_a?(Hash)

      raise TypeError, "#{context} must be an object"
    end

    def string(value, context)
      return value if value.is_a?(String)

      raise TypeError, "#{context} must be a string"
    end

    def boolean(value, context)
      return value if value.equal?(true) || value.equal?(false)

      raise TypeError, "#{context} must be a boolean"
    end
  end

  PermissionAcknowledgementParams = Data.define(:request_id) do
    def to_rpc
      { "requestId" => RPCValidation.string(request_id, "request_id") }
    end
  end

  PermissionAcknowledgementResult = Data.define(:success) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "permission acknowledgement result")
      new(success: RPCValidation.boolean(object.fetch("success"), "success"))
    end

    alias_method :success?, :success
  end

  DirectoryAccessResponseParams = Data.define(:request_id, :granted) do
    def to_rpc
      {
        "requestId" => RPCValidation.string(request_id, "request_id"),
        "granted" => RPCValidation.boolean(granted, "granted")
      }
    end
  end

  DirectoryAccessResponseResult = Data.define(:success) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "directory access response result")
      new(success: RPCValidation.boolean(object.fetch("success"), "success"))
    end

    alias_method :success?, :success
  end

  DirectoryAccessAcknowledgementParams = Data.define(:request_id) do
    def to_rpc
      { "requestId" => RPCValidation.string(request_id, "request_id") }
    end
  end

  DirectoryAccessAcknowledgementResult = Data.define(:success) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "directory access acknowledgement result")
      new(success: RPCValidation.boolean(object.fetch("success"), "success"))
    end

    alias_method :success?, :success
  end

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

  AutomodeStartParams = Data.define(
    :prompt,
    :max_iterations,
    :completion_promise,
    :use_worktree,
    :checkpoint_interval,
    :max_runtime,
    :max_cost
  ) do
    def to_rpc
      {
        "prompt" => prompt.to_s,
        "maxIterations" => max_iterations,
        "completionPromise" => completion_promise,
        "useWorktree" => use_worktree,
        "checkpointInterval" => checkpoint_interval,
        "maxRuntime" => max_runtime,
        "maxCost" => max_cost
      }.compact
    end
  end

  AutomodeStartResult = Data.define(:success, :session_id, :error) do
    def self.from_rpc(value)
      new(success: value.fetch("success"), session_id: value["sessionId"], error: value["error"])
    end

    alias_method :success?, :success
  end

  AUTOMODE_SESSION_STATUSES = %w[running paused completed cancelled failed].freeze

  AutomodeCheckpoint = Data.define(:commit, :message, :timestamp) do
    def self.from_rpc(value)
      new(
        commit: value.fetch("commit").to_s,
        message: value.fetch("message").to_s,
        timestamp: value.fetch("timestamp").to_s
      )
    end
  end

  AutomodeState = Data.define(
    :session_id,
    :status,
    :current_iteration,
    :max_iterations,
    :files_created,
    :files_modified,
    :branch,
    :last_checkpoint
  ) do
    def self.from_rpc(value)
      status = value.fetch("status").to_s
      raise ArgumentError, "unsupported auto-mode status: #{status}" unless AUTOMODE_SESSION_STATUSES.include?(status)

      checkpoint = value["lastCheckpoint"]
      new(
        session_id: value.fetch("sessionId").to_s,
        status: status,
        current_iteration: Integer(value.fetch("currentIteration")),
        max_iterations: Integer(value.fetch("maxIterations")),
        files_created: Integer(value.fetch("filesCreated")),
        files_modified: Integer(value.fetch("filesModified")),
        branch: value["branch"],
        last_checkpoint: checkpoint.nil? ? nil : AutomodeCheckpoint.from_rpc(checkpoint)
      )
    end
  end

  AutomodeStatusParams = Data.define do
    def to_rpc
      {}
    end
  end

  AutomodeStatusResult = Data.define(:active, :paused, :state) do
    def self.from_rpc(value)
      state = value["state"]
      new(
        active: value.fetch("active"),
        paused: value.fetch("paused"),
        state: state.nil? ? nil : AutomodeState.from_rpc(state)
      )
    end

    alias_method :active?, :active
    alias_method :paused?, :paused
  end

  AutomodePauseParams = Data.define do
    def to_rpc
      {}
    end
  end

  AutomodeOperationResult = Data.define(:success, :error) do
    def self.from_rpc(value)
      new(success: value.fetch("success"), error: value["error"])
    end

    alias_method :success?, :success
  end
  AutomodeResumeParams = Data.define do
    def to_rpc
      {}
    end
  end
  AutomodeResumeResult = AutomodeOperationResult
  AutomodeCancelParams = Data.define(:reason) do
    def to_rpc
      { "reason" => reason }.compact
    end
  end
  AutomodeCancelResult = AutomodeOperationResult

  AutomodeGetLogParams = Data.define(:limit) do
    def to_rpc
      { "limit" => limit }.compact
    end
  end

  AutomodeLogCheckpoint = Data.define(:commit, :message) do
    def self.from_rpc(value)
      new(commit: value.fetch("commit").to_s, message: value.fetch("message").to_s)
    end
  end

  AutomodeIterationLog = Data.define(
    :iteration,
    :timestamp,
    :actions,
    :tokens_used,
    :cost,
    :checkpoint
  ) do
    def self.from_rpc(value)
      checkpoint = value["checkpoint"]
      new(
        iteration: Integer(value.fetch("iteration")),
        timestamp: value.fetch("timestamp").to_s,
        actions: Array(value.fetch("actions")).map(&:to_s).freeze,
        tokens_used: value["tokensUsed"],
        cost: value["cost"],
        checkpoint: checkpoint.nil? ? nil : AutomodeLogCheckpoint.from_rpc(checkpoint)
      )
    end
  end

  AutomodeGetLogResult = Data.define(:success, :iterations, :error) do
    def self.from_rpc(value)
      new(
        success: value.fetch("success"),
        iterations: Array(value.fetch("iterations")).map { |entry| AutomodeIterationLog.from_rpc(entry) }.freeze,
        error: value["error"]
      )
    end

    alias_method :success?, :success
  end
end
# rubocop:enable Metrics/ModuleLength
