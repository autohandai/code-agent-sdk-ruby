# frozen_string_literal: true

require "autohand_sdk"

USAGE = <<~TEXT
  Usage:
    bundle exec ruby examples/08_session_and_automode.rb reset
    bundle exec ruby examples/08_session_and_automode.rb handoff-create
    bundle exec ruby examples/08_session_and_automode.rb handoff-attach TOKEN
    bundle exec ruby examples/08_session_and_automode.rb handoff-attach-latest
    bundle exec ruby examples/08_session_and_automode.rb automode-start PROMPT
    bundle exec ruby examples/08_session_and_automode.rb automode-status
    bundle exec ruby examples/08_session_and_automode.rb automode-pause
    bundle exec ruby examples/08_session_and_automode.rb automode-resume
    bundle exec ruby examples/08_session_and_automode.rb automode-cancel [REASON]
    bundle exec ruby examples/08_session_and_automode.rb automode-log [LIMIT]
TEXT

def print_operation(result)
  fields = ["success=#{result.success?}"]
  fields << "session_id=#{result.session_id}" if result.respond_to?(:session_id) && result.session_id
  puts fields.join(" ")
  warn result.error if result.respond_to?(:error) && result.error
end

def run_action(agent, action, arguments)
  case action
  when "reset"
    puts "session_id=#{agent.reset.session_id}"
  when "handoff-create"
    handoff = agent.create_browser_handoff(
      extension_id: ENV.fetch("AUTOHAND_EXTENSION_ID", nil),
      install_url: ENV.fetch("AUTOHAND_INSTALL_URL", nil)
    )
    puts "url=#{handoff.url} expires_at=#{handoff.expires_at}"
  when "handoff-attach"
    token = arguments.fetch(0) { abort USAGE }
    print_operation(agent.attach_browser_handoff(token))
  when "handoff-attach-latest"
    print_operation(agent.attach_latest_browser_handoff)
  when "automode-start"
    prompt = arguments.join(" ")
    abort USAGE if prompt.empty?

    print_operation(
      agent.start_automode(prompt, max_iterations: 10, use_worktree: true)
    )
  when "automode-status"
    status = agent.get_automode_status
    puts "active=#{status.active?} paused=#{status.paused?} state=#{status.state.inspect}"
  when "automode-pause"
    print_operation(agent.pause_automode)
  when "automode-resume"
    print_operation(agent.resume_automode)
  when "automode-cancel"
    print_operation(agent.cancel_automode(reason: arguments.first))
  when "automode-log"
    log = agent.get_automode_log(limit: arguments.first&.then { |limit| Integer(limit) })
    print_operation(log)
    log.iterations.each { |entry| puts entry.inspect }
  else
    abort USAGE
  end
end

action = ARGV.shift || abort(USAGE)
cwd = ENV.fetch("AUTOHAND_CWD", ".")

AutohandSDK::Agent.open(cwd: cwd) do |agent|
  run_action(agent, action, ARGV)
end
