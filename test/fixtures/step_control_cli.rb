#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

$stdout.sync = true

def notify(method, params)
  puts JSON.generate(jsonrpc: "2.0", method: "autohand.#{method}", params: params)
end

def reply(id, result)
  puts JSON.generate(jsonrpc: "2.0", id: id, result: result)
end

def step(number, malformed: false)
  notify("stepEnd", {
           stepId: "step-#{number}", timestamp: "2026-09-06T00:00:00Z",
           step: { stepNumber: malformed ? 0 : number,
                   toolCalls: [{ id: "call-#{number}", tool: "read_file", args: { path: "evidence.txt" } }],
                   toolResults: [{ tool: "read_file", success: true, output: "persisted evidence #{number}" }] }
         })
end

active = nil
number = 0
$stdin.each_line do |line|
  request = JSON.parse(line)
  File.open(ENV.fetch("AUTOHAND_TEST_REQUEST_LOG"), "a") { |file| file.puts(line) }
  id = request.fetch("id")
  params = request.fetch("params", {})
  case request.fetch("method")
  when "autohand.prompt"
    message = params.fetch("message")
    if message == "reject"
      reply(id, { success: false, error: "rejected prompt" })
      next
    end
    reply(id, { success: true })
    active = message
    notify("turnStart", { turnId: message })
    if %w[steps malformed reject_decision ignore_abort].include?(message)
      number = 1
      step(number, malformed: message == "malformed")
    elsif message == "pending_error"
      notify("error", { message: "model failed before cancellation" })
    else
      (message == "flood" ? 1_500 : 1).times { notify("messageUpdate", { delta: "persisted evidence" }) }
      notify("error", { message: "model failed" }) if message == "error"
      reason = %w[aborted error].include?(message) ? message : "completed"
      notify("turnEnd", { turnId: message, reason: reason })
      active = nil
    end
  when "autohand.stepDecision"
    accepted = active != "reject_decision" && params["stepId"] == "step-#{number}"
    reply(id, { success: accepted })
    next unless accepted

    if params["stop"]
      notify("turnEnd", { turnId: active, reason: "stop_condition" })
      active = nil
    else
      number += 1
      step(number)
    end
  when "autohand.abort"
    next if active == "ignore_abort"

    if active
      notify("messageUpdate", { delta: "drained abandoned turn" })
      notify("turnEnd", { turnId: active, reason: "aborted" })
      active = nil
    end
    reply(id, { success: true })
  else
    reply(id, { status: "idle" })
  end
end
