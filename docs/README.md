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
