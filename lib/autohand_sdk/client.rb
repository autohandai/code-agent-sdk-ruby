# frozen_string_literal: true

require_relative "configuration"
require_relative "discovery_types"
require_relative "rpc_types"
require_relative "rpc_client"
require_relative "utils"

module AutohandSDK
  # The public client intentionally keeps lifecycle and CLI capability methods together.
  # rubocop:disable Metrics/ClassLength
  class Client
    PERMISSION_SCOPE_DECISIONS = {
      allow: {
        once: "allow_once",
        session: "allow_session",
        project: "allow_always_project",
        user: "allow_always_user"
      },
      deny: {
        once: "deny_once",
        session: "deny_session",
        project: "deny_always_project",
        user: "deny_always_user"
      }
    }.freeze

    attr_reader :config

    def initialize(config = nil, rpc_client: nil, **)
      @config = Configuration.from(config, **)
      @rpc_client = rpc_client || RPCClient.new(@config)
      @started = false
      @lifecycle_mutex = Mutex.new
    end

    def self.open(config = nil, **)
      client = new(config, **)
      client.start
      return client unless block_given?

      begin
        yield client
      ensure
        client.close
      end
    end

    def start
      @lifecycle_mutex.synchronize do
        return self if started?

        @rpc_client.start
        @started = true
        plan_mode = @config.permission_mode == "plan" ? true : @config.plan_mode
        @rpc_client.set_plan_mode(plan_mode) unless plan_mode.nil?
        @rpc_client.apply_flag_settings({ features: @config.features }) if @config.features
        self
      rescue StandardError
        @started = false
        begin
          @rpc_client.stop
        rescue StandardError
          nil
        end
        raise
      end
    end

    def stop
      @lifecycle_mutex.synchronize do
        return self unless @started || rpc_running?

        @rpc_client.stop
        self
      ensure
        @started = false
      end
    end

    alias close stop

    def prompt(message_or_params, **)
      ensure_started
      @rpc_client.prompt(prompt_params(message_or_params, **))
    end

    def stream_prompt(message_or_params, **, &block)
      ensure_started
      events = @rpc_client.stream_prompt(prompt_params(message_or_params, **))
      return events unless block

      events.each(&block)
    end

    def stream_input(prompts)
      Enumerator.new do |yielder|
        prompts.each do |params|
          stream_prompt(params).each { |event| yielder << event }
        end
      end
    end

    def abort(reason: nil)
      ensure_started
      @rpc_client.abort(Utils.compact_hash("reason" => reason))
    end

    alias interrupt abort

    def reset
      ensure_started
      ResetResult.from_rpc(@rpc_client.reset(ResetParams.new.to_rpc))
    end

    def create_browser_handoff(extension_id: nil, install_url: nil)
      ensure_started
      result = @rpc_client.create_browser_handoff(extension_id: extension_id, install_url: install_url)
      BrowserHandoffCreateResult.from_rpc(result)
    end

    def attach_browser_handoff(token)
      ensure_started
      BrowserHandoffAttachResult.from_rpc(@rpc_client.attach_browser_handoff(token))
    end

    def permission_response(params = nil, **options)
      ensure_started
      data = params.is_a?(Hash) ? params.merge(options) : options
      @rpc_client.permission_response(data)
    end

    def allow_permission(request_id, scope: :once)
      permission_response(request_id: request_id, decision: permission_decision(:allow, scope))
    end

    def deny_permission(request_id, scope: :once)
      permission_response(request_id: request_id, decision: permission_decision(:deny, scope))
    end

    def suggest_permission_alternative(request_id, alternative)
      permission_response(request_id: request_id, decision: "alternative", alternative: alternative)
    end

    def set_permission_mode(mode)
      ensure_started
      if mode.to_s == "plan"
        set_plan_mode(true)
      else
        @rpc_client.set_permission_mode(mode)
      end
      @config.permission_mode = mode.to_s if mode
    end

    def set_plan_mode(enabled)
      ensure_started
      @rpc_client.set_plan_mode(enabled)
      @config.plan_mode = enabled
    end

    def enable_plan_mode
      set_plan_mode(true)
    end

    def disable_plan_mode
      set_plan_mode(false)
    end

    def set_model(model = nil)
      ensure_started
      @rpc_client.set_model(model)
      @config.model = model if model
    end

    def set_max_thinking_tokens(max_thinking_tokens)
      ensure_started
      @rpc_client.set_max_thinking_tokens(max_thinking_tokens)
    end

    def apply_flag_settings(settings)
      ensure_started
      @rpc_client.apply_flag_settings(settings)
    end

    def get_state(include_context: nil)
      ensure_started
      @rpc_client.get_state(Utils.compact_hash("include_context" => include_context))
    end

    def get_messages(limit: nil, before: nil)
      ensure_started
      @rpc_client.get_messages(Utils.compact_hash("limit" => limit, "before" => before))
    end

    def supported_models
      ensure_started
      result = @rpc_client.get_supported_models
      result.is_a?(Hash) ? result.fetch("models", []) : result
    end

    def supported_commands
      ensure_started
      result = @rpc_client.get_supported_commands
      commands = result.is_a?(Hash) ? result.fetch("commands", result.fetch("agents", [])) : result
      Array(commands).filter_map do |command|
        next unless command.is_a?(String)

        command.start_with?("/") ? command : "/#{command}"
      end
    end

    def get_skills_registry(force_refresh: nil)
      ensure_started
      result = @rpc_client.get_skills_registry(force_refresh: force_refresh)
      SkillsRegistryResult.from_rpc(result)
    end

    def install_skill(skill_name, scope:, force: nil)
      normalized_scope = scope.to_s
      unless %w[user project].include?(normalized_scope)
        raise ArgumentError, "skill scope must be one of: user, project"
      end

      ensure_started
      result = @rpc_client.install_skill(skill_name, scope: normalized_scope, force: force)
      InstallSkillResult.from_rpc(result)
    end

    def list_mcp_servers
      ensure_started
      McpServersResult.from_rpc(@rpc_client.list_mcp_servers)
    end

    def list_mcp_tools(server_name: nil)
      ensure_started
      McpToolsResult.from_rpc(@rpc_client.list_mcp_tools(server_name: server_name))
    end

    def get_mcp_server_configs
      ensure_started
      McpServerConfigsResult.from_rpc(@rpc_client.get_mcp_server_configs)
    end

    def supports_command?(command)
      supported_commands.include?(Utils.format_slash_command(command))
    end

    def stream_command(command, args = nil, **options, &)
      stream_prompt(Utils.format_slash_command(command, args), **options, &)
    end

    def get_context_usage
      ensure_started
      @rpc_client.get_context_usage
    end

    def reload_plugins
      ensure_started
      @rpc_client.reload_plugins
    end

    def account_info
      ensure_started
      @rpc_client.get_account_info
    end

    def reconnect_mcp_server(server_name)
      ensure_started
      @rpc_client.reconnect_mcp_server(server_name)
    end

    def toggle_mcp_server(server_name, enabled)
      ensure_started
      @rpc_client.toggle_mcp_server(server_name, enabled)
    end

    def set_mcp_servers(servers)
      ensure_started
      @rpc_client.set_mcp_servers(servers)
    end

    def get_hooks
      ensure_started
      @rpc_client.get_hooks
    end

    def add_hook(hook)
      ensure_started
      @rpc_client.add_hook(hook)
    end

    def remove_hook(event, index)
      ensure_started
      @rpc_client.remove_hook(event, index)
    end

    def toggle_hook(event, index)
      ensure_started
      @rpc_client.toggle_hook(event, index)
    end

    def test_hook(hook)
      ensure_started
      @rpc_client.test_hook(hook)
    end

    def set_hooks_settings(settings)
      ensure_started
      @rpc_client.set_hooks_settings(settings)
    end

    def get_goal
      ensure_started
      @rpc_client.get_goal
    end

    def create_goal(params = nil, **options)
      ensure_started
      @rpc_client.create_goal(merge_params(params, options))
    end

    def update_goal(params = nil, **options)
      ensure_started
      @rpc_client.update_goal(merge_params(params, options))
    end

    def clear_goal
      ensure_started
      @rpc_client.clear_goal
    end

    def queue_goal(params = nil, **options)
      ensure_started
      @rpc_client.queue_goal(merge_params(params, options))
    end

    def start_queued_goal
      ensure_started
      @rpc_client.start_queued_goal
    end

    def list_goal_templates
      ensure_started
      @rpc_client.list_goal_templates
    end

    def start_autoresearch(params = nil, **options)
      ensure_started
      @rpc_client.start_autoresearch(merge_params(params, options))
    end

    def get_autoresearch_status
      ensure_started
      @rpc_client.get_autoresearch_status
    end

    def stop_autoresearch
      ensure_started
      @rpc_client.stop_autoresearch
    end

    def get_autoresearch_history
      ensure_started
      @rpc_client.get_autoresearch_history
    end

    def replay_autoresearch(params = nil, **options)
      ensure_started
      @rpc_client.replay_autoresearch(merge_params(params, options))
    end

    def rescore_autoresearch(params = nil, **options)
      ensure_started
      @rpc_client.rescore_autoresearch(merge_params(params, options))
    end

    def compare_autoresearch(params = nil, **options)
      ensure_started
      @rpc_client.compare_autoresearch(merge_params(params, options))
    end

    def get_autoresearch_pareto
      ensure_started
      @rpc_client.get_autoresearch_pareto
    end

    def pin_autoresearch(params = nil, **options)
      ensure_started
      @rpc_client.pin_autoresearch(merge_params(params, options))
    end

    def prune_autoresearch(params = nil, **options)
      ensure_started
      @rpc_client.prune_autoresearch(merge_params(params, options))
    end

    def started?
      @started && rpc_running?
    end

    def connected?
      @rpc_client.running?
    end

    def update_config(**)
      @lifecycle_mutex.synchronize do
        raise ConfigurationError, "update_config must be called before start" if started?

        @config = @config.merge(**)
        @rpc_client = RPCClient.new(@config)
        self
      end
    end

    private

    def ensure_started
      start unless started?
    end

    def rpc_running?
      return @rpc_client.running? if @rpc_client.respond_to?(:running?)

      @started
    end

    def prompt_params(message_or_params, **options)
      params = if message_or_params.is_a?(Hash)
                 Utils.normalize_hash(message_or_params)
               else
                 { message: message_or_params.to_s }
               end
      Utils.with_rpc_aliases(params.merge(Utils.normalize_hash(options)))
    end

    def merge_params(params, options)
      data = params.nil? ? {} : Utils.normalize_hash(params)
      raise ArgumentError, "expected a Hash of parameters" unless data.is_a?(Hash)

      data.merge(Utils.normalize_hash(options))
    end

    def permission_decision(action, scope)
      PERMISSION_SCOPE_DECISIONS.fetch(action).fetch(scope.to_sym)
    rescue KeyError
      raise ArgumentError, "permission scope must be one of: once, session, project, user"
    end
  end
  # rubocop:enable Metrics/ClassLength
end
