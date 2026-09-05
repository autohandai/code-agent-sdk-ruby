# Resumable step control

Pass `stop_when` to `Agent#send`, `#run`, `#stream`, `#run_json`, or the client's
`#prompt` and `#stream_prompt`. Conditions run after the CLI persists a completed
tool step. A stop leaves the conversation available for the next prompt.

```ruby
require "autohand_sdk"

AutohandSDK::Agent.open(cwd: Dir.pwd) do |agent|
  result = agent.run("Inspect the project", stop_when: AutohandSDK.is_step_count(2))
  puts result.fetch(:status) # "stopped" if the condition ended the turn
  result.fetch(:steps).each do |step|
    puts "Step #{step.step_number}: #{step.tool_calls.map(&:tool).join(', ')}"
  end

  agent.run("Continue using the saved tool results")
end
```

`AutohandSDK.is_step_count(n)` requires a positive integer.
`AutohandSDK.has_tool_call(name)` matches a tool in the latest completed step.
A single callable or an array of callables is accepted. Arrays use OR semantics
and stop evaluating once a condition returns `true`.

```ruby
agent.run("Inspect configuration", stop_when: [
  AutohandSDK.has_tool_call("read_file"),
  ->(context) { context.steps.length >= 4 }
])
```

Callbacks receive `StopConditionContext` with immutable snapshots of the current
prompt's steps. `AgentStep` contains `step_number`, `thought`, `tool_calls`, and
`tool_results`. Tool calls expose `id`, `tool`, and `args`; results expose `tool`,
`success`, `output`, and `error`. Streaming prompt consumers receive typed
`StepEndEvent` values with `type == "step_end"`, `step_id`, `step`, and `timestamp`.
The general event stream retains raw step payloads, which can be decoded with
`StepEndEvent.from_rpc`.

Callbacks execute on a separate worker so they may wait for IO while RPC events
continue. They must return `true` or `false`. The SDK sends only
`stopWhen: {mode: "host"}` to the CLI; callbacks remain in Ruby. If a callback
raises, the SDK requests a stop, waits for terminal completion, then raises the
original exception. A rejected decision, malformed step, or event overflow fails
the prompt and settles or terminates its CLI turn before releasing the queue.

Runs retain events and steps for repeated `wait` calls and independent replay
subscriptions. Status is `completed`, `stopped`, `failed`, or `aborted`, based on
the CLI's terminal reason. An error cannot become a completed result merely
because the CLI process closes.

`run.abort` cancels only that run. Unstarted and queued runs cannot interrupt the
active prompt; completed runs ignore abort. Cancelling an active run also stops
its predicate worker and drains the turn. An unresponsive CLI is stopped after
the cleanup deadline. Abandoning the last stream consumer cancels the run unless
another stream or waiter still needs it.

All prompt APIs share the same turn queue. `Client#prompt` now waits for terminal
completion and returns the original RPC acknowledgement or legacy content result.
Use the generic `request` method when an immediate, low-level RPC response is
specifically required. Current CLI `turnEnd` notifications are preserved without
inventing an additional `agentEnd` event.

## Integration check

```sh
AUTOHAND_TEST_CLI_PATH=/path/to/autohand bundle exec ruby -Ilib:test test/harness_step_control_test.rb
```

This executes the real CLI against local authentication and Autohand AI HTTP
mocks, reads a real file, stops after one step, and verifies that continuation
includes the saved tool result. It supplies an explicit provider configuration
and model context window; it does not establish default provider selection or
production inference behavior. Without the environment variable it is skipped.
