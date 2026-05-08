# SDLC Workflows

## Discovery

Use plan mode for read-only discovery before writes:

```ruby
AutohandSDK::Agent.open(cwd: ".", permission_mode: "plan") do |agent|
  puts agent.run("Inspect this repo and propose the smallest safe fix").fetch(:text)
end
```

## Gated implementation

```ruby
AutohandSDK::Agent.open(cwd: ".", permission_mode: "interactive") do |agent|
  agent.stream("Apply the approved plan").each do |event|
    case event["type"]
    when "permission_request"
      agent.allow_permission(event["request_id"], scope: :once)
    when "message_update"
      print event["delta"]
    end
  end
end
```

## Release readiness

```ruby
AutohandSDK::Agent.open(cwd: ".", instructions: "Be strict about publish readiness.") do |agent|
  report = agent.run_json(
    "Assess release readiness for this gem",
    schema_name: "ReleaseReadiness",
    schema: {
      summary: "string",
      blockers: [{ title: "string", severity: "low | medium | high" }],
      checks: ["string"]
    }
  )

  puts report.fetch("summary")
end
```

Use the SDK as orchestration glue. Keep application policy, persistence, retries, and approvals in your app where they can be tested directly.
