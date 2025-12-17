# VibedTerm

Flutter-based SSH client targeting Windows, Linux, and Android with an encrypted vault and optional file-based sync via user-chosen OneDrive/Google Drive folders.

## Docs

- Project plan: `docs/plan.md`
- Changelog: `CHANGELOG.md`

## Repo layout (skeleton)

- `apps/ssh_client_app` — Flutter app entry point
- `packages/core_vault` — vault format, crypto, data models
- `packages/core_sync` — sync abstraction (file-based first)
- `packages/core_ssh` — SSH session management
- `packages/ui_terminal` — terminal widget integration

Melos configuration is provided (`melos.yaml`) for future package orchestration.

## Running

From repo root:

```bash
flutter analyze
flutter test packages/core_vault
flutter test packages/core_ssh
```

App: `cd apps/ssh_client_app && flutter run -d <device>`

## Current UI status

- Vault tab: create/unlock vaults; stores hosts/identities.
- Hosts tab: manage hosts and identities saved in the vault.
- Terminal tab: pick a saved host or enter details manually, connect/disconnect, run quick commands, view logs. On first connect it prompts to trust the host key (fingerprint shown) and persists acceptance in vault metadata for reuse.
