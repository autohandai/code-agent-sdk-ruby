# frozen_string_literal: true

require "autohand_sdk"

AutohandSDK::Client.open(cwd: ".") do |sdk|
  sdk.stream_prompt("Review the current working tree").each do |event|
    case event["type"]
    when "message_update"
      print event["delta"]
    when "tool_start"
      warn "\nRunning #{event["tool_name"] || event["toolName"]}"
    end
  end
end
