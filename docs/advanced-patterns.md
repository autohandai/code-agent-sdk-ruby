# Advanced Patterns

## Structured JSON

```ruby
result = agent.run_json(
  "List the files that need tests",
  schema_name: "TestPlan",
  schema: {
    summary: "string",
    files: [{ path: "string", reason: "string" }]
  },
  validate: ->(value) {
    raise "files must be an array" unless value["files"].is_a?(Array)

    value
  }
)
```

The parser accepts direct JSON, fenced JSON, and embedded JSON. Invalid output raises `AutohandSDK::StructuredOutputError` with the raw response.

## Skills

```ruby
sdk = AutohandSDK::Client.new(
  cwd: ".",
  skills: ["ruby", "./skills/release/SKILL.md"],
  auto_skill: true
)
```

Local skill files are copied into `~/.autohand/skills` before startup unless `copy_skill_files: false`.

## Sessions

```ruby
sdk = AutohandSDK::Client.new(
  cwd: ".",
  persist_session: true,
  session_id: "release-review",
  resume: true
)
```

## Hooks

```ruby
sdk.add_hook(
  event: "pre-tool",
  command: "echo tool starting",
  filter: { tool: ["bash"] }
)
```

## MCP Servers

```ruby
sdk.set_mcp_servers(
  "filesystem" => {
    "transport" => "stdio",
    "command" => "npx",
    "args" => ["-y", "@modelcontextprotocol/server-filesystem", Dir.pwd]
  }
)
```
