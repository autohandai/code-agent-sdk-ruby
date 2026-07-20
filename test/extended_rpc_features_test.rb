# frozen_string_literal: true

require_relative "test_helper"

class ExtendedRPCFeaturesTest < SDKTestCase
  def test_permission_acknowledgement_uses_typed_result_and_exact_wire_contract
    with_request_log do |request_log, env_vars|
      sdk = client(env_vars: env_vars)
      sdk.start

      result = sdk.acknowledge_permission("permission-1")
      request = last_request(request_log)

      assert_instance_of(AutohandSDK::PermissionAcknowledgementResult, result)
      assert_predicate(result, :success?)
      assert_equal("autohand.permissionAcknowledged", request.fetch("method"))
      assert_equal({ "requestId" => "permission-1" }, request.fetch("params"))
    ensure
      sdk&.close
    end
  end

  def test_directory_access_response_uses_typed_result_and_exact_wire_contract
    with_request_log do |request_log, env_vars|
      sdk = client(env_vars: env_vars)
      sdk.start

      result = sdk.respond_to_directory_access("directory-1", granted: true)
      request = last_request(request_log)

      assert_instance_of(AutohandSDK::DirectoryAccessResponseResult, result)
      assert_predicate(result, :success?)
      assert_equal("autohand.directoryAccessResponse", request.fetch("method"))
      assert_equal({ "requestId" => "directory-1", "granted" => true }, request.fetch("params"))
    ensure
      sdk&.close
    end
  end

  def test_directory_access_acknowledgement_uses_exact_wire_contract
    with_request_log do |request_log, env_vars|
      sdk = client(env_vars: env_vars)
      sdk.start

      result = sdk.acknowledge_directory_access("directory-2")
      request = last_request(request_log)

      assert_instance_of(AutohandSDK::DirectoryAccessAcknowledgementResult, result)
      assert_predicate(result, :success?)
      assert_equal("autohand.directoryAccessAcknowledged", request.fetch("method"))
      assert_equal({ "requestId" => "directory-2" }, request.fetch("params"))
    ensure
      sdk&.close
    end
  end

  def test_multi_file_change_decision_maps_nested_result_and_wire_contract
    with_request_log do |request_log, env_vars|
      sdk = client(env_vars: env_vars)
      sdk.start

      result = sdk.decide_changes(
        "batch-1",
        action: :accept_selected,
        selected_change_ids: %w[change-1 change-2]
      )
      request = last_request(request_log)

      assert_instance_of(AutohandSDK::ChangesDecisionResult, result)
      assert_predicate(result, :success?)
      assert_equal(2, result.applied_count)
      assert_equal("change-skipped", result.errors.first.change_id)
      assert_equal("autohand.changesDecision", request.fetch("method"))
      assert_equal(
        { "batchId" => "batch-1", "action" => "accept_selected", "selectedChangeIds" => %w[change-1 change-2] },
        request.fetch("params")
      )
    ensure
      sdk&.close
    end
  end

  def test_session_history_maps_pagination_and_typed_entries
    with_request_log do |request_log, env_vars|
      sdk = client(env_vars: env_vars)
      sdk.start

      result = sdk.get_session_history(page: 2, page_size: 10)
      request = last_request(request_log)

      assert_instance_of(AutohandSDK::SessionHistoryResult, result)
      assert_equal(2, result.current_page)
      assert_equal(25, result.total_items)
      assert_instance_of(AutohandSDK::SessionHistoryEntry, result.sessions.first)
      assert_equal("completed", result.sessions.first.status)
      assert_equal("autohand.getHistory", request.fetch("method"))
      assert_equal({ "page" => 2, "pageSize" => 10 }, request.fetch("params"))
    ensure
      sdk&.close
    end
  end

  def test_session_details_returns_typed_success_union_with_messages
    with_request_log do |request_log, env_vars|
      sdk = client(env_vars: env_vars)
      sdk.start

      result = sdk.get_session_details("session-42")
      request = last_request(request_log)

      assert_instance_of(AutohandSDK::SessionDetailsSuccess, result)
      assert_predicate(result, :success?)
      assert_equal("Done", result.messages.first.content)
      assert_equal("write_file", result.messages.first.tool_calls.first.name)
      assert_equal("autohand.getSession", request.fetch("method"))
      assert_equal({ "sessionId" => "session-42" }, request.fetch("params"))
      assert_instance_of(
        AutohandSDK::SessionDetailsFailure,
        AutohandSDK::SessionDetailsResult.from_rpc("success" => false, "error" => "not found")
      )
    ensure
      sdk&.close
    end
  end

  def test_session_attachment_returns_typed_metadata
    with_request_log do |request_log, env_vars|
      sdk = client(env_vars: env_vars)
      sdk.start

      result = sdk.attach_session("session-existing")
      request = last_request(request_log)

      assert_instance_of(AutohandSDK::SessionAttachResult, result)
      assert_predicate(result, :success?)
      assert_equal("session-existing", result.session_id)
      assert_equal(7, result.message_count)
      assert_equal("autohand.session.attach", request.fetch("method"))
      assert_equal({ "sessionId" => "session-existing" }, request.fetch("params"))
    ensure
      sdk&.close
    end
  end

  def test_timed_yolo_mode_supports_canonical_and_compatibility_wire_names
    with_request_log do |request_log, env_vars|
      sdk = client(env_vars: env_vars)
      sdk.start

      canonical = sdk.set_yolo_mode("*", timeout_seconds: 900)
      compatibility = sdk.set_yolo_mode("workspace/**", timeout_seconds: 60, compatibility_alias: true)
      canonical_request, compatibility_request = requests(request_log).last(2)

      assert_instance_of(AutohandSDK::YoloSetResult, canonical)
      assert_predicate(canonical, :success?)
      assert_equal(900, canonical.expires_in)
      assert_predicate(compatibility, :success?)
      assert_equal("autohand.yoloSet", canonical_request.fetch("method"))
      assert_equal({ "pattern" => "*", "timeoutSeconds" => 900 }, canonical_request.fetch("params"))
      assert_equal("autohand.yolo.set", compatibility_request.fetch("method"))
    ensure
      sdk&.close
    end
  end

  def test_vscode_mcp_tool_registration_serializes_typed_descriptors
    with_request_log do |request_log, env_vars|
      sdk = client(env_vars: env_vars)
      sdk.start
      schema = AutohandSDK::MCPInputSchema.new(
        properties: { "issue" => { "type" => "string" } },
        required: ["issue"]
      )
      tool = AutohandSDK::VscodeMCPTool.new(
        name: "open_issue",
        description: "Open an issue",
        server_name: "vscode",
        input_schema: schema
      )

      result = sdk.register_vscode_mcp_tools([tool])
      request = last_request(request_log)

      assert_instance_of(AutohandSDK::MCPSetVscodeToolsResult, result)
      assert_predicate(result, :success?)
      assert_equal("autohand.mcp.setVscodeTools", request.fetch("method"))
      assert_equal("object", request.dig("params", "tools", 0, "inputSchema", "type"))
      assert_equal(["issue"], request.dig("params", "tools", 0, "inputSchema", "required"))
    ensure
      sdk&.close
    end
  end

  def test_mcp_invocation_response_sends_completion_payload
    with_request_log do |request_log, env_vars|
      sdk = client(env_vars: env_vars)
      sdk.start

      result = sdk.complete_mcp_invocation("invoke-1", success: false, error: "tool unavailable")
      request = last_request(request_log)

      assert_instance_of(AutohandSDK::MCPInvokeResponseResult, result)
      assert_predicate(result, :success?)
      assert_equal("autohand.mcp.invokeResponse", request.fetch("method"))
      assert_equal(
        { "requestId" => "invoke-1", "success" => false, "error" => "tool unavailable" },
        request.fetch("params")
      )
    ensure
      sdk&.close
    end
  end

  def test_project_learning_recommendations_map_audit_and_ranked_results
    with_request_log do |request_log, env_vars|
      sdk = client(env_vars: env_vars)
      sdk.start

      result = sdk.recommend_project_learning(deep: true)
      request = last_request(request_log)

      assert_instance_of(AutohandSDK::LearnRecommendResult, result)
      assert_predicate(result, :success?)
      assert_equal("outdated", result.audit.first.status)
      assert_in_delta(0.97, result.recommendations.first.score)
      assert_equal("Deep contract gap", result.gap_analysis)
      assert_equal("autohand.learn.recommend", request.fetch("method"))
      assert_equal({ "deep" => true }, request.fetch("params"))
    ensure
      sdk&.close
    end
  end

  def test_project_learning_updates_map_each_skill_status
    with_request_log do |request_log, env_vars|
      sdk = client(env_vars: env_vars)
      sdk.start

      result = sdk.update_project_learning
      request = last_request(request_log)

      assert_instance_of(AutohandSDK::LearnUpdateResult, result)
      assert_predicate(result, :success?)
      assert_equal(1, result.updated)
      assert_equal(%w[updated unchanged], result.results.map(&:status))
      assert_equal("autohand.learn.update", request.fetch("method"))
      assert_empty(request.fetch("params"))
    ensure
      sdk&.close
    end
  end

  def test_skill_generation_returns_typed_generated_artifact
    with_request_log do |request_log, env_vars|
      sdk = client(env_vars: env_vars)
      sdk.start

      result = sdk.generate_project_skill(scope: :project)
      request = last_request(request_log)

      assert_instance_of(AutohandSDK::LearnGenerateResult, result)
      assert_predicate(result, :success?)
      assert_equal("generated-rpc-contracts", result.skill_name)
      assert_equal("/skills/project/generated-rpc-contracts", result.skill_path)
      assert_equal("autohand.learn.generate", request.fetch("method"))
      assert_equal({ "scope" => "project" }, request.fetch("params"))
    ensure
      sdk&.close
    end
  end

  def test_tools_registry_maps_typed_entries_and_diagnostics
    with_request_log do |request_log, env_vars|
      sdk = client(env_vars: env_vars)
      sdk.start

      result = sdk.get_tools_registry
      request = last_request(request_log)

      assert_instance_of(AutohandSDK::ToolsRegistryResult, result)
      assert_instance_of(AutohandSDK::ToolRegistryEntry, result.tools.first)
      assert(result.tools.first.requires_approval)
      assert_equal("builtin", result.tools.first.source)
      assert_equal("invalid schema", result.diagnostics.first.reason)
      assert_equal("autohand.getToolsRegistry", request.fetch("method"))
      assert_empty(request.fetch("params"))
    ensure
      sdk&.close
    end
  end

  def test_context_compaction_control_returns_effective_state
    with_request_log do |request_log, env_vars|
      sdk = client(env_vars: env_vars)
      sdk.start

      result = sdk.set_context_compaction(false)
      request = last_request(request_log)

      assert_instance_of(AutohandSDK::ContextCompactResult, result)
      refute_predicate(result, :enabled?)
      assert_equal("autohand.setContextCompact", request.fetch("method"))
      assert_equal({ "enabled" => false }, request.fetch("params"))
    ensure
      sdk&.close
    end
  end

  private

  def with_request_log
    Dir.mktmpdir("autohand-sdk-request-log") do |directory|
      path = File.join(directory, "requests.jsonl")
      yield path, { "AUTOHAND_TEST_REQUEST_LOG" => path }
    end
  end

  def last_request(path)
    requests(path).last
  end

  def requests(path)
    File.readlines(path, chomp: true).map { |line| JSON.parse(line) }
  end
