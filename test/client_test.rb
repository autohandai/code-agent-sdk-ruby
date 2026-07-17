# frozen_string_literal: true

require_relative "test_helper"

class ClientTest < SDKTestCase
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
end
