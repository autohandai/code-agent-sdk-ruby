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
    assert_equal(%w[model permissions], sdk.supported_commands)
  ensure
    sdk&.close
  end

  def test_hook_event_constants_match_cli_names
    assert_equal("post-response", AutohandSDK::HookEvents::POST_RESPONSE)
    assert_equal("teammate-spawned", AutohandSDK::HookEvents::TEAMMATE_SPAWNED)
    assert_equal("context:critical", AutohandSDK::HookEvents::CONTEXT_CRITICAL)
    assert_includes(AutohandSDK::HookEvents::ALL, "automode:checkpoint")
  end
end
