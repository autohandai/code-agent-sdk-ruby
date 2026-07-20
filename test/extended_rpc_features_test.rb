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