end

class ExtendedRPCEventsTest < SDKTestCase
  def test_auto_mode_iteration_notifications_become_native_events
    with_typed_events do |sdk|
      sdk.set_context_compaction(true)
      event = sdk.events.find { |candidate| candidate.is_a?(AutohandSDK::AutomodeIterationEvent) }

      assert_equal("automode_iteration", event.type)
      assert_equal("automode-1", event.session_id)
      assert_equal(3, event.iteration)
      assert_equal(%w[edit test], event.actions)
      assert_equal(420, event.tokens_used)
    end
  end

  def test_auto_mode_completion_notifications_become_native_events
    with_typed_events do |sdk|
      sdk.set_context_compaction(true)
      event = sdk.events.find { |candidate| candidate.is_a?(AutohandSDK::AutomodeCompleteEvent) }

      assert_equal("automode_complete", event.type)
      assert_equal(5, event.iterations)
      assert_equal(2, event.files_created)
      assert_equal(4, event.files_modified)
    end
  end

  def test_auto_mode_error_notifications_become_native_events
    with_typed_events do |sdk|
      sdk.set_context_compaction(true)
      event = sdk.events.find { |candidate| candidate.is_a?(AutohandSDK::AutomodeErrorEvent) }

      assert_equal("automode_error", event.type)
      assert_equal("automode-2", event.session_id)
      assert_equal("iteration budget exceeded", event.error)
    end
  end

  def test_pre_tool_hook_notifications_become_native_events
    with_typed_events do |sdk|
      sdk.set_context_compaction(true)
      event = sdk.events.find { |candidate| candidate.is_a?(AutohandSDK::HookPreToolEvent) }

      assert_equal("hook_pre_tool", event.type)
      assert_equal("write_file", event.tool_name)
      assert_equal("README.md", event.args.fetch("path"))
    end
  end

  def test_post_tool_hook_notifications_become_native_events
    with_typed_events do |sdk|
      sdk.set_context_compaction(true)
      event = sdk.events.find { |candidate| candidate.is_a?(AutohandSDK::HookPostToolEvent) }

      assert_equal("hook_post_tool", event.type)
      assert_predicate(event, :success?)
      assert_in_delta(18.5, event.duration)
      assert_equal("written", event.output)
    end
  end

  def test_pre_prompt_hook_notifications_become_native_events
    with_typed_events do |sdk|
      sdk.set_context_compaction(true)
      event = sdk.events.find { |candidate| candidate.is_a?(AutohandSDK::HookPrePromptEvent) }

      assert_equal("hook_pre_prompt", event.type)
      assert_equal("Review the SDK", event.instruction)
      assert_equal(%w[README.md lib/autohand_sdk.rb], event.mentioned_files)
    end
  end

  def test_post_response_hook_notifications_become_native_events
    with_typed_events do |sdk|
      sdk.set_context_compaction(true)
      event = sdk.events.find { |candidate| candidate.is_a?(AutohandSDK::HookPostResponseEvent) }

      assert_equal("hook_post_response", event.type)
      assert_equal(1_250, event.tokens_used)
      assert_equal("actual", event.tokens_usage_status)
      assert_equal(2, event.tool_calls_count)
      assert_in_delta(415.2, event.duration)
    end
  end

  def test_mcp_invocation_request_notifications_become_native_events
    with_typed_events do |sdk|
      sdk.set_context_compaction(true)
      event = sdk.events.find { |candidate| candidate.is_a?(AutohandSDK::MCPInvokeRequestEvent) }

      assert_equal("mcp_invoke_request", event.type)
      assert_equal("mcp-invoke-9", event.request_id)
      assert_equal("open_issue", event.tool_name)
      assert_equal("SDK parity", event.args.fetch("issue"))
    end
  end

  private

  def with_typed_events
    sdk = client(env_vars: { "AUTOHAND_TEST_TYPED_EVENTS" => "1" })
    sdk.start
    yield sdk
  ensure
    sdk&.close
  end
end
