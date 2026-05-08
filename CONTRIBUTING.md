# Contributing

Thank you for helping improve the Ruby SDK. This gem is intentionally small and Ruby-first: prefer explicit APIs, stdlib runtime dependencies, tight tests, and documentation that shows real usage.

## Local setup

```bash
bundle install
bundle exec rake
bundle exec yard
```

## Guidelines

- Keep runtime dependencies out unless the feature cannot be implemented cleanly with stdlib.
- Add tests for public API changes and transport edge cases.
- Preserve string-keyed event hashes because they mirror JSON-RPC payloads and avoid surprising key conversions.
- Keep Rails integration optional. Do not require Rails or ActiveSupport from the main entrypoint.
- Update README, `docs/`, examples, and CHANGELOG when changing public behavior.

## Release checklist

1. Update `lib/autohand_sdk/version.rb`.
2. Update `CHANGELOG.md`.
3. Run `bundle exec rake`.
4. Run `bundle exec yard`.
5. Build with `gem build autohand_sdk.gemspec`.
6. Publish with RubyGems MFA enabled.
