# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "shellwords"

require_relative "configuration"
require_relative "errors"

module AutohandSDK
  class Transport
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
          @resolved = true
          @value = value
          @condition.broadcast
        end
      end

      def reject(error)
        @mutex.synchronize do
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

    attr_reader :stderr_tail

    def initialize(config = nil, **)
      @config = Configuration.from(config, **)
      @request_id = 0
      @pending = {}
      @pending_mutex = Mutex.new
      @notification_callbacks = Hash.new { |hash, key| hash[key] = [] }
      @stderr_lines = []
      @stderr_tail = ""
      @running = false
    end

    def start
      return if running?

      copy_skill_files if @config.copy_skill_files && (@config.skills.any? || @config.skill_files.any?)

      env = build_environment
      args = build_args
      @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(env, *args, chdir: @config.cwd)
      @stdin.sync = true
      @running = true

      @stdout_thread = Thread.new { read_stdout }
      @stderr_thread = Thread.new { read_stderr }
      sleep 0.05

      return if running?

      code = @wait_thread&.value&.exitstatus
      stop
      raise TransportError, "CLI process exited during startup with code #{code}#{format_stderr_tail}"
    end

    def stop
      return unless @wait_thread || @stdin || @stdout || @stderr

      @running = false
      close_io(@stdin)
      close_io(@stdout)
      close_io(@stderr)
      terminate_process

      @stdout_thread&.kill
      @stderr_thread&.kill
      @stdin = @stdout = @stderr = @wait_thread = nil
      @stdout_thread = @stderr_thread = nil
      fail_pending_requests(TransportError.new("Transport stopped before receiving a response"))
    end

    def request(method, params = {})
      raise TransportNotStartedError, "Transport not started" unless running? && @stdin

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
        @stdin.write("#{JSON.generate(payload)}\n")
        @stdin.flush
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

      callbacks = @notification_callbacks[method]
      callbacks << block
      -> { callbacks.delete(block) }
    end

    def running?
      @running && @wait_thread&.alive?
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

    def build_args
      args = [cli_binary, "--mode", "rpc"]
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
      ENV.to_h.tap do |env|
        ENV.each_key do |key|
          env[key] = nil if key.start_with?("BUNDLE_") || %w[RUBYOPT RUBYLIB GEM_HOME GEM_PATH].include?(key)
        end
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
      return @config.cli_path if @config.cli_path

      binary_name = platform_binary_name
      package_binary = File.expand_path("../../cli/#{binary_name}", __dir__)
      return package_binary if File.exist?(package_binary)

      find_executable("autohand") || find_executable(binary_name) || binary_name
    end

    def platform_binary_name
      os = RbConfig::CONFIG.fetch("host_os").downcase
      cpu = RbConfig::CONFIG.fetch("host_cpu").downcase

      case os
      when /darwin/
        cpu.include?("arm") || cpu.include?("aarch64") ? "autohand-macos-arm64" : "autohand-macos-x64"
      when /linux/
        cpu.include?("arm") || cpu.include?("aarch64") ? "autohand-linux-arm64" : "autohand-linux-x64"
      when /mswin|mingw|cygwin/
        "autohand-windows-x64.exe"
      else
        raise ConfigurationError, "Unsupported platform: #{os}/#{cpu}"
      end
    end

    def find_executable(name)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
        path = File.join(directory, name)
        return path if File.executable?(path) && !File.directory?(path)
      end
      nil
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

    def read_stdout
      @stdout.each_line do |line|
        break unless @running

        handle_stdout_line(line)
      end
    rescue IOError
      fail_pending_requests(TransportError.new("CLI stdout closed"))
    rescue StandardError => e
      fail_pending_requests(TransportError.new("Failed reading CLI stdout: #{e.message}"))
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

      params = message["params"]
      params = params.is_a?(Hash) ? params.dup : { "value" => params }
      params["_method"] = method
      callbacks_for(method).each { |callback| safely_call_notification(callback, params) }
    end

    def waiter_for(request_id)
      @pending_mutex.synchronize { @pending[request_id] }
    end

    def callbacks_for(method)
      @notification_callbacks[method] + @notification_callbacks["*"]
    end

    def safely_call_notification(callback, params)
      callback.call(params)
    rescue StandardError => e
      @config.logger.error("Unhandled notification callback error: #{e.class}: #{e.message}")
    end

    def read_stderr
      @stderr.each_line do |line|
        text = line.to_s.strip
        next if text.empty?

        @stderr_lines << text
        @stderr_lines = @stderr_lines.last(50)
        @stderr_tail = @stderr_lines.join("\n")
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

    def terminate_process
      return unless @wait_thread&.alive?

      Process.kill("TERM", @wait_thread.pid)
      return if @wait_thread.join(5)

      Process.kill("KILL", @wait_thread.pid)
      @wait_thread.join
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end

    def close_io(io)
      io&.close unless io&.closed?
    rescue IOError
      nil
    end

    def format_stderr_tail
      @stderr_tail.empty? ? "" : ":\n#{@stderr_tail}"
    end
  end
end
