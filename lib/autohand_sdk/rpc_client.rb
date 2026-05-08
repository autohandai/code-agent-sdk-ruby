# frozen_string_literal: true

require_relative "event_queue"
require_relative "transport"
require_relative "utils"

module AutohandSDK
  class RPCClient
    RPC_METHODS = {
      prompt: "autohand.prompt",
      abort: "autohand.abort",
      permission_response: "autohand.permissionResponse",
      get_state: "autohand.getState",
      get_messages: "autohand.getMessages",
      get_supported_models: "autohand.getSupportedModels",
      get_supported_commands: "autohand.getSupportedCommands",
      set_permission_mode: "autohand.permissionModeSet",
      set_plan_mode: "autohand.planModeSet",
      set_model: "autohand.modelSet",
      set_max_thinking_tokens: "autohand.maxThinkingTokensSet",
      apply_flag_settings: "autohand.applyFlagSettings",
      get_context_usage: "autohand.getContextUsage",
      reload_plugins: "autohand.reloadPlugins",
      get_account_info: "autohand.getAccountInfo",
      reconnect_mcp_server: "autohand.mcp.reconnectServer",
      toggle_mcp_server: "autohand.mcp.toggleServer",
      set_mcp_servers: "autohand.mcp.setServers",
      get_hooks: "autohand.hooks.getHooks",
      add_hook: "autohand.hooks.addHook",
      remove_hook: "autohand.hooks.removeHook",
      toggle_hook: "autohand.hooks.toggleHook",
      test_hook: "autohand.hooks.testHook",
      set_hooks_settings: "autohand.hooks.setSettings"
    }.freeze

    NOTIFICATION_EVENT_TYPES = {
      "autohand.agentStart" => "agent_start",
      "autohand.agentEnd" => "agent_end",
      "autohand.turnStart" => "turn_start",
      "autohand.turnEnd" => "turn_end",
      "autohand.messageStart" => "message_start",
      "autohand.messageUpdate" => "message_update",
      "autohand.messageEnd" => "message_end",
      "autohand.toolStart" => "tool_start",
      "autohand.toolUpdate" => "tool_update",
      "autohand.toolEnd" => "tool_end",
      "autohand.permissionRequest" => "permission_request",
      "autohand.directoryAccessRequest" => "directory_access_request",
      "autohand.error" => "error",
      "autohand.hook.fileModified" => "file_modified",
      "autohand.changesBatchStart" => "changes_batch_start",
      "autohand.changesBatchUpdate" => "changes_batch_update",
      "autohand.changesBatchEnd" => "changes_batch_end"
    }.freeze

    CAMEL_TO_SNAKE_KEYS = {
      "sessionId" => "session_id",
      "turnId" => "turn_id",
      "messageId" => "message_id",
      "toolId" => "tool_id",
      "toolName" => "tool_name",
      "requestId" => "request_id",
      "filePath" => "file_path",
      "changeType" => "change_type",
      "contextPercent" => "context_percent",
      "messageCount" => "message_count"
    }.freeze

    def initialize(config = nil, transport: nil, **)
      @config = Configuration.from(config, **)
      @transport = transport || Transport.new(@config)
      @event_queue = EventQueue.new
      @prompt_mutex = Mutex.new
      @started = false
      @transport.on_notification("*") { |params| handle_notification(params) }
    end

    def start
      return if @started

      @transport.start
      startup_check if @config.startup_check && @transport.running?
      @started = true
    end

    def stop
      @transport.stop
      @started = false
    end

    def prompt(params)
      request(RPC_METHODS.fetch(:prompt), Utils.with_rpc_aliases(params))
    end

    def stream_prompt(params)
      Enumerator.new do |yielder|
        @prompt_mutex.synchronize do
          @event_queue.clear
          result, seen_events = run_prompt_request(Utils.with_rpc_aliases(params), yielder)
          synthesize_prompt_events(result, yielder) unless seen_events
        end
      end
    end

    def events
      Enumerator.new do |yielder|
        loop { yielder << @event_queue.pop }
      end
    end

    def abort(params = {})
      request(RPC_METHODS.fetch(:abort), Utils.with_rpc_aliases(params))
    end

    def permission_response(params)
      request(RPC_METHODS.fetch(:permission_response), normalize_permission_response(params))
    end

    def get_state(params = {})
      request(RPC_METHODS.fetch(:get_state), Utils.with_rpc_aliases(params))
    end

    def get_messages(params = {})
      request(RPC_METHODS.fetch(:get_messages), Utils.with_rpc_aliases(params))
    end

    def get_supported_models
      request(RPC_METHODS.fetch(:get_supported_models), {})
    end

    def get_supported_commands
      request(RPC_METHODS.fetch(:get_supported_commands), {})
    end

    def set_permission_mode(mode)
      request(RPC_METHODS.fetch(:set_permission_mode), { "mode" => mode })
    end

    def set_plan_mode(enabled)
      request(RPC_METHODS.fetch(:set_plan_mode), { "enabled" => enabled })
    end

    def set_model(model = nil)
      request(RPC_METHODS.fetch(:set_model), { "model" => model })
    end

    def set_max_thinking_tokens(max_thinking_tokens)
      request(RPC_METHODS.fetch(:set_max_thinking_tokens), { "maxThinkingTokens" => max_thinking_tokens })
    end

    def apply_flag_settings(settings)
      request(RPC_METHODS.fetch(:apply_flag_settings), { "settings" => Utils.with_rpc_aliases(settings) })
    end

    def get_context_usage
      request(RPC_METHODS.fetch(:get_context_usage), {})
    end

    def reload_plugins
      request(RPC_METHODS.fetch(:reload_plugins), {})
    end

    def get_account_info
      request(RPC_METHODS.fetch(:get_account_info), {})
    end

    def reconnect_mcp_server(server_name)
      request(RPC_METHODS.fetch(:reconnect_mcp_server), { "serverName" => server_name })
    end

    def toggle_mcp_server(server_name, enabled)
      request(RPC_METHODS.fetch(:toggle_mcp_server), { "serverName" => server_name, "enabled" => enabled })
    end

    def set_mcp_servers(servers)
      request(RPC_METHODS.fetch(:set_mcp_servers), { "servers" => servers })
    end

    def get_hooks
      request(RPC_METHODS.fetch(:get_hooks), {})
    end

    def add_hook(hook)
      request(RPC_METHODS.fetch(:add_hook), { "hook" => Utils.with_rpc_aliases(hook) })
    end

    def remove_hook(event, index)
      request(RPC_METHODS.fetch(:remove_hook), { "event" => event, "index" => index })
    end

    def toggle_hook(event, index)
      request(RPC_METHODS.fetch(:toggle_hook), { "event" => event, "index" => index })
    end

    def test_hook(hook)
      request(RPC_METHODS.fetch(:test_hook), { "hook" => Utils.with_rpc_aliases(hook) })
    end

    def set_hooks_settings(settings)
      request(RPC_METHODS.fetch(:set_hooks_settings), { "settings" => Utils.with_rpc_aliases(settings) })
    end

    def request(method, params = {})
      @transport.request(method, params || {})
    end

    def running?
      @transport.running?
    end

    private

    def startup_check
      request(RPC_METHODS.fetch(:get_state), {})
      @event_queue.clear
    rescue StandardError => e
      stderr = @transport.stderr_tail
      detail = stderr.to_s.empty? ? "" : "\nCLI stderr:\n#{stderr}"
      @transport.stop
      raise TransportError, "CLI startup check failed: #{e.message}#{detail}"
    end

    def run_prompt_request(params, yielder)
      request_state = { done: false, result: nil, error: nil }
      mutex = Mutex.new
      request_thread = Thread.new do
        result = prompt(params)
        mutex.synchronize { request_state[:result] = result }
      rescue StandardError => e
        mutex.synchronize { request_state[:error] = e }
      ensure
        mutex.synchronize { request_state[:done] = true }
      end

      seen_events = false
      until mutex.synchronize { request_state[:done] }
        event = @event_queue.pop(timeout: 0.05)
        next unless event

        seen_events = true
        yielder << event
      end

      @event_queue.drain.each do |event|
        seen_events = true
        yielder << event
      end

      request_thread.join
      error = mutex.synchronize { request_state[:error] }
      raise error if error

      [mutex.synchronize { request_state[:result] }, seen_events]
    end

    def synthesize_prompt_events(result, yielder)
      return unless result.is_a?(Hash)

      session_id = result["sessionId"] || result["session_id"] || ""
      yielder << { "type" => "agent_start", "session_id" => session_id }
      yielder << { "type" => "message_end", "content" => result["content"] } if result["content"]
      yielder << { "type" => "agent_end", "session_id" => session_id, "reason" => "completed" }
    end

    def normalize_permission_response(params)
      data = Utils.with_rpc_aliases(params)
      case data["decision"]
      when "allow"
        data["decision"] = data["remember"] ? "allow_session" : "allow_once"
      when "deny"
        data["decision"] = data["remember"] ? "deny_session" : "deny_once"
      end
      data
    end

    def handle_notification(params)
      method = params["_method"]
      event_type = NOTIFICATION_EVENT_TYPES[method]
      return unless event_type

      event = notification_to_event(event_type, params)
      @event_queue.push(event)

      return unless method == "autohand.turnEnd"

      @event_queue.push(
        "type" => "agent_end",
        "session_id" => event["session_id"] || event["turn_id"].to_s,
        "reason" => "completed",
        "timestamp" => event["timestamp"]
      )
    end

    def notification_to_event(event_type, params)
      event = params.except("_method")
      CAMEL_TO_SNAKE_KEYS.each do |camel, snake|
        event[snake] = event[camel] if event.key?(camel) && !event.key?(snake)
      end
      event["type"] = event_type
      event
    end
  end
end
