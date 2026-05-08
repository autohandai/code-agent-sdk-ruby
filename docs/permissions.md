# Permissions

Set the default mode at startup:

```ruby
sdk = AutohandSDK::Client.new(permission_mode: "interactive")
```

Change it during a session:

```ruby
sdk.set_permission_mode("unrestricted")
```

When the CLI emits a `permission_request`, respond with one of the helper methods:

```ruby
sdk.stream_prompt("Apply the migration").each do |event|
  next unless event["type"] == "permission_request"

  if event["tool"] == "bash"
    sdk.allow_permission(event["request_id"], scope: :once)
  else
    sdk.deny_permission(event["request_id"], scope: :session)
  end
end
```

Scopes:

- `:once` - only this request.
- `:session` - this CLI session.
- `:project` - persist for the project.
- `:user` - persist for the user.

For a safer alternative:

```ruby
sdk.suggest_permission_alternative(event["request_id"], "bundle exec rake test")
```
