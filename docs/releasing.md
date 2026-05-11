# Releasing

This gem publishes through RubyGems Trusted Publishing from GitHub Actions.

## One-Time RubyGems Setup

Run the trusted-publisher setup helper:

```bash
bundle exec rake release:trusted_publisher
```

This runs the RubyGems-maintained `configure_trusted_publisher` helper for:

- Repository: `autohandai/code-agent-sdk-ruby`
- Workflow: `.github/workflows/release.yml`
- Environment: `release`

Choose the tag-based release option when prompted. You will still enter RubyGems credentials and MFA once; that owner authorization is the security boundary. After that, GitHub Actions uses short-lived OIDC tokens and no long-lived RubyGems API key is stored in this repository.

If RubyGems asks for an OTP separately, pass it as an environment variable:

```bash
RUBYGEMS_OTP=123456 bundle exec rake release:trusted_publisher
```

Keep MFA enabled on the RubyGems owner accounts. Trusted Publishing removes the need for a long-lived API key in GitHub secrets.

## Release Steps

1. Update `lib/autohand_sdk/version.rb`.
2. Move `CHANGELOG.md` entries from `Unreleased` into the new version section.
3. Run the release checks:

```bash
bundle exec rake
bundle exec yard
gem build autohand_sdk.gemspec
bundle exec rake package:verify
```

4. Commit the version and changelog changes.
5. Create and push the release tag:

```bash
bundle exec rake release:tag
```

The task verifies the working tree is clean, runs tests, runs YARD, builds the gem, verifies the package executable, creates the annotated `vVERSION` tag, and pushes it. The release workflow then rebuilds from the tag and publishes to RubyGems.

## CLI Installer

The Ruby gem stays small. It does not vendor every Autohand Code CLI binary into the main gem.

Users install the platform CLI with:

```bash
bundle exec autohand-sdk install-cli
```

By default the installer downloads the current platform asset from:

```text
https://github.com/autohandai/code-cli/releases/latest/download
```

Override the release source when testing a prerelease:

```bash
AUTOHAND_CLI_RELEASE_BASE_URL=https://github.com/autohandai/code-cli/releases/download/v0.9.0 \
  bundle exec autohand-sdk install-cli --force
```

The SDK discovers the CLI in this order:

1. Explicit `cli_path:`.
2. A platform binary bundled inside `cli/` for custom/private bundles.
3. `~/.autohand/bin/autohand`.
4. `autohand` on `PATH`.
5. The platform binary name on `PATH`.
