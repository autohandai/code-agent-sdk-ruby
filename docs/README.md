# Documentation

The Ruby SDK is a thin, explicit wrapper around the Autohand Code CLI JSON-RPC mode. Start with:

- [Getting Started](getting-started.md)
- [API Reference](API_REFERENCE.md)
- [Configuration](configuration.md)
- [Event Streaming](event-streaming.md)
- [Error Handling](error-handling.md)
- [Permissions](permissions.md)
- [Plan Mode](plan-mode.md)
- [Rails Integration](rails.md)
- [Advanced Patterns](advanced-patterns.md)
- [SDLC Workflows](sdlc-workflows.md)

The public API favors predictable Ruby: block forms for lifecycle cleanup, `Enumerator` for streams, explicit permission helpers, and string-keyed event hashes that mirror JSON-RPC payloads.

Maintainers can run `bundle exec ruby benchmarks/startup.rb` for the fixed
5-warmup/50-sample p95 <50 ms gates covering public require, public client
start, and fixture spawn through the first successful `autohand.getState`.
The benchmark compiles its deterministic native RPC fixture once before
sampling, excluding unrelated child Ruby VM startup from the SDK budget.
The JSON output reports `language`, `budgetMs`, nested `metrics`, and overall
`passed`; each metric contains `samples`, `medianMs`, `p95Ms`, `maxMs`, and
`passed`.
