# Getting Started

## Requirements

- Ruby 3.2 or newer.
- Bundler.

## Install

```ruby
gem "autohand_sdk", git: "https://github.com/autohandai/code-agent-sdk-ruby"
```

```bash
bundle install
```

Install the Autohand Code CLI:

```bash
bundle exec autohand-sdk install-cli
bundle exec autohand-sdk doctor
```

The installer downloads the correct platform binary from the Autohand Code CLI GitHub release and installs it into `~/.autohand/bin`.

## First Run

```ruby
require "autohand_sdk"

AutohandSDK::Client.open(cwd: ".") do |sdk|
  sdk.stream_prompt("Explain this repository in three bullets").each do |event|
    print event["delta"] if event["type"] == "message_update"
  end
end
```

Use `cli_path:` during local CLI development:

```ruby
AutohandSDK::Client.open(cli_path: "/path/to/autohand", cwd: ".") do |sdk|
  puts sdk.get_state
end
```

## High-Level Agent API

```ruby
agent = AutohandSDK::Agent.create(
  cwd: ".",
  instructions: "Prefer minimal, well-tested Ruby changes.",
  permission_mode: "interactive"
)

result = agent.run("Find the highest-risk release blockers")
puts result.fetch(:text)
agent.close
```

Prefer `.open` when the client should always close:

```ruby
AutohandSDK::Agent.open(cwd: ".") do |agent|
  puts agent.run("Summarize the current git diff").fetch(:text)
end
```
