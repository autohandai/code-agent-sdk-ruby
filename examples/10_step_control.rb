# frozen_string_literal: true

require "autohand_sdk"

AutohandSDK::Agent.open(cwd: ".") do |agent|
  result = agent.run("Inspect this repository", stop_when: AutohandSDK.is_step_count(2))
  puts "#{result.fetch(:status)} after #{result.fetch(:steps).length} completed tool steps"
  next unless result.fetch(:status) == "stopped"

  puts agent.run("Continue using the saved tool results").fetch(:text)
end
