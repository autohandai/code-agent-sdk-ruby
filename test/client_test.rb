# frozen_string_literal: true

require_relative "test_helper"

class ClientTest < SDKTestCase
  class ContractTransport
    attr_reader :requests

    def initialize(result)
      @result = result
      @requests = []
      @running = false
    end

    def on_notification(*) = nil
    def on_termination = nil

    def start
      @running = true
      self
    end

    def stop
      @running = false
      self
    end

    def running? = @running

    def request(method, params)
      @requests << [method, params]
      @result
    end
  end

  class RunProbeClient
    def initialize
      @release = Queue.new
      @abort_calls = 0
      @mutex = Mutex.new
    end

    def stream_prompt(_params)
      Enumerator.new do |yielder|
        completed = false
        begin
          yielder << { "type" => "turn_start", "turn_id" => "probe-turn" }
          @release.pop
          yielder << { "type" => "message_update", "delta" => "done" }
          yielder << { "type" => "agent_end", "reason" => "completed" }
          completed = true
        ensure
          @mutex.synchronize { @abort_calls += 1 } unless completed
        end
      end
    end

    def release
      @release << true
    end

    def abort_calls
      @mutex.synchronize { @abort_calls }
    end

    alias close release
  end

  def test_stream_prompt_yields_normalized_events
    sdk = client
    sdk.start
    events = sdk.stream_prompt("Say hello").to_a

    assert_includes(events.map { |event| event["type"] }, "message_update")
    assert_includes(events.map { |event| event["type"] }, "agent_end")
    assert_equal("msg_1", events.find { |event| event["type"] == "message_update" }["message_id"])
  ensure
    sdk&.close
  end

  def test_agent_run_collects_final_text
    agent = AutohandSDK::Agent.create(cli_path: @cli_path, timeout: 2_000)
    result = agent.run("Say hello")

    assert_equal("completed", result.fetch(:status))
    assert_equal("Hello Ruby", result.fetch(:text))
    assert(result.fetch(:events).any? { |event| event["type"] == "message_end" })
  ensure
    agent&.close
  end

  def test_run_stream_abandonment_unwinds_and_joins_the_prompt_pump
    probe = RunProbeClient.new
    run = AutohandSDK::Run.new(probe, { "message" => "hello" })

    event = run.stream.first
    pump = run.instance_variable_get(:@thread)

    assert_equal("turn_start", event.fetch("type"))
    assert_equal(1, probe.abort_calls)
    refute_predicate(pump, :alive?)
    assert_equal("aborted", run.wait.fetch(:status))
  ensure
    probe&.release
    pump&.kill if pump&.alive?
  end

  def test_one_stream_can_leave_while_another_consumer_finishes_the_run
    probe = RunProbeClient.new
    run = AutohandSDK::Run.new(probe, { "message" => "hello" })
    events = nil
    remaining_consumer = Thread.new { events = run.stream.to_a }
    wait_until { run.instance_variable_get(:@active_streams) == 1 }

    assert_equal("turn_start", run.stream.first.fetch("type"))
    assert_equal(0, probe.abort_calls)

    probe.release

    assert(remaining_consumer.join(1), "remaining stream consumer did not settle")
    assert_includes(events.map { |event| event["type"] }, "agent_end")
    assert_equal("done", run.wait.fetch(:text))
    assert_equal(0, probe.abort_calls)
  ensure
    probe&.release
    remaining_consumer&.kill
    pump = run&.instance_variable_get(:@thread)
    pump&.kill if pump&.alive?
  end

  def test_stream_abandonment_does_not_cancel_an_active_waiter
    probe = RunProbeClient.new
    run = AutohandSDK::Run.new(probe, { "message" => "hello" })
    result = nil
    waiter = Thread.new { result = run.wait }
    wait_until { run.instance_variable_get(:@waiters) == 1 }

    assert_equal("turn_start", run.stream.first.fetch("type"))
    assert_equal(0, probe.abort_calls)

    probe.release

    assert(waiter.join(1), "run waiter did not settle")
    assert_equal("done", result.fetch(:text))
    assert_equal(0, probe.abort_calls)
  ensure
    probe&.release
    waiter&.kill
    pump = run&.instance_variable_get(:@thread)
    pump&.kill if pump&.alive?
  end

  def test_permission_helpers_use_scoped_decisions
    sdk = client
    sdk.start

    result = sdk.allow_permission("req_1", scope: :session)

    assert_equal("req_1", result.fetch("received").fetch("requestId"))
    assert_equal("allow_session", result.fetch("received").fetch("decision"))
  ensure
    sdk&.close
  end

  def test_supported_models_and_commands_unwrap_cli_results
    sdk = client
    sdk.start

    assert_equal([{ "id" => "test-model" }], sdk.supported_models)
    assert_equal(%w[/model /permissions /autoresearch], sdk.supported_commands)
    assert(sdk.supports_command?("/autoresearch"))
  ensure
    sdk&.close
  end

  def test_reset_uses_exact_wire_contract_and_decodes_result
    sdk, transport = contract_client("sessionId" => "session-new")

    result = sdk.reset

    assert_equal([["autohand.reset", {}]], transport.requests)
    assert_instance_of(AutohandSDK::ResetResult, result)
    assert_equal("session-new", result.session_id)
    assert_respond_to(AutohandSDK::Agent.from_client(sdk), :reset)
  ensure
    sdk&.close
  end

  def test_create_browser_handoff_uses_exact_wire_contract_and_decodes_result
    wire_result = {
      "token" => "token-1",
      "sessionId" => "session-1",
      "workspaceRoot" => "/workspace",
      "createdAt" => "2026-07-20T00:00:00.000Z",
      "expiresAt" => "2026-07-20T00:10:00.000Z",
      "url" => "chrome-extension://ext/sidepanel.html?handoff=token-1"
    }
    sdk, transport = contract_client(wire_result)

    result = sdk.create_browser_handoff(extension_id: "ext", install_url: "https://install.test")

    assert_equal(
      [["autohand.browserHandoff.create", { "extensionId" => "ext", "installUrl" => "https://install.test" }]],
      transport.requests
    )
    assert_instance_of(AutohandSDK::BrowserHandoffCreateResult, result)
    assert_equal("/workspace", result.workspace_root)
    assert_respond_to(AutohandSDK::Agent.from_client(sdk), :create_browser_handoff)
  ensure
    sdk&.close
  end

  def test_attach_browser_handoff_uses_exact_wire_contract_and_decodes_result
    wire_result = {
      "success" => true,
      "sessionId" => "session-1",
      "workspaceRoot" => "/workspace",
      "messageCount" => 12
    }
    sdk, transport = contract_client(wire_result)

    result = sdk.attach_browser_handoff("token-1")

    assert_equal([["autohand.browserHandoff.attach", { "token" => "token-1" }]], transport.requests)
    assert_instance_of(AutohandSDK::BrowserHandoffAttachResult, result)
    assert_predicate(result, :success?)
    assert_equal(12, result.message_count)
    assert_respond_to(AutohandSDK::Agent.from_client(sdk), :attach_browser_handoff)
  ensure
    sdk&.close
  end

  def test_attach_latest_browser_handoff_uses_exact_wire_contract_and_decodes_result
    sdk, transport = contract_client("success" => false)

    result = sdk.attach_latest_browser_handoff

    assert_equal([["autohand.browserHandoff.attachLatest", {}]], transport.requests)
    assert_instance_of(AutohandSDK::BrowserHandoffAttachResult, result)
    refute_predicate(result, :success?)
    assert_nil(result.session_id)
    assert_respond_to(AutohandSDK::Agent.from_client(sdk), :attach_latest_browser_handoff)
  ensure
    sdk&.close
  end

  def test_start_automode_uses_exact_wire_contract_and_decodes_result
    sdk, transport = contract_client("success" => true, "sessionId" => "auto-1")

    result = sdk.start_automode(
      "Ship the release",
      max_iterations: 20,
      completion_promise: "DONE",
      use_worktree: false,
      checkpoint_interval: 5,
      max_runtime: 60,
      max_cost: 2.5
    )

    assert_equal(
      [[
        "autohand.automode.start",
        {
          "prompt" => "Ship the release",
          "maxIterations" => 20,
          "completionPromise" => "DONE",
          "useWorktree" => false,
          "checkpointInterval" => 5,
          "maxRuntime" => 60,
          "maxCost" => 2.5
        }
      ]],
      transport.requests
    )
    assert_instance_of(AutohandSDK::AutomodeStartResult, result)
    assert_equal("auto-1", result.session_id)
    assert_respond_to(AutohandSDK::Agent.from_client(sdk), :start_automode)
  ensure
    sdk&.close
  end

  def test_routes_goal_and_replayable_autoresearch_methods_to_exact_rpc_names
    sdk = client
    sdk.start

    created = sdk.create_goal(objective: "Finish parity", token_budget: 20_000)
    goal = sdk.get_goal
    updated = sdk.update_goal(status: "paused")
    cleared = sdk.clear_goal
    queued = sdk.queue_goal(objective: "Next goal")
    queue_started = sdk.start_queued_goal
    templates = sdk.list_goal_templates
    started = sdk.start_autoresearch(
      objective: "Reduce test runtime",
      metric_name: "total_ms",
      max_iterations: 12,
      secondary_objectives: [{ name: "memory", unit: "mb", direction: "lower" }],
      subagents: { idea_generation: true }
    )
    replayed = sdk.replay_autoresearch(attempt_id: "attempt-1", evaluator: "current")
    history = sdk.get_autoresearch_history
    rescored = sdk.rescore_autoresearch(all: true)
    compared = sdk.compare_autoresearch(left_attempt_id: "attempt-1", right_attempt_id: "attempt-2")
    pareto = sdk.get_autoresearch_pareto
    pinned = sdk.pin_autoresearch(attempt_id: "attempt-1", pinned: true)
    pruned = sdk.prune_autoresearch(dry_run: true)
    stopped = sdk.stop_autoresearch

    assert_equal("autohand.goal.create", created.fetch("method"))
    assert_equal({ "objective" => "Finish parity", "token_budget" => 20_000 }, created.fetch("params"))
    assert_equal("autohand.goal.get", goal.fetch("method"))
    assert_equal("paused", updated.dig("params", "status"))
    assert_equal("autohand.goal.clear", cleared.fetch("method"))
    assert_equal("autohand.goal.queue", queued.fetch("method"))
    assert_equal("autohand.goal.startQueued", queue_started.fetch("method"))
    assert_equal("autohand.goal.listTemplates", templates.fetch("method"))
    assert_equal("autohand.autoresearch.start", started.fetch("method"))
    assert_equal("total_ms", started.dig("params", "metricName"))
    assert(started.dig("params", "subagents", "ideaGeneration"))
    assert_equal("attempt-1", replayed.dig("params", "attemptId"))
    assert_equal("autohand.autoresearch.history", history.fetch("method"))
    assert(rescored.dig("params", "all"))
    assert_equal("autohand.autoresearch.compare", compared.fetch("method"))
    assert_equal("autohand.autoresearch.pareto", pareto.fetch("method"))
    assert(pinned.dig("params", "pinned"))
    assert(pruned.dig("params", "dryRun"))
    assert_equal("autohand.autoresearch.stop", stopped.fetch("method"))
  ensure
    sdk&.close
  end

  def test_autoresearch_notifications_are_normalized_events
    sdk = client
    sdk.start

    sdk.get_autoresearch_status
    event = sdk.instance_variable_get(:@rpc_client).events.first

    assert_equal("autoresearch", event.fetch("type"))
    assert_equal("status", event.fetch("phase"))
    assert_equal(12, event.fetch("max_iterations"))
    assert_equal(3, event.fetch("runs_logged"))
  ensure
    sdk&.close
  end

  def test_autoresearch_operation_notifications_are_normalized_events
    sdk = client
    sdk.start

    sdk.replay_autoresearch(attempt_id: "attempt-1", evaluator: "current")
    event = sdk.instance_variable_get(:@rpc_client).events.first

    assert_equal("autoresearch", event.fetch("type"))
    assert_equal("replay", event.fetch("operation"))
    assert_equal("complete", event.fetch("phase"))
    assert(event.fetch("success"))
    assert_equal("attempt-1", event.fetch("attempt_id"))
  ensure
    sdk&.close
  end

  def test_agent_command_helpers_use_the_streamed_run_lifecycle
    agent = AutohandSDK::Agent.create(cli_path: @cli_path, timeout: 2_000)

    result = agent.deep_research("Ruby RPC reliability").wait

    assert_equal("Hello Ruby", result.fetch(:text))
    assert_raises(ArgumentError) { agent.command("deep-research", "invalid") }
  ensure
    agent&.close
  end

  def test_feature_settings_use_cli_camel_case
    sdk = client
    sdk.start

    result = sdk.apply_flag_settings(features: { slash_goal: true, token_usage_status: true })

    assert(result.dig("params", "settings", "features", "slashGoal"))
    assert(result.dig("params", "settings", "features", "tokenUsageStatus"))
  ensure
    sdk&.close
  end

  def test_hook_event_constants_match_cli_names
    assert_equal("post-response", AutohandSDK::HookEvents::POST_RESPONSE)
    assert_equal("teammate-spawned", AutohandSDK::HookEvents::TEAMMATE_SPAWNED)
    assert_equal("context:critical", AutohandSDK::HookEvents::CONTEXT_CRITICAL)
    assert_includes(AutohandSDK::HookEvents::ALL, "automode:checkpoint")
    assert_includes(AutohandSDK::HookEvents::ALL, "autoresearch:run")
    assert_includes(AutohandSDK::HookEvents::ALL, "goal-written:completed")
  end

  private

  def wait_until
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1
    until yield
      raise "condition not reached" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      Thread.pass
    end
  end

  def contract_client(result)
    transport = ContractTransport.new(result)
    rpc_client = AutohandSDK::RPCClient.new({ startup_check: false }, transport: transport)
    [AutohandSDK::Client.new({ startup_check: false }, rpc_client: rpc_client), transport]
  end
end
