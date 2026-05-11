# Code Agent SDK for Ruby

[![CI](https://github.com/autohandai/code-agent-sdk-ruby/actions/workflows/ci.yml/badge.svg)](https://github.com/autohandai/code-agent-sdk-ruby/actions/workflows/ci.yml)
[![Ruby](https://img.shields.io/badge/ruby-3.2%2B-red.svg)](https://www.ruby-lang.org/)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE.txt)

Autohand Code Agent SDK for Ruby: a CLI-backed Ruby gem for controlling Autohand Code agents over JSON-RPC, with streaming events, run lifecycle helpers, permissions, skills, sessions, hooks, and Rails-friendly configuration.

**Beta:** this SDK is actively evolving while the Agent SDK APIs stabilize. Pin versions in production and review release notes before upgrading.

## Overview

This SDK wraps the Autohand Code CLI in RPC mode and exposes a Ruby API for agentic coding workflows.

```text
Ruby app -> autohand_sdk gem -> Autohand Code CLI subprocess -> Provider -> HTTP
```

The gem:

- Starts the Autohand Code CLI as a subprocess in JSON-RPC mode.
- Streams agent lifecycle, message, tool, permission, and file-change events.
- Provides `AutohandSDK::Client` for low-level control and `AutohandSDK::Agent` / `Run` for application code.
- Keeps Rails optional through a Railtie that only loads when Rails is present.
- Uses Ruby stdlib for runtime behavior; development dependencies stay out of production installs.

## Other Programming Languages (Beta)

The Agent SDK is available in multiple beta language packages. Use the same CLI-backed SDK model from another programming language:

- [TypeScript](https://github.com/autohandai/code-agent-sdk-typescript) - `Agent`, `Run`, streaming, and JSON helpers for Node and Bun hosts.
- [Go](https://github.com/autohandai/code-agent-sdk-go) - idiomatic Go package with `context.Context`, typed events, and channel-based streaming.
- [Python](https://github.com/autohandai/code-agent-sdk-python) - async Python package with `async for` event streams and typed Pydantic models.
- [Java](https://github.com/autohandai/code-agent-sdk-java) - Java 21 records, sealed events, and virtual-thread-ready APIs.
- [Swift](https://github.com/autohandai/code-agent-sdk-swift) - SwiftPM package with `Agent`, `Runner`, async streams, tools, hooks, and permissions.
- [Rust](https://github.com/autohandai/code-agent-sdk-rust) - async Rust crate with Tokio, typed events, and stream-based runs.
- [C++](https://github.com/autohandai/code-agent-sdk-cpp) - modern C++20 package with CMake targets and typed event callbacks.
- [C#](https://github.com/autohandai/code-agent-sdk-csharp) - .NET package with `IAsyncEnumerable`, `CancellationToken`, and `System.Text.Json`.
- [Ruby](https://github.com/autohandai/code-agent-sdk-ruby) - this gem, with Ruby enumerators, block APIs, Rails-friendly configuration, and JSON helpers.

## Installation

Until the first RubyGems release is published, install from GitHub:

```ruby
# Gemfile
gem "autohand_sdk", git: "https://github.com/autohandai/code-agent-sdk-ruby"
```

After the gem is released to RubyGems:

```ruby
gem "autohand_sdk", "~> 0.1"
```

Then run:

```bash
bundle install
```

Install the Autohand Code CLI for this user:

```bash
bundle exec autohand-sdk install-cli
bundle exec autohand-sdk doctor
```

The Ruby gem stays small instead of vendoring every platform binary into one RubyGems package. The installer downloads the correct Autohand Code CLI release asset for macOS, Linux, or Windows and installs it into `~/.autohand/bin`. The SDK then discovers the CLI from `cli_path:`, a bundled `cli/` binary, `~/.autohand/bin/autohand`, or `PATH`.

Use `cli_path:` when you need a custom CLI build:

```ruby
AutohandSDK::Client.open(cli_path: "/path/to/autohand", cwd: ".") do |sdk|
  puts sdk.get_state
end
```

## Quick Start

Use `AutohandSDK::Agent` for application code:

```ruby
require "autohand_sdk"

agent = AutohandSDK::Agent.create(
  cwd: ".",
  instructions: "Review code with staff-level Ruby judgement.",
  permission_mode: "interactive"
)

run = agent.send("Review this repository for release readiness")

run.stream.each do |event|
  print event["delta"] if event["type"] == "message_update"
end

result = run.wait
puts result.fetch(:text)

agent.close
```

For one-shot tasks:

```ruby
result = agent.run("Summarize the public API surface")
puts result.fetch(:text)
```

For JSON output:

```ruby
risk = agent.run_json(
  "Assess publish readiness",
  schema_name: "ReleaseRisk",
  schema: {
    summary: "string",
    risks: [{ title: "string", severity: "low | medium | high" }]
  }
)

puts risk.fetch("summary")
```

## Low-Level Client

Use `AutohandSDK::Client` when you want explicit control over the CLI session:

```ruby
require "autohand_sdk"

AutohandSDK::Client.open(cwd: ".", debug: true) do |sdk|
  sdk.stream_prompt("Analyze this codebase").each do |event|
    case event["type"]
    when "message_update"
      print event["delta"]
    when "tool_start"
      warn "Running #{event["tool_name"] || event["toolName"]}"
    end
  end
end
```

## Rails

The gem does not depend on Rails. When Rails is loaded, the Railtie uses `Rails.logger` by default and leaves all configuration explicit:

```ruby
# config/initializers/autohand_sdk.rb
AutohandSDK.configure do |config|
  config.cli_path = Rails.application.credentials.dig(:autohand, :cli_path)
  config.env_vars = { "AUTOHAND_NO_BANNER" => "1" }
end
```

Use the client from jobs, controllers, or service objects with normal Rails lifecycle discipline:

```ruby
AutohandSDK::Client.open(cwd: Rails.root.to_s, permission_mode: "interactive") do |sdk|
  sdk.stream_prompt("Review app/models/user.rb").each { |event| Rails.logger.info(event.inspect) }
end
```

## Documentation

- [Getting Started](docs/getting-started.md)
- [API Reference](docs/API_REFERENCE.md)
- [Configuration](docs/configuration.md)
- [Releasing](docs/releasing.md)
- [Event Streaming](docs/event-streaming.md)
- [Error Handling](docs/error-handling.md)
- [Permissions](docs/permissions.md)
- [Plan Mode](docs/plan-mode.md)
- [Rails Integration](docs/rails.md)
- [Advanced Patterns](docs/advanced-patterns.md)
- [SDLC Workflows](docs/sdlc-workflows.md)

## Examples

- [Basic agent run](examples/01_basic_agent.rb)
- [Streaming query](examples/02_streaming_query.rb)
- [Permission handling](examples/03_permissions.rb)
- [Structured JSON output](examples/04_structured_json.rb)
- [Rails initializer](examples/05_rails_initializer.rb)

## Development

Use Ruby 3.3 locally:

```bash
bundle install
bundle exec rake
bundle exec yard
gem build autohand_sdk.gemspec
```

CI runs the test suite and RuboCop on Ruby 3.2, 3.3, and 3.4.

## License

Apache License 2.0. See [LICENSE.txt](LICENSE.txt).
