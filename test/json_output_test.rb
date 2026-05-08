# frozen_string_literal: true

require_relative "test_helper"

class JsonOutputTest < Minitest::Test
  def test_parses_direct_json
    assert_equal({ "ok" => true }, AutohandSDK::JsonOutput.parse_json_text('{"ok":true}'))
  end

  def test_parses_fenced_json
    text = "Sure:\n```json\n{\"files\":[\"lib/autohand_sdk.rb\"]}\n```"

    assert_equal({ "files" => ["lib/autohand_sdk.rb"] }, AutohandSDK::JsonOutput.parse_json_text(text))
  end

  def test_parses_embedded_json
    text = "The result is {\"risk\":\"low\",\"count\":2}."

    assert_equal({ "risk" => "low", "count" => 2 }, AutohandSDK::JsonOutput.parse_json_text(text))
  end

  def test_raises_structured_output_error_for_empty_response
    error = assert_raises(AutohandSDK::StructuredOutputError) do
      AutohandSDK::JsonOutput.parse_json_text("   ")
    end

    assert_match("empty response", error.message)
    assert_equal("   ", error.raw_response)
  end
end
