# Event Streaming

`stream_prompt` returns a Ruby `Enumerator`. Events are string-keyed hashes that mirror JSON-RPC payloads and include snake-case aliases for common camel-case fields.

```ruby
sdk.stream_prompt("Run the tests and summarize failures").each do |event|
  case event["type"]
  when "message_update"
    print event["delta"]
  when "tool_start"
    warn "Running #{event["tool_name"]}"
  when "permission_request"
    sdk.allow_permission(event["request_id"], scope: :once)
  end
end
```

Common event types:

- `agent_start`
- `agent_end`
- `turn_start`
- `turn_end`
- `message_start`
- `message_update`
- `message_end`
- `tool_start`
- `tool_update`
- `tool_end`
- `permission_request`
- `directory_access_request`
- `file_modified`
- `changes_batch_start`
- `changes_batch_update`
- `changes_batch_end`
- `error`

## Typed hook notifications

Hook notifications are validated at the transport boundary and exposed through
these public event types:

| JSON-RPC method | Ruby event | `type` / key readers |
| --- | --- | --- |
| `autohand.hook.preTool` | `HookPreToolEvent` | `hook_pre_tool`; `tool_id`, `tool_name`, `args` |
| `autohand.hook.postTool` | `HookPostToolEvent` | `hook_post_tool`; `success?`, `duration`, `output` |
| `autohand.hook.fileModified` | `HookFileModifiedEvent` | `file_modified`; `file_path`, `change_type`, `tool_id` |
| `autohand.hook.prePrompt` | `HookPrePromptEvent` | `hook_pre_prompt`; `instruction`, `mentioned_files` |
| `autohand.hook.postResponse` | `HookPostResponseEvent` | `hook_post_response`; `tokens_used`, `tokens_usage_status`, `tool_calls_count`, `duration` |
| `autohand.hook.sessionError` | `HookSessionErrorEvent` | `hook_session_error`; `error`, `code`, `context` |
| `autohand.hook.stop` | `HookStopEvent` | `hook_stop`; `tokens_used`, `tokens_usage_status`, `tool_calls_count`, `duration` |
| `autohand.hook.sessionStart` | `HookSessionStartEvent` | `hook_session_start`; `session_type` |
| `autohand.hook.sessionEnd` | `HookSessionEndEvent` | `hook_session_end`; `reason`, `duration` |
| `autohand.hook.subagentStop` | `HookSubagentStopEvent` | `hook_subagent_stop`; `subagent_id`, `subagent_name`, `success?`, `error` |
| `autohand.hook.permissionRequest` | `HookPermissionRequestEvent` | `hook_permission_request`; `tool`, `path`, `command`, `args` |
| `autohand.hook.notification` | `HookNotificationEvent` | `hook_notification`; `notification_type`, `message` |
| `autohand.hook.contextCompacted` | `HookContextCompactedEvent` | `hook_context_compacted`; `cropped_count`, `summary`, `usage_percent`, `reason` |
| `autohand.hook.contextOverflow` | `HookContextOverflowEvent` | `hook_context_overflow`; `tokens_before`, `tokens_after`, `cropped_count`, `usage_percent` |
| `autohand.hook.contextWarning` | `HookContextWarningEvent` | `hook_context_warning`; `usage_percent`, `remaining_tokens` |
| `autohand.hook.contextCritical` | `HookContextCriticalEvent` | `hook_context_critical`; `usage_percent`, `remaining_tokens` |

Every event responds to `method` with its exact JSON-RPC method and exposes a
`timestamp`. `HookFileModifiedEvent` extends the existing string-keyed
`file_modified` hash for compatibility; the other hook events are immutable
Ruby `Data` values. Token usage status is `"actual"`, `"unavailable"`, or `nil`
when omitted.

`tokens_used` and `tool_calls_count` in post-response and stop events must be
integers. Context counts and token values (`cropped_count`, `tokens_before`,
`tokens_after`, and `remaining_tokens`) must be non-negative integers. Ruby
retains its arbitrary-precision integer range. `usage_percent` must be finite
and non-negative, but is intentionally not capped at `1.0` because an overflow
event can report a larger value.

An unknown notification, or a known hook that fails a required field, enum, or
numeric check, becomes `AutohandSDK::UnknownNotificationEvent`. Its `method` is
the exact JSON-RPC method and its `params` retain the original top-level JSON
shape: `Hash`, `Array`, `nil`, `String`, numeric, `true`, or `false`. No
`{"value" => ...}` wrapper is added to the event.

```ruby
case event
when AutohandSDK::HookContextWarningEvent
  warn "context usage=#{event.usage_percent}"
when AutohandSDK::UnknownNotificationEvent
  warn "raw #{event.method}: #{event.params.inspect}" if event.method.start_with?("autohand.hook.")
end
```

The CLI acknowledges `autohand.prompt` before it emits the turn. The SDK therefore
keeps the enumerator open after that acknowledgement and completes it only after
the terminal `agent_end` event. It emits `agent_end` after `turn_end` so stream
consumers have a stable completion marker.

Each `RPCClient#events` enumerator has an independent queue. Global subscribers
and the active prompt stream receive their own copies instead of stealing
notifications. Queues retain the newest 1,024 events, bounding memory when a
consumer is slow or absent.

Only one prompt stream is active at a time. Ending a prompt enumeration early
sends `autohand.abort` and drains that turn through its terminal event before the
next prompt starts. If the CLI does not acknowledge and terminate the abandoned
turn within two seconds, the SDK stops the transport so a later operation starts
a fresh CLI process. An unexpected CLI exit or stdout closure also wakes blocked
prompt and global event enumerators and leaves the client restartable.

The same cancellation contract applies to `Agent#stream` and `Run#stream` even
though `Run` uses a background pump to support replay and multiple consumers.
When the last active stream consumer exits early and no `Run#wait` caller is
active, the pump unwinds the low-level prompt enumerator, waits for abort cleanup,
and terminates. Other active stream consumers or waiters keep the run alive.
