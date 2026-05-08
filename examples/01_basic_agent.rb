# frozen_string_literal: true

require "autohand_sdk"

AutohandSDK::Agent.open(cwd: ".", instructions: "Answer with concise Ruby-focused guidance.") do |agent|
  result = agent.run("Summarize this repository")
  puts result.fetch(:text)
end
