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
