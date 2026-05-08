# frozen_string_literal: true

require "autohand_sdk"

AutohandSDK::Agent.open(cwd: ".") do |agent|
  result = agent.run_json(
    "Assess this SDK for release readiness",
    schema_name: "ReleaseRisk",
    schema: {
      summary: "string",
      risks: [{ title: "string", severity: "low | medium | high" }]
    }
  )

  puts result.fetch("summary")
end
