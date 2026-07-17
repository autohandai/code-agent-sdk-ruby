# Replayable Autoresearch Ledger

The Ruby SDK exposes Autohand's persisted autoresearch engine through the same
JSON-RPC methods as the TypeScript SDK. Ruby callers use snake-case keyword
arguments; the SDK recursively converts them to the CLI's camel-case wire
format. Responses intentionally remain string-keyed hashes.

## Capability check

CLI builds may not all expose autoresearch. Check the connected process before
starting a command-driven run:

```ruby
if agent.supports_command?("/autoresearch")
  agent.autoresearch("Improve the benchmark").wait
end
```

The lifecycle RPC methods require a CLI build that implements
`autohand.autoresearch.*`.

## Start and inspect

```ruby
started = agent.start_autoresearch(
  objective: "Reduce test runtime without regressions",
  metric_name: "total_ms",
  metric_unit: "ms",
  direction: "lower",
  measure_command: "bundle exec rake test",
  checks_command: "bundle exec rubocop",
  max_iterations: 12,
  timeout_ms: 60_000,
  files_in_scope: ["lib", "test"],
  secondary_objectives: [
    { name: "peak_memory_mb", unit: "mb", direction: "lower" }
  ],
  constraints: [
    { metric_name: "failures", operator: "<=", threshold: 0 }
  ],
  sampling: { min_samples: 3, max_samples: 7, confidence_threshold: 0.9 },
  retention: { max_artifact_bytes: 100_000_000, max_artifact_age_days: 14 },
  subagents: { idea_generation: true, measurement_analysis: true }
)

raise started.fetch("error", "autoresearch failed") unless started["success"]

status = agent.get_autoresearch_status
history = agent.get_autoresearch_history
```

Starting an existing paused session resumes its persisted `.auto/` state.
Stopping pauses the loop without deleting that state:

```ruby
agent.stop_autoresearch
```

## Replay and decision analysis

```ruby
attempt_id = history.fetch("attempts").first.fetch("attemptId")

original = agent.replay_autoresearch(attempt_id: attempt_id, evaluator: "original")
current = agent.replay_autoresearch(attempt_id: attempt_id, evaluator: "current")
agent.rescore_autoresearch(attempt_id: attempt_id)
agent.rescore_autoresearch(all: true)

agent.compare_autoresearch(
  left_attempt_id: original.fetch("attemptId"),
  right_attempt_id: current.fetch("attemptId")
)

pareto = agent.get_autoresearch_pareto
```

Replays evaluate candidates in isolated worktrees. Rescoring appends a new
decision from stored measurements and the current policy; it does not rewrite
the immutable evaluation record.

## Pinning and pruning

```ruby
agent.pin_autoresearch(attempt_id: attempt_id, pinned: true)
preview = agent.prune_autoresearch(dry_run: true)

# Explicitly apply retention only after inspecting preview["candidates"].
applied = agent.prune_autoresearch(dry_run: false, yes: true)
```

Pinned and materialized candidates remain protected. Always preview before an
applied prune.

## Events

`Client#stream_prompt` and `RPCClient#events` expose autoresearch lifecycle and
operation notifications as hashes with `"type" => "autoresearch"`. Lifecycle
events include `phase` values `start`, `status`, or `pause`; ledger operation
events include the CLI's `operation`, `phase`, `success`, and optional
`attempt_id`, `applied`, and `error` fields.
