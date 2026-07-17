# Configuration

Configuration accepts Ruby-style snake case and common JSON-style camel case keys.

```ruby
AutohandSDK::Client.new(
  cwd: ".",
  cli_path: "/path/to/autohand",
  debug: true,
  timeout: 300_000,
  model: "openrouter/auto",
  permission_mode: "interactive",
  append_sys_prompt: "Prefer small commits."
)
```

## CLI and execution

| Option | Description |
| --- | --- |
| `cwd` | Working directory for the CLI subprocess. |
| `cli_path` | Explicit CLI executable path. |
| `debug` | Enables SDK debug logging. |
| `timeout` | RPC request timeout in milliseconds. |
| `extra_args` | Additional CLI args appended at startup. |
| `env_vars` | Environment variables forwarded to the subprocess. |
| `auto_commit` | Pass `-c` for automatic commits. |
| `agents_md_enable` | Pass `--agents-md` or `--no-agents-md`. |
| `agents_md_create` | Create AGENTS.md when missing. |
| `agents_md_path` | Use an explicit AGENTS.md path. |
| `agents_md_auto_update` | Allow CLI-managed AGENTS.md updates. |

CLI discovery order:

1. Explicit `cli_path`.
2. A platform binary bundled inside `cli/`.
3. `~/.autohand/bin/autohand`, installed by `bundle exec autohand-sdk install-cli`.
4. `autohand` on `PATH`.
5. The platform binary name on `PATH`, such as `autohand-macos-arm64`.

Use the bundled executable helpers to inspect or install the CLI:

```bash
bundle exec autohand-sdk cli-path
bundle exec autohand-sdk install-cli
bundle exec autohand-sdk doctor
```

Bundler and Ruby runtime variables such as `BUNDLE_GEMFILE`, `RUBYOPT`, `RUBYLIB`, `GEM_HOME`, and `GEM_PATH` are scrubbed before the CLI subprocess starts. This keeps Rails and Bundler apps from accidentally forcing Ruby-specific boot settings into the Autohand CLI process. Use `env_vars` for values you intentionally want to pass.

## Autohand AI provider

```ruby
AutohandSDK::Client.new(
  provider: "autohandai",
  api_key: ENV.fetch("AUTOHAND_AI_API_KEY"),
  autohand_ai_plan: "cloud"
)
```

The SDK maps `api_key`, optional `base_url`, and `autohand_ai_plan` to the
CLI's `AUTOHAND_AI_*` subprocess environment variables. Credentials are not
placed on the process command line.

## Agent behavior

| Option | Description |
| --- | --- |
| `model` | Model identifier passed to `--model`. |
| `temperature` | Sampling temperature, `0.0..2.0`. |
| `auto_mode` | Enables CLI auto-mode. |
| `unrestricted` | Starts CLI unrestricted mode. |
| `max_iterations` | Max auto-mode iterations. |
| `max_runtime` | Max runtime limit. |
| `max_cost` | Max cost limit. |
| `sys_prompt` | Replaces the default system prompt. |
| `append_sys_prompt` | Appends to the default system prompt. |

## Skills

```ruby
AutohandSDK::Client.new(
  skills: ["ruby", "./skills/security/SKILL.md"],
  auto_skill: true,
  install_missing_skills: true
)
```

Skill file paths are copied into `~/.autohand/skills/<name>/SKILL.md` by default. Set `copy_skill_files: false` to disable that behavior.

## Sessions and context

```ruby
AutohandSDK::Client.new(
  persist_session: true,
  session_id: "session_123",
  resume: true,
  context_compact: true,
  max_tokens: 200_000
)
```

Nested sections are also accepted:

```ruby
AutohandSDK::Client.new(
  session: { persist_session: true, resume: true },
  context: { context_compact: true, summarization_threshold: 0.8 }
)
```
