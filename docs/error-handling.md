# Error Handling

All SDK-specific errors inherit from `AutohandSDK::Error`.

```ruby
begin
  AutohandSDK::Client.open(cwd: ".") do |sdk|
    sdk.stream_prompt("Make the smallest safe fix").each { |event| puts event.inspect }
  end
rescue AutohandSDK::RequestTimeoutError => error
  warn "Timed out: #{error.message}"
rescue AutohandSDK::RPCError => error
  warn "RPC error #{error.code}: #{error.message}"
  warn error.data.inspect
rescue AutohandSDK::TransportError => error
  warn "CLI transport failed: #{error.message}"
end
```

Error classes:

- `ConfigurationError` - invalid SDK options.
- `TransportError` - subprocess, stdin/stdout, or startup check failure.
- `TransportNotStartedError` - request attempted before the transport is running.
- `RequestTimeoutError` - RPC request exceeded `timeout`.
- `RPCError` - CLI returned a JSON-RPC error response.
- `StructuredOutputError` - JSON helper could not parse the agent response.

For hosted or queue-backed systems, prefer block APIs (`Client.open`, `Agent.open`) so subprocesses close even when exceptions are raised.
