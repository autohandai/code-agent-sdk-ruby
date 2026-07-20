# frozen_string_literal: true

require_relative "event_queue"
require_relative "rpc_types"
require_relative "transport"
require_relative "utils"
require_relative "autoresearch_rpc"

module AutohandSDK
  # RPC routing and event lifecycle share state and remain co-located intentionally.
  # rubocop:disable Metrics/ClassLength
  class RPCClient
    include AutoresearchRPC

    PROMPT_CLEANUP_TIMEOUT = 2.0

    class RequestWorker
      def initialize(&work)
        @mutex = Mutex.new
        @done = false
        @result = nil
        @error = nil
        @thread = Thread.new do
          result = work.call
          @mutex.synchronize { @result = result }
        rescue StandardError => e
          @mutex.synchronize { @error = e }
        ensure
          @mutex.synchronize { @done = true }
        end
      end

      def done?
        @mutex.synchronize { @done }
      end

      def result
        @mutex.synchronize { @result }
      end

      def error
        @mutex.synchronize { @error }
      end

      def join(timeout = nil)
        @thread.join(timeout)
      end

      def stop
        return unless @thread.alive?

        @thread.kill
        @thread.join
      end
    end

    PromptContext = Struct.new(:generation, :queue, keyword_init: true)

    RPC_METHODS = {
      prompt: "autohand.prompt",
      abort: "autohand.abort",
      reset: "autohand.reset",
      browser_handoff_create: "autohand.browserHandoff.create",
      browser_handoff_attach: "autohand.browserHandoff.attach",
      browser_handoff_attach_latest: "autohand.browserHandoff.attachLatest",
      automode_start: "autohand.automode.start",
      automode_status: "autohand.automode.status",
      automode_pause: "autohand.automode.pause",
      automode_resume: "autohand.automode.resume",
      automode_cancel: "autohand.automode.cancel",
      automode_get_log: "autohand.automode.getLog",
      permission_response: "autohand.permissionResponse",
      permission_acknowledged: "autohand.permissionAcknowledged",
      directory_access_response: "autohand.directoryAccessResponse",
      directory_access_acknowledged: "autohand.directoryAccessAcknowledged",
      changes_decision: "autohand.changesDecision",
      get_state: "autohand.getState",
      get_messages: "autohand.getMessages",
      get_supported_models: "autohand.getSupportedModels",
      get_supported_commands: "autohand.getSupportedCommands",
      get_skills_registry: "autohand.getSkillsRegistry",
      install_skill: "autohand.installSkill",
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
      list_mcp_servers: "autohand.mcp.listServers",
      list_mcp_tools: "autohand.mcp.listTools",
      get_mcp_server_configs: "autohand.mcp.getServerConfigs",
      get_hooks: "autohand.hooks.getHooks",
      add_hook: "autohand.hooks.addHook",
      remove_hook: "autohand.hooks.removeHook",
      toggle_hook: "autohand.hooks.toggleHook",
      test_hook: "autohand.hooks.testHook",
      set_hooks_settings: "autohand.hooks.setSettings",
      get_goal: "autohand.goal.get",
      create_goal: "autohand.goal.create",
      update_goal: "autohand.goal.update",
      clear_goal: "autohand.goal.clear",
      queue_goal: "autohand.goal.queue",
      start_queued_goal: "autohand.goal.startQueued",
      list_goal_templates: "autohand.goal.listTemplates",
      start_autoresearch: "autohand.autoresearch.start",
      get_autoresearch_status: "autohand.autoresearch.status",
      stop_autoresearch: "autohand.autoresearch.stop",
      get_autoresearch_history: "autohand.autoresearch.history",
      replay_autoresearch: "autohand.autoresearch.replay",
      rescore_autoresearch: "autohand.autoresearch.rescore",
      compare_autoresearch: "autohand.autoresearch.compare",
      get_autoresearch_pareto: "autohand.autoresearch.pareto",
      pin_autoresearch: "autohand.autoresearch.pin",
      prune_autoresearch: "autohand.autoresearch.prune"
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
      "autohand.changesBatchEnd" => "changes_batch_end",
      "autohand.autoresearch.start" => "autoresearch",
      "autohand.autoresearch.status" => "autoresearch",
      "autohand.autoresearch.pause" => "autoresearch",
      "autohand.autoresearch.event" => "autoresearch"
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
      "messageCount" => "message_count",
      "tokensUsed" => "tokens_used",
      "tokensUsageStatus" => "tokens_usage_status",
      "durationMs" => "duration_ms",
      "runsLogged" => "runs_logged",
      "statusText" => "status_text",
      "maxIterations" => "max_iterations",
      "attemptId" => "attempt_id"
    }.freeze

    def initialize(config = nil, transport: nil, **)
      @config = Configuration.from(config, **)
      @transport = transport || Transport.new(@config)
      @event_queue = EventQueue.new
      @event_subscribers = []
      @event_subscribers_mutex = Mutex.new
      @prompt_context = nil
      @prompt_state_mutex = Mutex.new
      @prompt_serial_mutex = Mutex.new
      @prompt_generation = 0
      @start_stop_mutex = Mutex.new
      @started_mutex = Mutex.new
      @started = false
      @active_transport_generation = nil
      @has_started_transport = false
      @transport.on_notification("*") { |params| handle_notification(params) }
      return unless @transport.respond_to?(:on_termination)

      @transport.on_termination do |error, generation_id|
        handle_transport_termination(error, generation_id)
      end
    end

    def start
      @start_stop_mutex.synchronize do
        return self if started? && @transport.running?

        mark_started(false)
        @active_transport_generation = nil
        close_event_streams if @has_started_transport
        @transport.start
        @has_started_transport = true
        @active_transport_generation = transport_generation_id
        startup_check if @config.startup_check
        mark_started(true)
      rescue StandardError
        mark_started(false)
        @active_transport_generation = nil
        close_event_streams
        raise
      end
      self
    end

    def stop
      @start_stop_mutex.synchronize do
        @transport.stop
      ensure
        mark_started(false)
        @active_transport_generation = nil
        close_event_streams
      end
      self
    end

    def prompt(params)
      request(RPC_METHODS.fetch(:prompt), Utils.with_rpc_aliases(params))
    end

    def stream_prompt(params)
      Enumerator.new do |yielder|
        @prompt_serial_mutex.synchronize do
          context = open_prompt_context
          begin
            run_prompt_request(Utils.with_rpc_aliases(params), yielder, context)
          ensure
            close_prompt_context(context)
          end
        end
      end
    end

    def events
      Enumerator.new do |yielder|
        queue = EventQueue.new
        @event_subscribers_mutex.synchronize do
          @event_queue.drain.each { |event| queue.push(event) }
          @event_subscribers << queue
        end
        begin
          loop do
            event = queue.pop
            break if event.nil? && queue.closed?

            yielder << event if event
          end
        ensure
          @event_subscribers_mutex.synchronize { @event_subscribers.delete(queue) }
          queue.close
        end
      end
    end

    def abort(params = {})
      request(RPC_METHODS.fetch(:abort), Utils.with_rpc_aliases(params))
    end

    def reset(params = {})
      request(RPC_METHODS.fetch(:reset), params)
    end

    def create_browser_handoff(extension_id: nil, install_url: nil)
      params = BrowserHandoffCreateParams.new(extension_id: extension_id, install_url: install_url)
      request(RPC_METHODS.fetch(:browser_handoff_create), params.to_rpc)
    end

    def attach_browser_handoff(token)
      params = BrowserHandoffAttachParams.new(token: token)
      request(RPC_METHODS.fetch(:browser_handoff_attach), params.to_rpc)
    end

    def attach_latest_browser_handoff
      params = BrowserHandoffAttachLatestParams.new
      request(RPC_METHODS.fetch(:browser_handoff_attach_latest), params.to_rpc)
    end

    # rubocop:disable Metrics/ParameterLists
    def start_automode(
      prompt,
      max_iterations: nil,
      completion_promise: nil,
      use_worktree: nil,
      checkpoint_interval: nil,
      max_runtime: nil,
      max_cost: nil
    )
      params = AutomodeStartParams.new(
        prompt: prompt,
        max_iterations: max_iterations,
        completion_promise: completion_promise,
        use_worktree: use_worktree,
        checkpoint_interval: checkpoint_interval,
        max_runtime: max_runtime,
        max_cost: max_cost
      )
      request(RPC_METHODS.fetch(:automode_start), params.to_rpc)
    end
    # rubocop:enable Metrics/ParameterLists

    def get_automode_status
      request(RPC_METHODS.fetch(:automode_status), AutomodeStatusParams.new.to_rpc)
    end

    def pause_automode
      request(RPC_METHODS.fetch(:automode_pause), AutomodePauseParams.new.to_rpc)
    end

    def resume_automode
      request(RPC_METHODS.fetch(:automode_resume), AutomodeResumeParams.new.to_rpc)
    end

    def cancel_automode(reason: nil)
      request(RPC_METHODS.fetch(:automode_cancel), AutomodeCancelParams.new(reason: reason).to_rpc)
    end

    def get_automode_log(limit: nil)
      request(RPC_METHODS.fetch(:automode_get_log), AutomodeGetLogParams.new(limit: limit).to_rpc)
    end

    def permission_response(params)
      request(RPC_METHODS.fetch(:permission_response), normalize_permission_response(params))
    end

    def acknowledge_permission(request_id)
      params = PermissionAcknowledgementParams.new(request_id: request_id)
      request(RPC_METHODS.fetch(:permission_acknowledged), params.to_rpc)
    end

    def respond_to_directory_access(request_id, granted:)
      params = DirectoryAccessResponseParams.new(request_id: request_id, granted: granted)
      request(RPC_METHODS.fetch(:directory_access_response), params.to_rpc)
    end

    def acknowledge_directory_access(request_id)
      params = DirectoryAccessAcknowledgementParams.new(request_id: request_id)
      request(RPC_METHODS.fetch(:directory_access_acknowledged), params.to_rpc)
    end

    def decide_changes(batch_id, action:, selected_change_ids: nil)
      params = ChangesDecisionParams.new(
        batch_id: batch_id,
        action: action,
        selected_change_ids: selected_change_ids
      )
      request(RPC_METHODS.fetch(:changes_decision), params.to_rpc)
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

    def get_skills_registry(force_refresh: nil)
      request(RPC_METHODS.fetch(:get_skills_registry), { "forceRefresh" => force_refresh }.compact)
    end

    def install_skill(skill_name, scope:, force: nil)
      request(
        RPC_METHODS.fetch(:install_skill),
        { "skillName" => skill_name.to_s, "scope" => scope.to_s, "force" => force }.compact
      )
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
      request(RPC_METHODS.fetch(:apply_flag_settings), { "settings" => camelize_hash(Utils.normalize_hash(settings)) })
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

    def list_mcp_servers
      request(RPC_METHODS.fetch(:list_mcp_servers), {})
    end

    def list_mcp_tools(server_name: nil)
      request(RPC_METHODS.fetch(:list_mcp_tools), { "serverName" => server_name }.compact)
    end

    def get_mcp_server_configs
      request(RPC_METHODS.fetch(:get_mcp_server_configs), {})
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

    def get_goal
      request(RPC_METHODS.fetch(:get_goal), {})
    end

    def create_goal(params)
      request(RPC_METHODS.fetch(:create_goal), goal_params(params))
    end

    def update_goal(params)
      request(RPC_METHODS.fetch(:update_goal), goal_params(params))
    end

    def clear_goal
      request(RPC_METHODS.fetch(:clear_goal), {})
    end

    def queue_goal(params)
      request(RPC_METHODS.fetch(:queue_goal), goal_params(params))
    end

    def start_queued_goal
      request(RPC_METHODS.fetch(:start_queued_goal), {})
    end

    def list_goal_templates
      request(RPC_METHODS.fetch(:list_goal_templates), {})
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

    def run_prompt_request(params, yielder, context)
      worker = RequestWorker.new { prompt(params) }
      seen_events = false
      terminal_seen = false
      cleanup_required = true

      loop do
        event = context.queue.pop(timeout: 0.05)
        if event
          seen_events = true
          terminal_seen = terminal_event?(event)
          yielder << event
          break if terminal_seen

          next
        end

        raise TransportError, "Prompt event stream closed" if context.queue.closed?
        next unless worker.done?

        if worker.error
          cleanup_required = seen_events
          raise worker.error
        end

        result = worker.result
        cleanup_required = seen_events if prompt_rejected?(result)
        raise_prompt_rejection(result)
        next unless legacy_prompt_result?(result)

        terminal_seen = true
        if seen_events
          synthesize_prompt_terminal(result, yielder)
        else
          synthesize_prompt_events(result, yielder)
        end
        break
      end

      settle_prompt_worker(worker)
    ensure
      cleanup_abandoned_prompt(context) if worker && cleanup_required && !terminal_seen
      worker&.stop
    end

    def open_prompt_context
      @prompt_state_mutex.synchronize do
        @prompt_generation += 1
        PromptContext.new(generation: @prompt_generation, queue: EventQueue.new).tap do |context|
          @prompt_context = context
        end
      end
    end

    def close_prompt_context(context)
      @prompt_state_mutex.synchronize do
        @prompt_context = nil if @prompt_context.equal?(context) && @prompt_context.generation == context.generation
      end
      context.queue.close
    end

    def settle_prompt_worker(worker)
      unless worker.join(PROMPT_CLEANUP_TIMEOUT)
        safely_stop_transport
        raise TransportError, "Prompt acknowledgement did not settle after terminal event"
      end

      raise worker.error if worker.error

      raise_prompt_rejection(worker.result)
    end

    def cleanup_abandoned_prompt(context)
      return unless @transport.running?

      abort_worker = RequestWorker.new { abort }
      deadline = monotonic_now + PROMPT_CLEANUP_TIMEOUT
      terminal_seen = drain_prompt_until_terminal(context, abort_worker, deadline)
      return if terminal_seen && abort_worker.join([deadline - monotonic_now, 0].max)

      safely_stop_transport
    ensure
      abort_worker&.stop
    end

    def drain_prompt_until_terminal(context, abort_worker, deadline)
      loop do
        remaining = deadline - monotonic_now
        return false if remaining <= 0

        event = context.queue.pop(timeout: [remaining, 0.05].min)
        return true if terminal_event?(event)
        return false if context.queue.closed?
        return false if abort_worker.done? && abort_worker.error
      end
    end

    def safely_stop_transport
      @start_stop_mutex.synchronize do
        @transport.stop
      rescue StandardError
        nil
      ensure
        mark_started(false)
        @active_transport_generation = nil
        close_event_streams
      end
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def terminal_event?(event)
      event.is_a?(Hash) && event["type"] == "agent_end"
    end

    def legacy_prompt_result?(result)
      return false unless result.is_a?(Hash)
      return true if result.key?("content")

      !result.key?("success") && (result.key?("sessionId") || result.key?("session_id"))
    end

    def raise_prompt_rejection(result)
      return unless prompt_rejected?(result)

      raise RPCError, result["error"] || result["message"] || "Prompt request was rejected"
    end

    def prompt_rejected?(result)
      result.is_a?(Hash) && result["success"] == false
    end

    def synthesize_prompt_events(result, yielder)
      return unless result.is_a?(Hash)

      session_id = result["sessionId"] || result["session_id"] || ""
      yielder << { "type" => "agent_start", "session_id" => session_id }
      yielder << { "type" => "message_end", "content" => result["content"] } if result["content"]
      synthesize_prompt_terminal(result, yielder)
    end

    def synthesize_prompt_terminal(result, yielder)
      session_id = result["sessionId"] || result["session_id"] || ""
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

    def goal_params(params)
      Utils.normalize_hash(params).each_with_object({}) do |(key, value), result|
        result[key.to_s] = value
      end
    end

    def handle_notification(params)
      method = params["_method"]
      event_type = NOTIFICATION_EVENT_TYPES[method]
      return unless event_type

      event = notification_to_event(event_type, params)
      publish_event(event)

      return unless method == "autohand.turnEnd"

      publish_event(
        "type" => "agent_end",
        "session_id" => event["session_id"] || event["turn_id"].to_s,
        "reason" => "completed",
        "timestamp" => event["timestamp"]
      )
    end

    def publish_event(event)
      prompt_context = @prompt_state_mutex.synchronize do
        context = @prompt_context
        context if context&.generation == @prompt_generation
      end
      prompt_context&.queue&.push(event)
      @event_subscribers_mutex.synchronize do
        if @event_subscribers.empty?
          @event_queue.push(event)
        else
          @event_subscribers.each { |queue| queue.push(event) }
        end
      end
    end

    def close_event_streams
      prompt_context = @prompt_state_mutex.synchronize { @prompt_context }
      prompt_context&.queue&.close
      @event_queue.clear
      subscribers = @event_subscribers_mutex.synchronize do
        @event_subscribers.dup.tap { @event_subscribers.clear }
      end
      subscribers.each(&:close)
    end

    def handle_transport_termination(_error, generation_id)
      @start_stop_mutex.synchronize do
        return if generation_id && generation_id != @active_transport_generation

        mark_started(false)
        @active_transport_generation = nil
        close_event_streams
      end
    end

    def mark_started(value)
      @started_mutex.synchronize { @started = value }
    end

    def started?
      @started_mutex.synchronize { @started }
    end

    def transport_generation_id
      @transport.generation_id if @transport.respond_to?(:generation_id)
    end

    def notification_to_event(event_type, params)
      event = params.except("_method")
      CAMEL_TO_SNAKE_KEYS.each do |camel, snake|
        event[snake] = event[camel] if event.key?(camel) && !event.key?(snake)
      end
      event["type"] = event_type
      case params["_method"]
      when "autohand.autoresearch.start" then event["phase"] = "start"
      when "autohand.autoresearch.status" then event["phase"] = "status"
      when "autohand.autoresearch.pause" then event["phase"] = "pause"
      end
      event
    end
  end
  # rubocop:enable Metrics/ClassLength
end
