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
