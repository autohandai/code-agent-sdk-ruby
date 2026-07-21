# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Immutable typed skill-registry lookup and skill-installation results.
- Immutable typed MCP server, tool, and server-configuration discovery results.
- Current CLI runtime flags, feature settings, slash-command helpers, and persistent-goal RPC methods.
- The complete replayable autoresearch lifecycle and normalized notifications.
- Typed conversation reset through `reset`, returning the replacement session ID.
- Expiring browser handoffs through `create_browser_handoff`, `attach_browser_handoff`, and
  `attach_latest_browser_handoff`.
- Typed auto-mode control through `start_automode`, `get_automode_status`, `pause_automode`,
  `resume_automode`, `cancel_automode`, and `get_automode_log`.
- Typed events for all 16 `autohand.hook.*` notifications, with exact raw-params fallback for
  unknown and malformed notifications.
- A committed 5-warmup/50-sample startup performance gate with stable nested JSON output.
- `autohand-sdk` executable with `doctor`, `cli-path`, and `install-cli` commands.
- `AutohandSDK::CLIInstaller` for platform CLI discovery and user-level CLI installation.
- GitHub Actions release workflow for RubyGems Trusted Publishing.

### Fixed

- Removed the fixed 50 ms transport startup sleep while retaining the readiness RPC.
- Treated prompt responses as acknowledgements and streamed through terminal `agent_end` notifications.
- Aborted and drained prompts when enumerators stop early, with fresh-generation fallback on cleanup failure.
- Propagated high-level `Agent` and `Run` stream abandonment through their background pump without cancelling shared consumers.
- Bounded prompt and global event queues while preserving independent subscriber copies.
- Failed pending requests, closed event streams, and reaped live children when CLI stdout reaches clean EOF.
- Serialized transport lifecycle and writes so concurrent starts, requests, stops, and restarts cannot cross generations.
- Scoped the optional Rails Railtie autoload under `AutohandSDK`.
- Rolled back partially started clients when plan-mode or feature configuration fails.
- Lazy-loaded public constants so requiring the gem does not eagerly load transport and installer dependencies.
- Replaced the benchmark's Ruby child fixture with a compile-once native RPC fixture, removing interpreter-start variance from wrapper startup measurements.

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
