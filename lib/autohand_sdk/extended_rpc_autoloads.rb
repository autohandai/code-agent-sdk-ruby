# frozen_string_literal: true

module AutohandSDK
  RPC_TYPE_AUTOLOADS = %i[
    PermissionAcknowledgementParams PermissionAcknowledgementResult
    DirectoryAccessResponseParams DirectoryAccessResponseResult
    DirectoryAccessAcknowledgementParams DirectoryAccessAcknowledgementResult
    CHANGE_DECISION_ACTIONS ChangesDecisionParams ChangesDecisionError ChangesDecisionResult
    SESSION_HISTORY_STATUSES SessionHistoryParams SessionHistoryEntry SessionHistoryResult
    SessionDetailsParams SESSION_MESSAGE_ROLES SessionMessageToolCall SessionMessage
    SessionDetailsSuccess SessionDetailsFailure SessionDetailsResult SessionAttachParams SessionAttachResult
    YoloSetParams YoloSetResult MCPInputSchema VscodeMCPTool MCPSetVscodeToolsParams MCPSetVscodeToolsResult
    MCPInvokeResponseParams MCPInvokeResponseResult LearnRecommendParams LEARN_AUDIT_STATUSES LearnAuditEntry
    LearnRecommendation LearnRecommendResult LearnUpdateParams LEARN_UPDATE_STATUSES LearnUpdateEntry
    LearnUpdateResult LEARN_GENERATE_SCOPES LearnGenerateParams LearnGenerateResult ToolsRegistryParams
    TOOL_REGISTRY_SOURCES TOOL_REGISTRY_SCOPES ToolRegistryEntry ToolRegistryDiagnostic ToolsRegistryResult
    ContextCompactParams ContextCompactResult UnknownNotificationEvent
    AutomodeIterationEvent AutomodeCompleteEvent AutomodeErrorEvent
    HookPreToolEvent HookPostToolEvent HookPrePromptEvent TOKEN_USAGE_STATUSES HookPostResponseEvent
    MCPInvokeRequestEvent MCPToolsChangedEntry MCPToolsChangedEvent LEARN_PROGRESS_STATUSES LearnProgressEvent
  ].freeze

  RPC_TYPE_AUTOLOADS.each { |constant| autoload constant, "autohand_sdk/rpc_types" }
end
