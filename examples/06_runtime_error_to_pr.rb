# frozen_string_literal: true

require "autohand_sdk"

def checkout_discount(cart)
  customer = cart.fetch(:customer)
  tier = customer.fetch(:loyalty_tier)
  tier == "gold" ? cart.fetch(:subtotal) * 0.15 : cart.fetch(:subtotal) * 0.05
rescue StandardError => e
  raise "checkout discount failed: #{e.message}"
end

def capture_runtime_error
  checkout_discount(subtotal: 129, customer: nil)
rescue StandardError => e
  [
    "#{e.class}: #{e.message}",
    "    at app/services/checkout/discounts.rb:42",
    "    at app/controllers/checkout_controller.rb:88",
    "Request: POST /checkout",
    'Payload: {"subtotal":129,"customer":null}'
  ].join("\n")
end

target_repo = ENV.fetch("AUTOHAND_TARGET_REPO", ".")
captured_error = capture_runtime_error

prompt = [
  "You are a QA engineering agent that turns production error reports into small repair pull requests.",
  "Reproduce the failure when the repository makes that possible.",
  "Fix the root cause, add or update a focused regression test, run the relevant validation command,",
  "commit the fix, push a branch, and create a pull request.",
  "Keep the pull request description concise and include the error signature, fix summary, and validation result.",
  "",
  "A runtime error was captured by the application error boundary.",
  "",
  "Captured error:",
  "```text",
  captured_error,
  "```",
  "",
  "Expected user impact:",
  "A checkout session should still calculate a safe default discount when the customer object is missing.",
  "",
  "Please create a pull request with the fix."
].join("\n")

AutohandSDK::Agent.open(cwd: target_repo, instructions: "Work like a careful QA engineer.") do |agent|
  run = agent.send(prompt)
  run.stream.each do |event|
    case event[:type]
    when "message_update"
      print event[:delta]
    when "tool_start"
      puts "\n[tool] #{event[:tool_name] || event[:toolName]}"
    when "permission_request"
      puts "\n[permission] #{event[:tool]}: #{event[:description]}"
    when "error"
      warn "\n[error] #{event[:message]}"
    end
  end

  result = run.wait
  puts "\n\nRun #{result.fetch(:id, "unknown")} #{result.fetch(:status, "complete")}."
end
