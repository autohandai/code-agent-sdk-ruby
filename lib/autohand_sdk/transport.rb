# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "shellwords"

require_relative "configuration"
require_relative "cli_installer"
require_relative "errors"

module AutohandSDK
  # Process-generation ownership and JSON-RPC framing are kept together deliberately.
  # rubocop:disable Metrics/ClassLength
  class Transport
    PROCESS_STOP_TIMEOUT = 1.0
    READER_JOIN_TIMEOUT = 0.5

    class Waiter
      def initialize
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @resolved = false
        @value = nil
        @error = nil
      end

      def resolve(value)
        @mutex.synchronize do
          return if @resolved

          @resolved = true
          @value = value
          @condition.broadcast
        end
      end

      def reject(error)
        @mutex.synchronize do
          return if @resolved

          @resolved = true
          @error = error
          @condition.broadcast
        end
      end

      def wait(timeout:, message:)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

        @mutex.synchronize do
          until @resolved
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            raise RequestTimeoutError, message if remaining <= 0

            @condition.wait(@mutex, remaining)
          end

          raise @error if @error

          @value
        end
      end
    end

    Generation = Struct.new(
      :id,
      :stdin,
      :stdout,
      :stderr,
      :wait_thread,
      :stdout_thread,
      :stderr_thread,
      :stopping,
      keyword_init: true
    )

    def initialize(config = nil, **)
      @config = Configuration.from(config, **)
      @request_id = 0
      @pending = {}
      @pending_mutex = Mutex.new
      @notification_callbacks = Hash.new { |hash, key| hash[key] = [] }
      @termination_callbacks = []
      @callbacks_mutex = Mutex.new
      @stderr_lines = []
      @stderr_tail = ""
      @stderr_mutex = Mutex.new
      @state_mutex = Mutex.new
      @lifecycle_mutex = Mutex.new
      @write_mutex = Mutex.new
      @generation_sequence = 0
      @generation = nil
    end

    def stderr_tail
      @stderr_mutex.synchronize { @stderr_tail.dup }
    end

    def generation_id
      current_generation&.id
    end

    def start
      @lifecycle_mutex.synchronize do
        return self if running?

        retire_stale_generation
        copy_skill_files if @config.copy_skill_files && (@config.skills.any? || @config.skill_files.any?)

        generation = spawn_generation
        activate_generation(generation)
        generation.stdout_thread = Thread.new { read_stdout(generation) }
        generation.stderr_thread = Thread.new { read_stderr(generation) }
        Thread.pass

        unless generation_running?(generation)
          code = generation.wait_thread.value&.exitstatus
          error = TransportError.new(
            "CLI process exited during startup with code #{code}#{format_stderr_tail}"
          )
          shutdown_generation(generation, error: error)
          raise error
        end
      end

      self
    end

    def stop
      @lifecycle_mutex.synchronize do
        generation = current_generation
        return self unless generation

        shutdown_generation(
          generation,
          error: TransportError.new("Transport stopped before receiving a response")
        )
      end

      self
    end

    def request(method, params = {})
      generation = current_running_generation
      raise TransportNotStartedError, "Transport not started" unless generation

      request_id = next_request_id
      waiter = Waiter.new
      @pending_mutex.synchronize { @pending[request_id] = waiter }

      payload = {
        jsonrpc: "2.0",
        method: method,
        params: params || {},
        id: request_id
      }

      begin
        @write_mutex.synchronize do
          unless generation_current_and_running?(generation)
            raise TransportNotStartedError, "Transport generation is no longer running"
          end

          generation.stdin.write("#{JSON.generate(payload)}\n")
          generation.stdin.flush
        end
      rescue IOError, Errno::EPIPE => e
        remove_waiter(request_id)
        raise TransportError,
              "Failed to write RPC request #{method} to CLI stdin#{format_stderr_tail}: #{e.message}"
      end

      response = waiter.wait(timeout: @config.timeout.to_f / 1_000, message: "Request timeout: #{method}")
      remove_waiter(request_id)
      raise_rpc_error(method, response) if response.key?("error")

      response["result"]
    ensure
      remove_waiter(request_id) if request_id
    end

    def on_notification(method, &block)
      raise ArgumentError, "notification callback required" unless block

      @callbacks_mutex.synchronize { @notification_callbacks[method] << block }
      lambda do
        @callbacks_mutex.synchronize { @notification_callbacks[method].delete(block) }
      end
    end

    def on_termination(&block)
      raise ArgumentError, "termination callback required" unless block

      @callbacks_mutex.synchronize { @termination_callbacks << block }
      -> { @callbacks_mutex.synchronize { @termination_callbacks.delete(block) } }
    end

    def running?
      generation = current_generation
      generation ? generation_running?(generation) : false
    end

    private

    def next_request_id
      @pending_mutex.synchronize do
        @request_id += 1
      end
    end

    def remove_waiter(request_id)
      @pending_mutex.synchronize { @pending.delete(request_id) }
    end

    def spawn_generation
      env = build_environment
      args = build_args
      stdin, stdout, stderr, wait_thread = Open3.popen3(
        env,
        *args,
        chdir: @config.cwd,
        unsetenv_others: true
      )
      stdin.sync = true
      @stderr_mutex.synchronize do
        @stderr_lines = []
        @stderr_tail = ""
      end

      Generation.new(
        id: next_generation_id,
        stdin: stdin,
        stdout: stdout,
        stderr: stderr,
        wait_thread: wait_thread,
        stopping: false
      )
    end

    def next_generation_id
      @state_mutex.synchronize do
        @generation_sequence += 1
      end
    end

    def activate_generation(generation)
      @state_mutex.synchronize { @generation = generation }
    end

    def current_generation
      @state_mutex.synchronize { @generation }
    end

    def current_running_generation
      @state_mutex.synchronize do
        generation = @generation
        generation if generation && !generation.stopping && generation.wait_thread.alive?
      end
    end

    def generation_running?(generation)
      @state_mutex.synchronize do
        @generation.equal?(generation) && !generation.stopping && generation.wait_thread.alive?
      end
    end

    def generation_current_and_running?(generation)
      generation_running?(generation)
    end

    def retire_stale_generation
      generation = current_generation
      return unless generation

      shutdown_generation(
        generation,
        error: TransportError.new("Previous CLI transport generation ended")
      )
    end

    def shutdown_generation(generation, error:)
      claimed = @state_mutex.synchronize do
        next unless @generation.equal?(generation)

        generation.stopping = true
        @generation = nil
        generation
      end
      return unless claimed

      fail_pending_requests(error)
      @write_mutex.synchronize { close_io(generation.stdin) }
      terminate_process(generation)
      close_io(generation.stdout)
      close_io(generation.stderr)
      join_reader_threads(generation)
      generation
    end

    def handle_unexpected_termination(generation, error)
      claimed = @lifecycle_mutex.synchronize do
        shutdown_generation(generation, error: error)
      end
      notify_termination(error, generation.id) if claimed
    end

    def join_reader_threads(generation)
      [generation.stdout_thread, generation.stderr_thread].each do |thread|
        next unless thread
        next if thread.equal?(Thread.current)
        next if thread.join(READER_JOIN_TIMEOUT)

        thread.kill
        thread.join(READER_JOIN_TIMEOUT)
      end
      generation.stdout_thread = nil
      generation.stderr_thread = nil
    end

    def notify_termination(error, generation_id)
      callbacks = @callbacks_mutex.synchronize { @termination_callbacks.dup }
      callbacks.each do |callback|
        case callback.arity
        when 0 then callback.call
        when 1 then callback.call(error)
        else callback.call(error, generation_id)
        end
      rescue StandardError => e
        @config.logger.error("Unhandled termination callback error: #{e.class}: #{e.message}")
      end
    end

    def build_args
      args = [cli_binary, "--mode", "rpc"]
      append_current_runtime_options(args)
      append_flag(args, "--unrestricted", @config.unrestricted)
      append_flag(args, "--auto-mode", @config.auto_mode)
      append_flag(args, "--auto-skill", @config.auto_skill)
      append_context_compact(args)
      append_flag(args, "--persist-session", @config.persist_session)
      append_value(args, "--session-id", @config.session_id)
      append_flag(args, "--resume", @config.resume)
      append_flag(args, "--continue", @config.continue_session)
      append_value(args, "--session-path", @config.session_path)
      append_value(args, "--auto-save-interval", @config.auto_save_interval)
      append_value(args, "--max-tokens", @config.max_tokens)
      append_value(args, "--compression-threshold", @config.compression_threshold)
      append_value(args, "--summarization-threshold", @config.summarization_threshold)
      append_value(args, "--skills", @config.skills.join(",")) unless @config.skills.empty?
      append_value(args, "--skill-sources", normalized_skill_sources.join(",")) unless normalized_skill_sources.empty?
      append_flag(args, "--install-missing-skills", @config.install_missing_skills)
      append_value(args, "--permission-mode", @config.permission_mode) if startup_permission_mode?
      unless @config.permission_allow_list.empty?
        append_value(args, "--permission-allow-list",
                     @config.permission_allow_list.join(","))
      end
      unless @config.permission_deny_list.empty?
        append_value(args, "--permission-deny-list",
                     @config.permission_deny_list.join(","))
      end
      append_value(args, "--max-iterations", @config.max_iterations)
      append_value(args, "--max-runtime", @config.max_runtime)
      append_value(args, "--max-cost", @config.max_cost)
      append_value(args, "--sys-prompt", @config.sys_prompt)
      append_value(args, "--append-sys-prompt", @config.append_sys_prompt)
      append_value(args, "--model", @config.model)
      append_value(args, "--temperature", @config.temperature)
      append_value(args, "--yolo", @config.yolo)
      append_value(args, "--yolo-timeout", @config.yolo_timeout)
      @config.add_dir.each { |directory| append_value(args, "--add-dir", directory) }
      args.concat(@config.extra_args)
      args
    end

    def append_current_runtime_options(args)
      append_flag(args, "--bare", @config.bare)
      args << "--no-idle-logout" if @config.idle_logout == false
      append_flag(args, "-c", @config.auto_commit)
      append_flag(args, "--agents-md-create", @config.agents_md_create)
      append_flag(args, "--agents-md-auto-update", @config.agents_md_auto_update)
      args << "--agents-md" if @config.agents_md_enable == true
      args << "--no-agents-md" if @config.agents_md_enable == false
      append_value(args, "--agents-md-path", @config.agents_md_path)
      append_value(args, "--fork", @config.fork)
      append_value(args, "--system-prompt-file", @config.system_prompt_file)
      append_value(args, "--append-system-prompt-file", @config.append_system_prompt_file)
      append_value(args, "--display-language", @config.display_language)
      append_value(args, "--mcp-config", @config.mcp_config)
      append_value(args, "--agents", @config.agents)
      append_value(args, "--plugin-dir", @config.plugin_dir)
    end

    def build_environment
      env = clean_subprocess_environment.merge("AUTOHAND_STREAM_TOOL_OUTPUT" => "1")
      if @config.provider == "autohandai"
        env["AUTOHAND_AI_PLAN"] = @config.autohand_ai_plan || "cloud"
        env["AUTOHAND_AI_API_KEY"] = @config.api_key if @config.api_key
        env["AUTOHAND_AI_BASE_URL"] = @config.base_url if @config.base_url
      end
      env.merge(@config.env_vars)
    end

    def clean_subprocess_environment
      base_env = if defined?(::Bundler) && ::Bundler.respond_to?(:unbundled_env)
                   ::Bundler.unbundled_env
                 else
                   ENV.to_h
                 end

      base_env.reject do |key, _value|
        key.start_with?("BUNDLE_") || %w[RUBYOPT RUBYLIB GEM_HOME GEM_PATH].include?(key)
      end
    end

    def append_context_compact(args)
      case @config.context_compact
      when true then args << "--context-compact"
      when false then args << "--no-context-compact"
      end
    end

    def startup_permission_mode?
      @config.permission_mode && @config.permission_mode != "plan"
    end

    def append_flag(args, flag, enabled)
      args << flag if enabled
    end

    def append_value(args, flag, value)
      return if value.nil?

      args << flag << value.to_s
    end

    def normalized_skill_sources
      @normalized_skill_sources ||= @config.skill_sources.filter_map do |source|
        case source
        when Hash
          normalized = Utils.normalize_hash(source)
          normalized[:name] || normalized[:path] || normalized[:url]
        else
          source
        end
      end.map(&:to_s)
    end

    def cli_binary
      AutohandSDK::CLIInstaller.detect!(
        explicit_path: @config.cli_path,
        path: @config.env_vars.fetch("PATH", ENV.fetch("PATH", nil))
      )
    end

    def copy_skill_files
      skills_dir = File.join(Dir.home, ".autohand", "skills")
      skill_files = (@config.skill_files + @config.skills).select { |skill| skill_file_reference?(skill) }

      skill_files.each do |skill|
        raw_path = File.expand_path(skill.to_s, @config.cwd)
        next unless File.file?(raw_path)

        name = skill_name_for_path(skill.to_s)
        destination = File.join(skills_dir, name, "SKILL.md")
        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp(raw_path, destination)
      end
    end

    def skill_file_reference?(skill)
      value = skill.to_s
      value.include?("/") || value.include?("\\") || value.match?(/\.md\z/i)
    end

    def skill_name_for_path(path)
      parts = path.split(%r{[/\\]}).reject { |part| part.empty? || part == "." || part == ".." }
      name = parts.last || "custom-skill"
      name = parts[-2] if name.casecmp("SKILL.md").zero? && parts.length > 1
      name.sub(/\.md\z/i, "")
    end

    def read_stdout(generation)
      error = nil
      generation.stdout.each_line do |line|
        break if generation.stopping

        handle_stdout_line(line)
      end
    rescue IOError
      error = TransportError.new("CLI stdout closed")
    rescue StandardError => e
      error = TransportError.new("Failed reading CLI stdout: #{e.message}")
    ensure
      unless generation.stopping
        handle_unexpected_termination(
          generation,
          error || TransportError.new("CLI stdout closed")
        )
      end
    end

    def handle_stdout_line(line)
      message = JSON.parse(line)
      if message.is_a?(Array)
        message.each { |item| handle_rpc_message(item) if item.is_a?(Hash) }
      elsif message.is_a?(Hash)
        handle_rpc_message(message)
      end
    rescue JSON::ParserError
      @config.logger.debug("Ignoring non-JSON RPC stdout line: #{line.inspect}") if @config.debug
    end

    def handle_rpc_message(message)
      if message.key?("id")
        waiter_for(message["id"])&.resolve(message)
        return
      end

      method = message["method"]
      return unless method.is_a?(String)

      raw_params = message["params"]
      params = raw_params.is_a?(Hash) ? raw_params.dup : { "value" => raw_params }
      params.instance_variable_set(:@autohand_raw_params, raw_params)
      params["_method"] = method
      callbacks_for(method).each { |callback| safely_call_notification(callback, params) }
    end

    def waiter_for(request_id)
      @pending_mutex.synchronize { @pending[request_id] }
    end

    def callbacks_for(method)
      @callbacks_mutex.synchronize do
        @notification_callbacks[method].dup + @notification_callbacks["*"].dup
      end
    end

    def safely_call_notification(callback, params)
      callback.call(params)
    rescue StandardError => e
      @config.logger.error("Unhandled notification callback error: #{e.class}: #{e.message}")
    end

    def read_stderr(generation)
      generation.stderr.each_line do |line|
        break if generation.stopping

        text = line.to_s.strip
        next if text.empty?

        @stderr_mutex.synchronize do
          @stderr_lines << text
          @stderr_lines = @stderr_lines.last(50)
          @stderr_tail = @stderr_lines.join("\n")
        end
        @config.logger.debug("[CLI stderr] #{text}") if @config.debug
      end
    rescue IOError
      nil
    end

    def raise_rpc_error(method, response)
      error = response["error"] || {}
      message = error["message"] || "RPC request failed: #{method}"
      raise RPCError.new(message, code: error["code"], data: error["data"])
    end

    def fail_pending_requests(error)
      waiters = @pending_mutex.synchronize do
        @pending.values.tap { @pending.clear }
      end
      waiters.each { |waiter| waiter.reject(error) }
    end

    def terminate_process(generation)
      return unless generation.wait_thread&.alive?

      Process.kill("TERM", generation.wait_thread.pid)
      return if generation.wait_thread.join(PROCESS_STOP_TIMEOUT)

      Process.kill("KILL", generation.wait_thread.pid)
      generation.wait_thread.join(PROCESS_STOP_TIMEOUT)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end

    def close_io(io)
      io&.close unless io&.closed?
    rescue IOError, SystemCallError
      nil
    end

    def format_stderr_tail
      tail = stderr_tail
      tail.empty? ? "" : ":\n#{tail}"
    end
  end
  # rubocop:enable Metrics/ClassLength
end
