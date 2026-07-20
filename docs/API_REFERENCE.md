# API Reference

## `AutohandSDK.configure`

Sets process-level defaults for clients created through `AutohandSDK.client` or `AutohandSDK.agent`.

```ruby
AutohandSDK.configure do |config|
  config.cli_path = "/usr/local/bin/autohand"
  config.env_vars = { "AUTOHAND_NO_BANNER" => "1" }
end
```

## `AutohandSDK::Client`

Low-level session API around the CLI subprocess.

### `.open(config = nil, **options) { |client| ... }`

Starts a client, yields it, and closes it.

### `#start`, `#stop`, `#close`

Start and stop the CLI subprocess.

### `#stream_prompt(message_or_params, **options)`

Sends a prompt and returns an `Enumerator` of event hashes.

```ruby
sdk.stream_prompt("Review lib/autohand_sdk/client.rb").each do |event|
  puts event.inspect
end
```

### `#prompt(message_or_params, **options)`

Sends a prompt and returns the raw RPC result. Use `stream_prompt` for live output.

### `#abort(reason: nil)`

Aborts the current operation.

### `#reset`

Calls `autohand.reset` with an empty parameter object and returns an immutable
`AutohandSDK::ResetResult` with a snake_case `session_id`. `Agent` delegates the
same method.

### `#permission_response`

Responds to a permission request event.

```ruby
sdk.permission_response(request_id: event["request_id"], decision: "allow_once")
```

Convenience helpers:

- `#allow_permission(request_id, scope: :once)`
- `#deny_permission(request_id, scope: :once)`
- `#suggest_permission_alternative(request_id, alternative)`

Scopes are `:once`, `:session`, `:project`, and `:user`.

### Runtime control

- `#set_permission_mode(mode)`
- `#set_plan_mode(enabled)`
- `#enable_plan_mode`
- `#disable_plan_mode`
- `#set_model(model)`
- `#set_max_thinking_tokens(value)`
- `#apply_flag_settings(settings)`

### Information methods

- `#get_state(include_context: nil)`
- `#get_messages(limit: nil, before: nil)`
- `#supported_models`
- `#supported_commands`
- `#get_context_usage`
- `#account_info`

### Typed skill and MCP discovery

| Client method | Result type | Exact RPC method |
| --- | --- | --- |
| `#get_skills_registry(force_refresh: nil)` | `SkillsRegistryResult` | `autohand.getSkillsRegistry` |
| `#install_skill(name, scope:, force: nil)` | `InstallSkillResult` | `autohand.installSkill` |
| `#list_mcp_servers` | `McpServersResult` | `autohand.mcp.listServers` |
| `#list_mcp_tools(server_name: nil)` | `McpToolsResult` | `autohand.mcp.listTools` |
| `#get_mcp_server_configs` | `McpServerConfigsResult` | `autohand.mcp.getServerConfigs` |

The result objects and nested values are immutable Ruby `Data` instances.
Optional arguments are omitted from the JSON-RPC payload when not provided.
Install scope accepts only `:user` or `:project`. A valid `success: false`
response remains an `InstallSkillResult`; a JSON-RPC error raises `RPCError`.

`Agent` exposes all five methods through its normal client delegation.

### Slash commands and persistent goals

- `#stream_command(command, args = nil, **options)`
- `#supported_commands`
- `#supports_command?(command)`
- `#get_goal`
- `#create_goal(objective:, **budgets)`
- `#update_goal(**changes)`
- `#clear_goal`
- `#queue_goal(objective:, **budgets)`
- `#start_queued_goal`
- `#list_goal_templates`

Goal budget keys are sent in the CLI's snake-case RPC format: `token_budget`,
`time_budget_seconds`, `min_tokens_before_wrap_up`, and
`min_time_seconds_before_wrap_up`.

### Replayable autoresearch ledger

- `#start_autoresearch(objective:, **options)`
- `#get_autoresearch_status`
- `#stop_autoresearch`
- `#get_autoresearch_history`
- `#replay_autoresearch(attempt_id:, evaluator: nil)`
- `#rescore_autoresearch(attempt_id: nil, all: false)`
- `#compare_autoresearch(left_attempt_id:, right_attempt_id:)`
- `#get_autoresearch_pareto`
- `#pin_autoresearch(attempt_id:, pinned:)`
- `#prune_autoresearch(dry_run: nil, yes: nil)`

Ruby keyword names are converted recursively to the CLI's camel-case
autoresearch protocol. Results remain string-keyed hashes so evaluation,
decision, sample, Pareto, and retention data mirror the JSON-RPC response.
See [Replayable Autoresearch](autoresearch.md) for the full lifecycle.

### MCP and hooks

- `#list_mcp_servers`
- `#list_mcp_tools(server_name: nil)`
- `#get_mcp_server_configs`
- `#reconnect_mcp_server(server_name)`
- `#toggle_mcp_server(server_name, enabled)`
- `#set_mcp_servers(servers)`
- `#get_hooks`
- `#add_hook(hook)`
- `#remove_hook(event, index)`
- `#toggle_hook(event, index)`
- `#test_hook(hook)`
- `#set_hooks_settings(settings)`

## `AutohandSDK::Agent`

High-level run lifecycle API.

### `.create(config = nil, instructions: nil, **options)`

Creates and starts an agent.

### `#send(input, **options)`

Returns an `AutohandSDK::Run` without waiting.

### `#run(input, **options)`

Runs to completion and returns:

```ruby
{
  id: "run_...",
  status: "completed",
  text: "...",
  events: [...]
}
```

### `#run_json(input, schema_name: nil, schema: nil, output_instructions: nil, validate: nil, **options)`

Adds JSON-only instructions, waits for the run, parses the final response, and optionally validates it.

### `#stream(input, **options)`

Streams a run directly.

### Slash-command helpers

- `#command(command, args = nil, **options)` returns a `Run`.
- `#deep_research(topic, **options)` runs `/deep-research`.
- `#autoresearch(objective, **options)` runs `/autoresearch`.

All `AutohandSDK::Client` goal and autoresearch methods are also available on
`Agent` through delegation.

## `AutohandSDK::Run`

- `#stream` returns a replayable event enumerator. If its last active consumer
  exits early and no `#wait` caller is active, the run aborts and joins its
  background pump; other active consumers continue normally.
- `#wait` returns the final result hash.
- `#json(validate: nil)` parses the final text as JSON.
- `#abort` aborts the active run.

## `AutohandSDK::CLIInstaller`

Installs and locates the Autohand Code CLI used by the SDK.

### `.install!(install_dir: nil, force: false, release_base_url: nil)`

Downloads or copies the current platform CLI into `~/.autohand/bin` by default and returns an `InstallResult`.

```ruby
result = AutohandSDK::CLIInstaller.install!(force: true)
puts result.path
```

### `.detect!(explicit_path: nil)`

Returns the CLI executable path or raises `AutohandSDK::ConfigurationError` with an installation hint.

The command-line wrapper exposes the same behavior:

```bash
bundle exec autohand-sdk install-cli
bundle exec autohand-sdk cli-path
bundle exec autohand-sdk doctor
```
