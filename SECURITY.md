# Security

Please report security issues privately instead of opening a public issue.

Email: support@autohand.ai

The SDK starts the Autohand Code CLI as a subprocess and forwards selected environment variables. Review `cli_path`, `env_vars`, permission mode, and workspace paths before using the SDK in a hosted service or multi-tenant environment.
