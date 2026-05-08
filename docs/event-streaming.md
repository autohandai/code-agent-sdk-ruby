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

The SDK emits an `agent_end` event after `turn_end` so stream consumers have a stable completion marker.
