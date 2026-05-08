# frozen_string_literal: true

require "autohand_sdk"

AutohandSDK::Client.open(cwd: ".", permission_mode: "interactive") do |sdk|
  sdk.stream_prompt("Run the safest validation command for this project").each do |event|
    case event["type"]
    when "permission_request"
      if event["tool"] == "bash"
        sdk.allow_permission(event["request_id"], scope: :once)
      else
        sdk.deny_permission(event["request_id"], scope: :session)
      end
    when "message_update"
      print event["delta"]
    end
  end
end
