# Changelog

## Unreleased

- Terminal tab can load saved vault hosts to prefill connection details.
- SSH connections now prompt for host-key verification and remember trusted fingerprints in the vault metadata.
- Vault service exposes helpers to read/write trusted host keys; vault payload updates bump revision/updatedAt.
- SSH core supports host-key verification callbacks with formatted fingerprints for UI prompts.
- Terminal tab offers an experimental interactive shell (basic text stream with send input) alongside quick commands.
