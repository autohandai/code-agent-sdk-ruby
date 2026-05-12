# frozen_string_literal: true

require "autohand_sdk"
require "json"

def github_credentials_from_env
  token_env_name =
    if ENV["GITHUB_TOKEN"] && !ENV["GITHUB_TOKEN"].empty?
      "GITHUB_TOKEN"
    elsif ENV["GH_TOKEN"] && !ENV["GH_TOKEN"].empty?
      "GH_TOKEN"
    end

  raise "Set GITHUB_TOKEN or GH_TOKEN before running this example." unless token_env_name

  {
    token_env_name: token_env_name,
    remote: ENV.fetch("AUTOHAND_GITHUB_REMOTE", "origin"),
    base_branch: ENV.fetch("AUTOHAND_GITHUB_BASE_BRANCH", "main"),
    repository: ENV["GITHUB_REPOSITORY"]
  }
end

def incident_packet
  {
    id: "INC-2026-05-12-0417",
    severity: "sev2",
    service: "checkout-api",
    first_seen: "2026-05-12T09:14:22Z",
    release: "checkout-api@2026.05.12.3",
    error_signature: "RuntimeError: checkout discount failed while replaying coupon idempotency key",
    user_impact: "Checkout returns HTTP 500 for guest customers using coupon replay from mobile clients.",
    stack_trace: [
      "RuntimeError: checkout discount failed while replaying coupon idempotency key",
      "    at app/services/checkout/discounts.rb:42",
      "    at app/services/checkout/payment_intent.rb:118",
      "    at app/controllers/checkout_controller.rb:88"
    ].join("\n"),
    logs: [
      "level=error trace=trk_94 request_id=req_7f2 route=POST /checkout status=500 duration_ms=184",
      "level=warn trace=trk_94 idempotency_key=checkout:cart_live_9834:attempt_2 cache_status=miss",
      "level=info trace=trk_94 feature_flags=discount-v2,coupon-replay"
    ],
    request: {
      method: "POST",
      path: "/checkout",
      payload: {
        cart_id: "cart_live_9834",
        subtotal: 129,
        customer: nil,
        coupon: { code: "SPRING25", source: "mobile-v5" },
        idempotency_key: "checkout:cart_live_9834:attempt_2"
      }
    },
    suspected_files: [
      "app/services/checkout/discounts.rb",
      "app/services/checkout/payment_intent.rb",
      "app/controllers/checkout_controller.rb",
      "spec/requests/checkout_spec.rb"
    ],
    reproduction_command: "bundle exec rspec spec/requests/checkout_spec.rb:88",
    validation_commands: [
      "bundle exec rspec spec/requests/checkout_spec.rb",
      "bundle exec rspec",
      "bundle exec rubocop"
    ]
  }
end

def build_prompt(incident, github)
  repo_hint = github[:repository] ? "- GitHub repository hint: #{github[:repository]}." : "- Discover the GitHub repository from git remote output."

  [
    "You are a senior QA engineering agent responsible for converting production incidents into verified repair pull requests.",
    "",
    "GitHub credentials:",
    "- A GitHub token is available in the #{github[:token_env_name]} environment variable. Do not print or commit the token.",
    "- Use git remote #{github[:remote]}.",
    "- Open the pull request against #{github[:base_branch]}.",
    repo_hint,
    "- Before pushing, run gh auth status or an equivalent non-secret auth check.",
    "",
    "Incident packet:",
    "```json",
    JSON.pretty_generate(incident),
    "```",
    "",
    "Required workflow:",
    "1. Inspect the target repository and confirm the likely failing path.",
    "2. Reproduce the incident using the provided payload or nearest existing test harness.",
    "3. Fix the root cause, not just the thrown exception.",
    "4. Add a regression test covering guest checkout, coupon replay, and idempotency behavior.",
    "5. Run the focused test first, then the relevant validation commands.",
    "6. Create a branch named autohand/fix-checkout-incident-inc-2026-05-12-0417.",
    "7. Commit the fix with a clear message.",
    "8. Push the branch and open a pull request.",
    "9. In the PR body, include the incident id, error signature, files changed, tests run, and any residual risk."
  ].join("\n")
end

target_repo = ENV.fetch("AUTOHAND_TARGET_REPO", ".")
prompt = build_prompt(incident_packet, github_credentials_from_env)

AutohandSDK::Agent.open(cwd: target_repo, instructions: "Work like a careful senior QA engineer. Keep secrets out of logs and pull request text.") do |agent|
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
