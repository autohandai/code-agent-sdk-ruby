# frozen_string_literal: true

require_relative "autohand_sdk/version"

module AutohandSDK
  autoload :Agent, "autohand_sdk/agent"
  autoload :Run, "autohand_sdk/agent"
  autoload :Client, "autohand_sdk/client"
  autoload :Configuration, "autohand_sdk/configuration"
  autoload :CLIInstaller, "autohand_sdk/cli_installer"
  autoload :Transport, "autohand_sdk/transport"
  autoload :RPCClient, "autohand_sdk/rpc_client"
  autoload :HookEvents, "autohand_sdk/hook_events"
  autoload :JsonOutput, "autohand_sdk/json_output"
  autoload :Error, "autohand_sdk/errors"
  autoload :ConfigurationError, "autohand_sdk/errors"
  autoload :CLIInstallError, "autohand_sdk/errors"
  autoload :TransportError, "autohand_sdk/errors"
  autoload :TransportNotStartedError, "autohand_sdk/errors"
  autoload :RequestTimeoutError, "autohand_sdk/errors"
  autoload :RPCError, "autohand_sdk/errors"
  autoload :StructuredOutputError, "autohand_sdk/errors"
  autoload :CommunitySkill, "autohand_sdk/discovery_types"
  autoload :SkillRegistryCategory, "autohand_sdk/discovery_types"
  autoload :SkillsRegistryResult, "autohand_sdk/discovery_types"
  autoload :InstallSkillResult, "autohand_sdk/discovery_types"
  autoload :McpServerSummary, "autohand_sdk/discovery_types"
  autoload :McpServersResult, "autohand_sdk/discovery_types"
  autoload :McpTool, "autohand_sdk/discovery_types"
  autoload :McpToolsResult, "autohand_sdk/discovery_types"
  autoload :McpServerConfig, "autohand_sdk/discovery_types"
  autoload :McpServerConfigsResult, "autohand_sdk/discovery_types"
  autoload :ResetParams, "autohand_sdk/rpc_types"
  autoload :ResetResult, "autohand_sdk/rpc_types"
  autoload :PermissionAcknowledgementParams, "autohand_sdk/rpc_types"
  autoload :PermissionAcknowledgementResult, "autohand_sdk/rpc_types"
  autoload :DirectoryAccessResponseParams, "autohand_sdk/rpc_types"
  autoload :DirectoryAccessResponseResult, "autohand_sdk/rpc_types"
  autoload :DirectoryAccessAcknowledgementParams, "autohand_sdk/rpc_types"
  autoload :DirectoryAccessAcknowledgementResult, "autohand_sdk/rpc_types"
  autoload :CHANGE_DECISION_ACTIONS, "autohand_sdk/rpc_types"
  autoload :ChangesDecisionParams, "autohand_sdk/rpc_types"
  autoload :ChangesDecisionError, "autohand_sdk/rpc_types"
  autoload :ChangesDecisionResult, "autohand_sdk/rpc_types"
  autoload :BrowserHandoffCreateParams, "autohand_sdk/rpc_types"
  autoload :BrowserHandoffCreateResult, "autohand_sdk/rpc_types"
  autoload :BrowserHandoffAttachParams, "autohand_sdk/rpc_types"
  autoload :BrowserHandoffAttachResult, "autohand_sdk/rpc_types"
  autoload :BrowserHandoffAttachLatestParams, "autohand_sdk/rpc_types"
  autoload :BrowserHandoffAttachLatestResult, "autohand_sdk/rpc_types"
  autoload :AutomodeStartParams, "autohand_sdk/rpc_types"
  autoload :AutomodeStartResult, "autohand_sdk/rpc_types"
  autoload :AUTOMODE_SESSION_STATUSES, "autohand_sdk/rpc_types"
  autoload :AutomodeCheckpoint, "autohand_sdk/rpc_types"
  autoload :AutomodeState, "autohand_sdk/rpc_types"
  autoload :AutomodeStatusParams, "autohand_sdk/rpc_types"
  autoload :AutomodeStatusResult, "autohand_sdk/rpc_types"
  autoload :AutomodePauseParams, "autohand_sdk/rpc_types"
  autoload :AutomodeOperationResult, "autohand_sdk/rpc_types"
  autoload :AutomodeResumeParams, "autohand_sdk/rpc_types"
  autoload :AutomodeResumeResult, "autohand_sdk/rpc_types"
  autoload :AutomodeCancelParams, "autohand_sdk/rpc_types"
  autoload :AutomodeCancelResult, "autohand_sdk/rpc_types"
  autoload :AutomodeGetLogParams, "autohand_sdk/rpc_types"
  autoload :AutomodeLogCheckpoint, "autohand_sdk/rpc_types"
  autoload :AutomodeIterationLog, "autohand_sdk/rpc_types"
  autoload :AutomodeGetLogResult, "autohand_sdk/rpc_types"

  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end

    def reset_configuration!
      @config = Configuration.new
    end

    def client(**)
      Client.new(config.merge(**))
    end

    def agent(instructions: nil, **options)
      Agent.create(config.merge(**options), instructions: instructions)
    end
  end

  if defined?(Rails::Railtie)
    autoload :Railtie, "autohand_sdk/railtie"
    Railtie
  end
end
