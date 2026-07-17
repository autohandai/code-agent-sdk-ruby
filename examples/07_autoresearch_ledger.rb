# frozen_string_literal: true

require "autohand_sdk"

AutohandSDK::Agent.open(cwd: ".", permission_mode: "interactive") do |agent|
  unless agent.supports_command?("/autoresearch")
    warn "The connected Autohand CLI does not expose /autoresearch."
    next
  end

  started = agent.start_autoresearch(
    objective: "Reduce Ruby SDK test runtime without failures",
    metric_name: "total_ms",
    metric_unit: "ms",
    direction: "lower",
    measure_command: "bundle exec rake test",
    checks_command: "bundle exec rubocop",
    max_iterations: 8,
    sampling: { min_samples: 3, max_samples: 7 },
    constraints: [{ metric_name: "failures", operator: "<=", threshold: 0 }]
  )

  raise started.fetch("error", "autoresearch failed") unless started["success"]

  status = agent.get_autoresearch_status
  history = agent.get_autoresearch_history
  puts "active=#{status["active"]} attempts=#{history.fetch("attempts", []).length}"

  if (attempt = history.fetch("attempts", []).first)
    attempt_id = attempt.fetch("attemptId")
    agent.replay_autoresearch(attempt_id: attempt_id, evaluator: "current")
    agent.rescore_autoresearch(attempt_id: attempt_id)
    agent.pin_autoresearch(attempt_id: attempt_id, pinned: true)
  end

  preview = agent.prune_autoresearch(dry_run: true)
  puts "prunable_bytes=#{preview.fetch("bytesFreed", 0)}"
  agent.stop_autoresearch
end
