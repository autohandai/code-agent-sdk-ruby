# frozen_string_literal: true

require "open3"

require_relative "test_helper"
require_relative "../lib/autohand_sdk/event_queue"

# Inline subprocess fixtures keep lifecycle regressions self-contained.
# rubocop:disable Metrics/ClassLength
class DiscoveryAndRegressionsTest < SDKTestCase
  class RecordingTransport
    attr_reader :requests

    def initialize
      @requests = []
    end

    def on_notification(*)
      -> {}
    end

    def request(method, params)
      @requests << [method, params]
      { "success" => true }
    end

    def running?
      true
    end

    def start; end

    def stop; end
  end

  class FailingRPCClient
    attr_reader :stop_calls

    def initialize
      @stop_calls = 0
    end

    def start; end

    def set_plan_mode(*)
      raise "apply failed"
    end

    def stop
      @stop_calls += 1
    end
  end

  def test_discovery_rpc_methods_preserve_exact_wire_contract
    transport = RecordingTransport.new
    rpc = AutohandSDK::RPCClient.new({ startup_check: false }, transport: transport)

    rpc.get_skills_registry
    rpc.get_skills_registry(force_refresh: false)
    rpc.install_skill("typescript", scope: "project", force: true)
    rpc.list_mcp_servers
    rpc.list_mcp_tools
    rpc.list_mcp_tools(server_name: "github")
    rpc.get_mcp_server_configs

    assert_equal(
      [
        ["autohand.getSkillsRegistry", {}],
        ["autohand.getSkillsRegistry", { "forceRefresh" => false }],
        ["autohand.installSkill", { "skillName" => "typescript", "scope" => "project", "force" => true }],
        ["autohand.mcp.listServers", {}],
        ["autohand.mcp.listTools", {}],
        ["autohand.mcp.listTools", { "serverName" => "github" }],
        ["autohand.mcp.getServerConfigs", {}]
      ],
      transport.requests
    )
  end

  def test_public_discovery_methods_return_immutable_typed_values
    sdk = client
    sdk.start

    registry = sdk.get_skills_registry(force_refresh: false)
    installed = sdk.install_skill("typescript", scope: :project)
    failed = sdk.install_skill("existing", scope: :user)
    servers = sdk.list_mcp_servers
    tools = sdk.list_mcp_tools(server_name: "github")
    configs = sdk.get_mcp_server_configs

    assert_instance_of(AutohandSDK::SkillsRegistryResult, registry)
    assert_equal(42, registry.skills.first.download_count)
    assert_predicate(registry.skills.first, :curated?)
    assert_predicate(installed, :success?)
    assert_equal("typescript", installed.skill_name)
    refute_predicate(failed, :success?)
    assert_equal("already installed", failed.error)
    assert_equal(3, servers.servers.first.tool_count)
    assert_equal("github", tools.tools.first.server_name)
    assert_equal("http", configs.configs.first.transport)
    assert_predicate(configs.configs.first, :auto_connect?)
    assert_predicate(registry, :frozen?)
    assert_predicate(registry.skills, :frozen?)
  ensure
    sdk&.close
  end

  def test_install_skill_rejects_unknown_scope_before_rpc
    sdk = client

    error = assert_raises(ArgumentError) { sdk.install_skill("typescript", scope: :global) }

    assert_match(/user, project/, error.message)
  ensure
    sdk&.close
  end

  def test_failed_post_start_configuration_rolls_back_client
    rpc = FailingRPCClient.new
    sdk = AutohandSDK::Client.new({ plan_mode: true }, rpc_client: rpc)

    error = assert_raises(RuntimeError) { sdk.start }

    assert_equal("apply failed", error.message)
    refute_predicate(sdk, :started?)
    assert_equal(1, rpc.stop_calls)
  end

  def test_event_queues_are_bounded_and_keep_the_newest_events
    queue = AutohandSDK::EventQueue.new(limit: 3)

    5.times { |index| queue.push(index) }

    assert_equal(3, queue.size)
    assert_equal([2, 3, 4], queue.drain)
  end

  def test_transport_waiters_keep_the_first_terminal_result
    waiter = AutohandSDK::Transport::Waiter.new
    waiter.resolve("response")
    waiter.reject(AutohandSDK::TransportError.new("late EOF"))

    assert_equal("response", waiter.wait(timeout: 0.01, message: "timed out"))
  end

  def test_clean_stdout_eof_terminates_live_child_closes_streams_and_restarts
    with_cli_script(eof_cli_script) do |cli_path|
      sdk = AutohandSDK::Client.new(cli_path: cli_path, startup_check: false, timeout: 2_000)
      sdk.start
      rpc = sdk.instance_variable_get(:@rpc_client)
      old_pid = rpc.request("test.pid").fetch("pid")
      reader = Thread.new { rpc.events.first }
      wait_for { rpc.instance_variable_get(:@event_subscribers).length == 1 }

      error = assert_raises(AutohandSDK::TransportError) { rpc.request("test.close_stdout") }

      assert_match(/CLI stdout closed/, error.message)
      refute_predicate(sdk, :started?)

      sdk.start

      assert(reader.join(3), "event reader remained blocked across transport restart")
      assert_predicate(sdk, :started?)
      assert_equal("idle", sdk.get_state.fetch("status"))
      refute_equal(old_pid, rpc.request("test.pid").fetch("pid"))
      assert_raises(Errno::ESRCH) { Process.kill(0, old_pid) }
    ensure
      reader&.kill
      sdk&.stop
    end
  end

  def test_client_and_transport_serialize_concurrent_starts_and_requests_across_restarts
    with_cli_script(counting_cli_script) do |cli_path, directory|
      pid_log = File.join(directory, "pids.log")
      sdk = AutohandSDK::Client.new(
        cli_path: cli_path,
        startup_check: false,
        timeout: 2_000,
        env_vars: { "AUTOHAND_TEST_PID_LOG" => pid_log }
      )

      starts = 8.times.map { Thread.new { sdk.start } }
      starts.each(&:join)
      results = 12.times.map do
        Thread.new { sdk.get_state.fetch("status") }
      end.map(&:value)

      assert_equal(["idle"], results.uniq)
      assert_equal(1, File.readlines(pid_log).length)

      sdk.stop
      sdk.start

      assert_equal("idle", sdk.get_state.fetch("status"))
      assert_equal(2, File.readlines(pid_log).length)
    ensure
      starts&.each { |thread| thread.kill if thread.alive? }
      sdk&.stop
    end
  end

  def test_ack_first_prompt_waits_for_terminal_and_drains_abandoned_generation
    with_cli_script(ack_first_cli_script) do |cli_path|
      rpc = AutohandSDK::RPCClient.new(cli_path: cli_path, startup_check: true, timeout: 2_000)
      rpc.start

      first_event = rpc.stream_prompt("message" => "first").first
      second_events = rpc.stream_prompt("message" => "second").to_a

      assert_equal("turn_start", first_event.fetch("type"))
      assert_includes(second_events.map { |event| event["type"] }, "agent_end")
      assert_equal(["second"], second_events.filter_map { |event| event["delta"] })
      refute_includes(second_events.filter_map { |event| event["delta"] }, "drained-first")

      assert_raises(AutohandSDK::RPCError) do
        rpc.stream_prompt("message" => "reject").to_a
      end
      assert_equal("idle", rpc.get_state.fetch("status"))
    ensure
      rpc&.stop
    end
  end

  def test_agent_stream_abandonment_aborts_drains_and_leaves_no_pump_thread
    with_cli_script(ack_first_cli_script) do |cli_path, directory|
      abort_log = File.join(directory, "aborts.log")
      agent = AutohandSDK::Agent.create(
        cli_path: cli_path,
        startup_check: true,
        timeout: 2_000,
        env_vars: { "AUTOHAND_TEST_ABORT_LOG" => abort_log }
      )

      first_event = agent.stream("first").first
      result = agent.run("second")

      assert_equal("turn_start", first_event.fetch("type"))
      assert_equal(["abort"], File.readlines(abort_log, chomp: true))
      assert_equal("second", result.fetch(:text))
      refute_includes(result.fetch(:events).filter_map { |event| event["delta"] }, "drained-first")
      refute(Thread.list.any? { |thread| thread.name&.start_with?(AutohandSDK::Run::PUMP_THREAD_PREFIX) })
    ensure
      agent&.close
    end
  end

  def test_railtie_autoload_is_scoped_to_autohand_sdk
    ruby = <<~RUBY
      module Rails
        class Railtie
          def self.initializer(*) = nil
        end

        def self.logger = nil
      end

      require "autohand_sdk"
      abort "wrong Railtie" unless AutohandSDK::Railtie < Rails::Railtie
      abort "leaked Object::Railtie" if Object.const_defined?(:Railtie, false)
    RUBY
    root = File.expand_path("..", __dir__)

    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I#{File.join(root, "lib")}", "-e", ruby)

    assert_predicate(status, :success?, stderr)
  end

  def test_prompt_and_global_event_consumers_receive_independent_copies
    rpc = AutohandSDK::RPCClient.new(cli_path: @cli_path, startup_check: false)
    request_started = Queue.new
    request_thread = nil
    global_event = nil
    global_reader = Thread.new { global_event = rpc.events.first }
    wait_for { rpc.instance_variable_get(:@event_subscribers).length == 1 }

    blocking_prompt = lambda do |_params|
      request_thread = Thread.current
      request_started << true
      sleep
    end
    notifier = Thread.new do
      request_started.pop
      rpc.send(
        :handle_notification,
        "_method" => "autohand.permissionRequest",
        "requestId" => "permission-1"
      )
    end

    prompt_event = rpc.stub(:prompt, blocking_prompt) do
      rpc.stream_prompt("message" => "hello").first
    end
    notifier.join
    global_reader.join

    assert_equal("permission-1", prompt_event.fetch("request_id"))
    assert_equal("permission-1", global_event.fetch("request_id"))
    refute_predicate(request_thread, :alive?, "prompt request worker leaked after early stream termination")
  ensure
    notifier&.kill
    global_reader&.kill
    request_thread&.kill
  end

  def test_stopping_rpc_client_wakes_blocked_event_stream
    rpc = AutohandSDK::RPCClient.new(cli_path: @cli_path, startup_check: false)
    reader = Thread.new { rpc.events.first }
    wait_for { rpc.instance_variable_get(:@event_subscribers).length == 1 }

    rpc.stop

    assert(reader.join(0.2), "event reader remained blocked after stop")
  ensure
    reader&.kill
  end

  private

  def wait_for(timeout: 1)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      raise "condition not reached" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      Thread.pass
    end
  end

  def with_cli_script(source)
    directory = Dir.mktmpdir("autohand-sdk-lifecycle-cli")
    path = File.join(directory, "autohand")
    File.write(path, source)
    FileUtils.chmod("+x", path)
    yield path, directory
  ensure
    FileUtils.remove_entry(directory) if directory && Dir.exist?(directory)
  end

  def eof_cli_script
    <<~RUBY
      #!/usr/bin/env ruby
      # frozen_string_literal: true

      require "json"

      $stdout.sync = true
      Signal.trap("TERM", "IGNORE")

      STDIN.each_line do |line|
        request = JSON.parse(line)
        case request.fetch("method")
        when "test.close_stdout"
          STDOUT.reopen(File::NULL)
          sleep 30
        when "test.pid"
          puts JSON.generate(jsonrpc: "2.0", id: request.fetch("id"), result: { pid: Process.pid })
        when "autohand.getState"
          puts JSON.generate(jsonrpc: "2.0", id: request.fetch("id"), result: { status: "idle" })
        end
      end
    RUBY
  end

  def counting_cli_script
    <<~RUBY
      #!/usr/bin/env ruby
      # frozen_string_literal: true

      require "json"

      $stdout.sync = true
      File.open(ENV.fetch("AUTOHAND_TEST_PID_LOG"), "a") { |file| file.puts(Process.pid) }

      STDIN.each_line do |line|
        request = JSON.parse(line)
        next unless request.fetch("method") == "autohand.getState"

        puts JSON.generate(jsonrpc: "2.0", id: request.fetch("id"), result: { status: "idle" })
      end
    RUBY
  end

  def ack_first_cli_script
    <<~'RUBY'
      #!/usr/bin/env ruby
      # frozen_string_literal: true

      require "json"

      $stdout.sync = true
      output_mutex = Mutex.new
      emit = lambda do |message|
        output_mutex.synchronize { puts JSON.generate(message) }
      end
      prompt_number = 0
      prompt_thread = nil

      STDIN.each_line do |line|
        request = JSON.parse(line)
        id = request.fetch("id")
        case request.fetch("method")
        when "autohand.getState"
          emit.call(jsonrpc: "2.0", id: id, result: { status: "idle" })
        when "autohand.prompt"
          if request.dig("params", "message") == "reject"
            emit.call(
              jsonrpc: "2.0",
              id: id,
              error: { code: -32_602, message: "rejected prompt" }
            )
            next
          end

          prompt_number += 1
          current_prompt = prompt_number
          emit.call(jsonrpc: "2.0", id: id, result: { success: true })
          prompt_thread = Thread.new do
            sleep 0.03
            emit.call(
              jsonrpc: "2.0",
              method: "autohand.turnStart",
              params: { turnId: "turn_#{current_prompt}" }
            )
            sleep 0.15
            emit.call(
              jsonrpc: "2.0",
              method: "autohand.messageUpdate",
              params: { messageId: "message_#{current_prompt}", delta: current_prompt == 1 ? "first" : "second" }
            )
            emit.call(
              jsonrpc: "2.0",
              method: "autohand.turnEnd",
              params: { turnId: "turn_#{current_prompt}" }
            )
          end
        when "autohand.abort"
          prompt_thread&.kill
          prompt_thread&.join
          abort_log = ENV["AUTOHAND_TEST_ABORT_LOG"]
          File.open(abort_log, "a") { |file| file.puts("abort") } if abort_log
          emit.call(
            jsonrpc: "2.0",
            method: "autohand.messageUpdate",
            params: { messageId: "message_1", delta: "drained-first" }
          )
          emit.call(jsonrpc: "2.0", id: id, result: { success: true })
          emit.call(jsonrpc: "2.0", method: "autohand.turnEnd", params: { turnId: "turn_1" })
        end
      end
    RUBY
  end
end
# rubocop:enable Metrics/ClassLength
