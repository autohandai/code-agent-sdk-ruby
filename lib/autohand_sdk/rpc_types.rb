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

    def integer(value, context)
      return value if value.is_a?(Integer)

      raise TypeError, "#{context} must be an integer"
    end

    def array(value, context)
      return value if value.is_a?(Array)

      raise TypeError, "#{context} must be an array"
    end

    def enum(value, allowed, context)
      string_value = string(value, context)
      return string_value if allowed.include?(string_value)

      raise ArgumentError, "#{context} must be one of: #{allowed.join(", ")}"
    end

    def optional_string(value, context)
      value.nil? ? nil : string(value, context)
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

  CHANGE_DECISION_ACTIONS = %w[accept_all reject_all accept_selected].freeze

  ChangesDecisionParams = Data.define(:batch_id, :action, :selected_change_ids) do
    def to_rpc
      ids = selected_change_ids
      normalized_ids = if ids.nil?
                         nil
                       else
                         RPCValidation.array(ids, "selected_change_ids").map do |id|
                           RPCValidation.string(id, "selected_change_id")
                         end
                       end
      {
        "batchId" => RPCValidation.string(batch_id, "batch_id"),
        "action" => RPCValidation.enum(action.to_s, CHANGE_DECISION_ACTIONS, "action"),
        "selectedChangeIds" => normalized_ids
      }.compact
    end
  end

  ChangesDecisionError = Data.define(:change_id, :error) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "change decision error")
      new(
        change_id: RPCValidation.string(object.fetch("changeId"), "changeId"),
        error: RPCValidation.string(object.fetch("error"), "error")
      )
    end
  end

  ChangesDecisionResult = Data.define(:success, :applied_count, :skipped_count, :errors) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "changes decision result")
      raw_errors = object.fetch("errors", [])
      new(
        success: RPCValidation.boolean(object.fetch("success"), "success"),
        applied_count: RPCValidation.integer(object.fetch("appliedCount"), "appliedCount"),
        skipped_count: RPCValidation.integer(object.fetch("skippedCount"), "skippedCount"),
        errors: RPCValidation.array(raw_errors, "errors").map { |entry| ChangesDecisionError.from_rpc(entry) }.freeze
      )
    end

    alias_method :success?, :success
  end

  SESSION_HISTORY_STATUSES = %w[active completed crashed].freeze

  SessionHistoryParams = Data.define(:page, :page_size) do
    def to_rpc
      {
        "page" => page.nil? ? nil : RPCValidation.integer(page, "page"),
        "pageSize" => page_size.nil? ? nil : RPCValidation.integer(page_size, "page_size")
      }.compact
    end
  end

  SessionHistoryEntry = Data.define(
    :session_id,
    :created_at,
    :last_active_at,
    :project_name,
    :model,
    :message_count,
    :status
  ) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "session history entry")
      new(
        session_id: RPCValidation.string(object.fetch("sessionId"), "sessionId"),
        created_at: RPCValidation.string(object.fetch("createdAt"), "createdAt"),
        last_active_at: RPCValidation.string(object.fetch("lastActiveAt"), "lastActiveAt"),
        project_name: RPCValidation.string(object.fetch("projectName"), "projectName"),
        model: RPCValidation.string(object.fetch("model"), "model"),
        message_count: RPCValidation.integer(object.fetch("messageCount"), "messageCount"),
        status: RPCValidation.enum(object.fetch("status"), SESSION_HISTORY_STATUSES, "status")
      )
    end
  end

  SessionHistoryResult = Data.define(:sessions, :current_page, :total_pages, :total_items) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "session history result")
      new(
        sessions: RPCValidation.array(object.fetch("sessions"), "sessions").map do |entry|
          SessionHistoryEntry.from_rpc(entry)
        end.freeze,
        current_page: RPCValidation.integer(object.fetch("currentPage"), "currentPage"),
        total_pages: RPCValidation.integer(object.fetch("totalPages"), "totalPages"),
        total_items: RPCValidation.integer(object.fetch("totalItems"), "totalItems")
      )
    end
  end

  SessionDetailsParams = Data.define(:session_id) do
    def to_rpc
      { "sessionId" => RPCValidation.string(session_id, "session_id") }
    end
  end

  SESSION_MESSAGE_ROLES = %w[user assistant system tool].freeze

  SessionMessageToolCall = Data.define(:id, :name, :args) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "session message tool call")
      new(
        id: RPCValidation.string(object.fetch("id"), "id"),
        name: RPCValidation.string(object.fetch("name"), "name"),
        args: RPCValidation.object(object.fetch("args"), "args").freeze
      )
    end
  end

  SessionMessage = Data.define(:id, :role, :content, :timestamp, :tool_calls) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "session message")
      calls = object.fetch("toolCalls", [])
      new(
        id: RPCValidation.string(object.fetch("id"), "id"),
        role: RPCValidation.enum(object.fetch("role"), SESSION_MESSAGE_ROLES, "role"),
        content: RPCValidation.string(object.fetch("content"), "content"),
        timestamp: RPCValidation.string(object.fetch("timestamp"), "timestamp"),
        tool_calls: RPCValidation.array(calls, "toolCalls").map do |entry|
          SessionMessageToolCall.from_rpc(entry)
        end.freeze
      )
    end
  end

  SessionDetailsSuccess = Data.define(
    :session_id,
    :project_name,
    :model,
    :message_count,
    :status,
    :created_at,
    :last_active_at,
    :summary,
    :messages,
    :workspace_root
  ) do
    def success? = true

    def self.from_rpc(value)
      object = RPCValidation.object(value, "session details result")
      new(
        session_id: RPCValidation.string(object.fetch("sessionId"), "sessionId"),
        project_name: RPCValidation.string(object.fetch("projectName"), "projectName"),
        model: RPCValidation.string(object.fetch("model"), "model"),
        message_count: RPCValidation.integer(object.fetch("messageCount"), "messageCount"),
        status: RPCValidation.string(object.fetch("status"), "status"),
        created_at: RPCValidation.string(object.fetch("createdAt"), "createdAt"),
        last_active_at: RPCValidation.string(object.fetch("lastActiveAt"), "lastActiveAt"),
        summary: RPCValidation.optional_string(object["summary"], "summary"),
        messages: RPCValidation.array(object.fetch("messages"), "messages").map do |entry|
          SessionMessage.from_rpc(entry)
        end.freeze,
        workspace_root: RPCValidation.string(object.fetch("workspaceRoot"), "workspaceRoot")
      )
    end
  end

  SessionDetailsFailure = Data.define(:error) do
    def success? = false

    def self.from_rpc(value)
      object = RPCValidation.object(value, "session details failure")
      new(error: RPCValidation.optional_string(object["error"], "error"))
    end
  end

  module SessionDetailsResult
    module_function

    def from_rpc(value)
      object = RPCValidation.object(value, "session details result")
      success = RPCValidation.boolean(object.fetch("success"), "success")
      success ? SessionDetailsSuccess.from_rpc(object) : SessionDetailsFailure.from_rpc(object)
    end
  end

  SessionAttachParams = Data.define(:session_id) do
    def to_rpc
      { "sessionId" => RPCValidation.string(session_id, "session_id") }
    end
  end

  SessionAttachResult = Data.define(:success, :session_id, :workspace_root, :message_count, :error) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "session attachment result")
      count = object["messageCount"]
      new(
        success: RPCValidation.boolean(object.fetch("success"), "success"),
        session_id: RPCValidation.optional_string(object["sessionId"], "sessionId"),
        workspace_root: RPCValidation.optional_string(object["workspaceRoot"], "workspaceRoot"),
        message_count: count.nil? ? nil : RPCValidation.integer(count, "messageCount"),
        error: RPCValidation.optional_string(object["error"], "error")
      )
    end

    alias_method :success?, :success
  end

  YoloSetParams = Data.define(:pattern, :timeout_seconds) do
    def to_rpc
      timeout = timeout_seconds
      {
        "pattern" => RPCValidation.string(pattern, "pattern"),
        "timeoutSeconds" => timeout.nil? ? nil : RPCValidation.integer(timeout, "timeout_seconds")
      }.compact
    end
  end

  YoloSetResult = Data.define(:success, :expires_in) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "YOLO mode result")
      expires_in = object["expiresIn"]
      new(
        success: RPCValidation.boolean(object.fetch("success"), "success"),
        expires_in: expires_in.nil? ? nil : RPCValidation.integer(expires_in, "expiresIn")
      )
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
