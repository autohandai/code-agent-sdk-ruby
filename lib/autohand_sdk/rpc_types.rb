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

    def optional_boolean(value, context)
      value.nil? ? nil : boolean(value, context)
    end

    def optional_integer(value, context)
      value.nil? ? nil : integer(value, context)
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

  MCPInputSchema = Data.define(:properties, :required) do
    def to_rpc
      required_names = required
      {
        "type" => "object",
        "properties" => RPCValidation.object(properties, "properties"),
        "required" => if required_names.nil?
                        nil
                      else
                        RPCValidation.array(required_names, "required").map do |name|
                          RPCValidation.string(name, "required property")
                        end
                      end
      }.compact
    end
  end

  VscodeMCPTool = Data.define(:name, :description, :server_name, :input_schema) do
    def to_rpc
      {
        "name" => RPCValidation.string(name, "name"),
        "description" => RPCValidation.string(description, "description"),
        "serverName" => RPCValidation.string(server_name, "server_name"),
        "inputSchema" => input_schema&.to_rpc
      }.compact
    end
  end

  MCPSetVscodeToolsParams = Data.define(:tools) do
    def to_rpc
      normalized = RPCValidation.array(tools, "tools").map do |tool|
        raise TypeError, "tools entries must be VscodeMCPTool values" unless tool.is_a?(VscodeMCPTool)

        tool.to_rpc
      end
      { "tools" => normalized }
    end
  end

  MCPSetVscodeToolsResult = Data.define(:success) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "MCP tool registration result")
      new(success: RPCValidation.boolean(object.fetch("success"), "success"))
    end

    alias_method :success?, :success
  end

  MCPInvokeResponseParams = Data.define(:request_id, :success, :result, :error) do
    def to_rpc
      {
        "requestId" => RPCValidation.string(request_id, "request_id"),
        "success" => RPCValidation.boolean(success, "success"),
        "result" => RPCValidation.optional_string(result, "result"),
        "error" => RPCValidation.optional_string(error, "error")
      }.compact
    end
  end

  MCPInvokeResponseResult = Data.define(:success) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "MCP invocation response result")
      new(success: RPCValidation.boolean(object.fetch("success"), "success"))
    end

    alias_method :success?, :success
  end

  LearnRecommendParams = Data.define(:deep) do
    def to_rpc
      { "deep" => deep.nil? ? nil : RPCValidation.boolean(deep, "deep") }.compact
    end
  end

  LEARN_AUDIT_STATUSES = %w[redundant outdated conflicting].freeze

  LearnAuditEntry = Data.define(:skill, :status, :reason) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "learning audit entry")
      new(
        skill: RPCValidation.string(object.fetch("skill"), "skill"),
        status: RPCValidation.enum(object.fetch("status"), LEARN_AUDIT_STATUSES, "status"),
        reason: RPCValidation.string(object.fetch("reason"), "reason")
      )
    end
  end

  LearnRecommendation = Data.define(:slug, :score, :reason) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "learning recommendation")
      score = object.fetch("score")
      raise TypeError, "score must be numeric" unless score.is_a?(Numeric)

      new(
        slug: RPCValidation.string(object.fetch("slug"), "slug"),
        score: score,
        reason: RPCValidation.string(object.fetch("reason"), "reason")
      )
    end
  end

  LearnRecommendResult = Data.define(
    :success,
    :project_summary,
    :audit,
    :recommendations,
    :gap_analysis,
    :error
  ) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "learning recommendations result")
      new(
        success: RPCValidation.boolean(object.fetch("success"), "success"),
        project_summary: RPCValidation.string(object.fetch("projectSummary"), "projectSummary"),
        audit: RPCValidation.array(object.fetch("audit"), "audit").map do |entry|
          LearnAuditEntry.from_rpc(entry)
        end.freeze,
        recommendations: RPCValidation.array(object.fetch("recommendations"), "recommendations").map do |entry|
          LearnRecommendation.from_rpc(entry)
        end.freeze,
        gap_analysis: RPCValidation.optional_string(object["gapAnalysis"], "gapAnalysis"),
        error: RPCValidation.optional_string(object["error"], "error")
      )
    end

    alias_method :success?, :success
  end

  LearnUpdateParams = Data.define do
    def to_rpc = {}
  end

  LEARN_UPDATE_STATUSES = %w[updated unchanged failed].freeze

  LearnUpdateEntry = Data.define(:name, :status) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "learning update entry")
      new(
        name: RPCValidation.string(object.fetch("name"), "name"),
        status: RPCValidation.enum(object.fetch("status"), LEARN_UPDATE_STATUSES, "status")
      )
    end
  end

  LearnUpdateResult = Data.define(:success, :updated, :unchanged, :results, :error) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "learning update result")
      new(
        success: RPCValidation.boolean(object.fetch("success"), "success"),
        updated: RPCValidation.integer(object.fetch("updated"), "updated"),
        unchanged: RPCValidation.integer(object.fetch("unchanged"), "unchanged"),
        results: RPCValidation.array(object.fetch("results"), "results").map do |entry|
          LearnUpdateEntry.from_rpc(entry)
        end.freeze,
        error: RPCValidation.optional_string(object["error"], "error")
      )
    end

    alias_method :success?, :success
  end

  LEARN_GENERATE_SCOPES = %w[project user].freeze

  LearnGenerateParams = Data.define(:scope) do
    def to_rpc
      { "scope" => RPCValidation.enum(scope.to_s, LEARN_GENERATE_SCOPES, "scope") }
    end
  end

  LearnGenerateResult = Data.define(:success, :skill_name, :skill_path, :error) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "skill generation result")
      new(
        success: RPCValidation.boolean(object.fetch("success"), "success"),
        skill_name: RPCValidation.optional_string(object["skillName"], "skillName"),
        skill_path: RPCValidation.optional_string(object["skillPath"], "skillPath"),
        error: RPCValidation.optional_string(object["error"], "error")
      )
    end

    alias_method :success?, :success
  end

  ToolsRegistryParams = Data.define do
    def to_rpc = {}
  end

  TOOL_REGISTRY_SOURCES = %w[builtin meta extension].freeze
  TOOL_REGISTRY_SCOPES = %w[user project].freeze

  ToolRegistryEntry = Data.define(
    :name,
    :description,
    :requires_approval,
    :approval_message,
    :source,
    :scope,
    :disabled,
    :created_at,
    :schema_version,
    :handler_preview,
    :reuse_hint,
    :extension_id,
    :extension_version
  ) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "tool registry entry")
      scope = object["scope"]
      new(
        name: RPCValidation.string(object.fetch("name"), "name"),
        description: RPCValidation.string(object.fetch("description"), "description"),
        requires_approval: RPCValidation.optional_boolean(object["requiresApproval"], "requiresApproval"),
        approval_message: RPCValidation.optional_string(object["approvalMessage"], "approvalMessage"),
        source: RPCValidation.enum(object.fetch("source"), TOOL_REGISTRY_SOURCES, "source"),
        scope: scope.nil? ? nil : RPCValidation.enum(scope, TOOL_REGISTRY_SCOPES, "scope"),
        disabled: RPCValidation.optional_boolean(object["disabled"], "disabled"),
        created_at: RPCValidation.optional_string(object["createdAt"], "createdAt"),
        schema_version: RPCValidation.optional_integer(object["schemaVersion"], "schemaVersion"),
        handler_preview: RPCValidation.optional_string(object["handlerPreview"], "handlerPreview"),
        reuse_hint: RPCValidation.optional_string(object["reuseHint"], "reuseHint"),
        extension_id: RPCValidation.optional_string(object["extensionId"], "extensionId"),
        extension_version: RPCValidation.optional_string(object["extensionVersion"], "extensionVersion")
      )
    end
  end

  ToolRegistryDiagnostic = Data.define(:file, :reason) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "tool registry diagnostic")
      new(
        file: RPCValidation.string(object.fetch("file"), "file"),
        reason: RPCValidation.string(object.fetch("reason"), "reason")
      )
    end
  end

  ToolsRegistryResult = Data.define(:tools, :diagnostics) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "tools registry result")
      new(
        tools: RPCValidation.array(object.fetch("tools"), "tools").map do |entry|
          ToolRegistryEntry.from_rpc(entry)
        end.freeze,
        diagnostics: RPCValidation.array(object.fetch("diagnostics"), "diagnostics").map do |entry|
          ToolRegistryDiagnostic.from_rpc(entry)
        end.freeze
      )
    end
  end

  ContextCompactParams = Data.define(:enabled) do
    def to_rpc
      { "enabled" => RPCValidation.boolean(enabled, "enabled") }
    end
  end

  ContextCompactResult = Data.define(:enabled) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "context compaction result")
      new(enabled: RPCValidation.boolean(object.fetch("enabled"), "enabled"))
    end

    alias_method :enabled?, :enabled
  end

  AutomodeIterationEvent = Data.define(:session_id, :iteration, :actions, :tokens_used, :timestamp) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "auto-mode iteration event")
      used = object["tokensUsed"]
      new(
        session_id: RPCValidation.string(object.fetch("sessionId"), "sessionId"),
        iteration: RPCValidation.integer(object.fetch("iteration"), "iteration"),
        actions: RPCValidation.array(object.fetch("actions"), "actions").map do |action|
          RPCValidation.string(action, "action")
        end.freeze,
        tokens_used: used.nil? ? nil : RPCValidation.integer(used, "tokensUsed"),
        timestamp: RPCValidation.string(object.fetch("timestamp"), "timestamp")
      )
    end

    def type = "automode_iteration"
    def method = "autohand.automode.iteration"
  end

  AutomodeCompleteEvent = Data.define(:session_id, :iterations, :files_created, :files_modified, :timestamp) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "auto-mode completion event")
      new(
        session_id: RPCValidation.string(object.fetch("sessionId"), "sessionId"),
        iterations: RPCValidation.integer(object.fetch("iterations"), "iterations"),
        files_created: RPCValidation.integer(object.fetch("filesCreated"), "filesCreated"),
        files_modified: RPCValidation.integer(object.fetch("filesModified"), "filesModified"),
        timestamp: RPCValidation.string(object.fetch("timestamp"), "timestamp")
      )
    end

    def type = "automode_complete"
    def method = "autohand.automode.complete"
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
