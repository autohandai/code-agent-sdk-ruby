# frozen_string_literal: true

require "autohand_sdk"

TYPED_HOOK_EVENTS = [
  AutohandSDK::HookPreToolEvent,
  AutohandSDK::HookPostToolEvent,
  AutohandSDK::HookFileModifiedEvent,
  AutohandSDK::HookPrePromptEvent,
  AutohandSDK::HookPostResponseEvent,
  AutohandSDK::HookSessionErrorEvent,
  AutohandSDK::HookStopEvent,
  AutohandSDK::HookSessionStartEvent,
  AutohandSDK::HookSessionEndEvent,
  AutohandSDK::HookSubagentStopEvent,
  AutohandSDK::HookPermissionRequestEvent,
  AutohandSDK::HookNotificationEvent,
  AutohandSDK::HookContextCompactedEvent,
  AutohandSDK::HookContextOverflowEvent,
  AutohandSDK::HookContextWarningEvent,
  AutohandSDK::HookContextCriticalEvent
].freeze

prompt = ARGV.empty? ? "Inspect this repository and summarize its structure" : ARGV.join(" ")

AutohandSDK::Client.open(cwd: ENV.fetch("AUTOHAND_CWD", ".")) do |sdk|
  sdk.stream_prompt(prompt).each do |event|
    if TYPED_HOOK_EVENTS.any? { |event_type| event.is_a?(event_type) }
      puts "#{event.method} at #{event.timestamp}"
    elsif event.is_a?(AutohandSDK::UnknownNotificationEvent) &&
          event.method.start_with?("autohand.hook.")
      warn "raw #{event.method}: #{event.params.inspect}"
    end
  end
end
