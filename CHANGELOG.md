# Changelog

## Unreleased

- Terminal tab can load saved vault hosts to prefill connection details.
- SSH connections now prompt for host-key verification and remember trusted fingerprints in the vault metadata.
- Vault service exposes helpers to read/write trusted host keys; vault payload updates bump revision/updatedAt.
- SSH core supports host-key verification callbacks with formatted fingerprints for UI prompts.
- Terminal tab offers an experimental interactive shell powered by xterm, with host-selected connections and quick commands.
- Connection form supports supplying a private-key passphrase.
