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

  private

  def with_request_log
    Dir.mktmpdir("autohand-sdk-request-log") do |directory|
      path = File.join(directory, "requests.jsonl")
      yield path, { "AUTOHAND_TEST_REQUEST_LOG" => path }
    end
  end

  def last_request(path)
    JSON.parse(File.readlines(path, chomp: true).last)
  end
end
