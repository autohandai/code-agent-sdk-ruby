# Changelog

## Unreleased

- Added current CLI runtime flags, feature settings, slash-command helpers, and persistent-goal RPC methods.
- Added the complete replayable autoresearch lifecycle: start, status, pause, history, replay, rescore, compare, Pareto, pin, and prune.
- Added autoresearch notifications and hook names, richer turn-usage aliases, documentation, and a runnable ledger example.

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `autohand-sdk` executable with `doctor`, `cli-path`, and `install-cli` commands.
- `AutohandSDK::CLIInstaller` for platform CLI discovery and user-level CLI installation.
- GitHub Actions release workflow for RubyGems Trusted Publishing.

## [0.1.0] - 2026-05-09

### Added

- Initial beta Ruby SDK for the Autohand Code CLI JSON-RPC mode.
- `AutohandSDK::Client` low-level subprocess and RPC client.
- `AutohandSDK::Agent` and `AutohandSDK::Run` high-level API.
- Streaming events through Ruby enumerators and block APIs.
- Permission, plan-mode, model, context, MCP, hooks, and account helper methods.
- Structured JSON output helpers.
- Optional Rails Railtie.
- Minitest coverage, RuboCop configuration, YARD setup, examples, and documentation.

### Security

- RubyGems MFA metadata is enabled in the gemspec.
