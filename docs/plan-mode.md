# Plan Mode

Plan mode asks the CLI to stay in a read-only planning posture until you disable it.

```ruby
AutohandSDK::Client.open(cwd: ".", permission_mode: "plan") do |sdk|
  plan = sdk.stream_prompt("Plan the refactor for the billing job").map { |event| event["delta"] }.join
  puts plan

  sdk.disable_plan_mode
  sdk.stream_prompt("Apply the approved plan").each { |event| print event["delta"] if event["delta"] }
end
```

You can also control it explicitly:

```ruby
sdk.enable_plan_mode
sdk.disable_plan_mode
sdk.set_plan_mode(true)
```
