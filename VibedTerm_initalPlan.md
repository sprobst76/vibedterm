Alles klar. Hier ist ein **umsetzbarer Entwicklungsplan in Stufen** (mit klaren Deliverables, Akzeptanzkriterien, Architektur-Entscheidungen und Codex-Tasks), damit du das Projekt sauber „vibe-coden“ kannst, ohne dich früh in OAuth/Sync-Konflikten zu verlieren.

# Gesamtziel

Flutter-App für **Windows, Linux, Android**:

* SSH Terminal (Tabs/Sessions)
* Hosts/Profiles
* Keys/Secrets in **verschlüsseltem Vault**
* **Sync** via OneDrive/Google Drive **konfigurierbar**
* Fokus: stabil, sicher, wartbar

---

# Leitentscheidung (macht das Projekt 5× einfacher)

**Sync zuerst als „Vault-Datei im Sync-Ordner“**:

* User wählt einen Pfad (z. B. `OneDrive/.../ssh_vault.vlt` oder Drive-Ordner)
* OneDrive/Google Drive synchronisiert die Datei selbst (Desktop über Client, Android über Drive/OneDrive App + „Offline/Sync“ je nach Lösung)

**Später** (Stage 6+) optional: native API-Sync über Graph/Drive API mit OAuth + Konfliktlösung.

---

# Repo-Struktur (von Anfang an so anlegen)

Monorepo mit Packages (Flutter `melos` empfohlen, aber optional):

```
/apps/ssh_client_app          # Flutter UI
/packages/core_vault          # Vault-Format, Crypto, Datenmodelle
/packages/core_sync           # Sync-Abstraktion (file-based zuerst)
/packages/core_ssh            # SSH session mgmt (dartssh2 wrapper)
/packages/ui_terminal         # Terminal widget wrapper (xterm)
```

---

# Entwicklungsstufen

## Stage 0 — Projektgrundlage (1–2 Tage)

**Ziel:** Build läuft auf Win/Linux/Android, CI/Format/Tests stehen.

**Deliverables**

* Flutter App + Desktop Targets aktiviert
* `analysis_options.yaml` + linting
* minimaler Navigator + Theme
* Dummy Screens: Vault Unlock / Host List / Terminal

**Akzeptanzkriterien**

* `flutter run -d windows`, `-d linux`, `-d <android>` funktioniert
* Basic Navigation und State läuft

**Codex Tasks**

* Scaffold monorepo/packages
* CI (GitHub Actions) optional: `flutter test` + `flutter analyze`

---

## Stage 1 — Vault v1: Datenmodell + Verschlüsselung (kritisch)

**Ziel:** Ein verschlüsselter „Vault als Datei“ mit sauberem Format.

**Vault-Format (empfohlen)**

* Header (Magic, Version, KDF params, salt, nonce)
* Payload: JSON/CBOR (Hosts, Keys, Snippets, Settings)
* Crypto: **AES-256-GCM** oder **XChaCha20-Poly1305**
* KDF: **Argon2id** (oder scrypt wenn Argon2 schwierig)

**Deliverables**

* `core_vault` Package:

  * `VaultFile.create(path, masterPassword)`
  * `VaultFile.open(path, masterPassword)`
  * `VaultFile.save()`
  * CRUD: Hosts, Identities(Keys), Snippets, Settings
* Unit Tests: roundtrip create→save→open→verify

**Akzeptanzkriterien**

* Falsches Passwort → definierter Fehler
* Dateiinhalt ist nicht als JSON lesbar (wirklich encrypted)
* Versioning vorbereitet (v1)

**Codex Tasks**

* Implementiere `VaultHeader` + `VaultCrypto`
* Tests für KDF params, nonces, tamper detection (GCM tag)

---

## Stage 2 — Secrets Handling: OS Keystore optional (Komfort)

**Ziel:** Masterpasswort nicht jedes Mal tippen müssen (optional).

**Deliverables**

* `core_vault` erweitert:

  * „Remember on this device“ → speichere *wrapped* vault key im Secure Storage
* Plattform:

  * Android: Keystore via `flutter_secure_storage`
  * Windows/Linux: ebenfalls `flutter_secure_storage` (oder Secret Service); fallback: kein remember

**Akzeptanzkriterien**

* Ohne remember: Passwort immer nötig
* Mit remember: App kann Vault entsperren (nach Device Unlock/biometric optional später)

---

## Stage 3 — Hosts UI + Key Import (nutzbares Produkt)

**Ziel:** Hostliste + Profile + Schlüssel importieren, alles im Vault.

**Deliverables**

* Screens:

  * Vault auswählen/erstellen
  * Hostliste (Filter/Tags)
  * Host Editor (Host, Port, User, Auth: password/key, optional jump host)
  * Key Import (Paste PEM / Datei import) + optional Passphrase
* Validierungen (Port, Host, user)
* Suchfeld

**Akzeptanzkriterien**

* Host hinzufügen → App Neustart → Host weiterhin da (im Vault)
* Key importiert → wird im Vault gespeichert

---

## Stage 4 — SSH Core + Terminal MVP (erstes SSH)

**Ziel:** Verbindung herstellen und Terminal anzeigen.

**Deliverables**

* `core_ssh`:

  * `SshConnectionManager` (connect/disconnect)
  * Keepalive
  * Error mapping (auth failed, host unreachable, timeout)
* `ui_terminal`:

  * Terminal Widget (xterm)
  * Copy/Paste
  * „Extra Key Row“ auf Android (Esc/Ctrl/Tab/Arrows)

**Akzeptanzkriterien**

* SSH connect zu deinem VPS klappt
* Terminal I/O stabil, Resize funktioniert
* Disconnect sauber

---

## Stage 5 — Multi-Session: Tabs, Session Persist (Termius-Gefühl)

**Ziel:** Tabs / mehrere Sessions.

**Deliverables**

* Tabs UI (oben/unten)
* Session list, reconnect button
* Optional: “Quick Connect” Palette (Ctrl+K)

**Akzeptanzkriterien**

* 2 Hosts parallel geöffnet
* Tabwechsel ohne Crashes
* Memory leak check (basic)

---

## Stage 6 — File-based Sync v1 (praktisch & schnell)

**Ziel:** Vault liegt in OneDrive/Drive Ordner → App erkennt Änderungen.

**Mechanik**

* File watcher (Desktop) + Polling fallback (Android)
* `lastModified` + `revision` in Vault-Metadata
* Bei Remote-Change: „Reload vault?“ Dialog (oder auto)

**Deliverables**

* Settings:

  * Vault path picker
  * Sync mode: manual / auto
* Sync status indicator

**Akzeptanzkriterien**

* Du änderst Host auf Windows → nach Sync → Android sieht Änderung nach „Reload“
* Konfliktfall: wenn beide geändert → App erkennt Divergenz und warnt

---

## Stage 7 — Konfliktlösung (Merge Wizard)

**Ziel:** Wenn zwei Geräte gleichzeitig ändern, nicht Daten verlieren.

**Vorschlag**

* Vault enthält:

  * `revision` (increment)
  * `deviceId`
  * optional `changeLog` (nur Metadaten)
* Konflikt UI:

  * Hosts & Snippets: mergebar (feldweise / latest)
  * Keys: meist „choose one“ oder „keep both“ (duplizieren mit suffix)

**Deliverables**

* `VaultMergeEngine`
* Konflikt Screen

**Akzeptanzkriterien**

* Simulierter Konflikt → Nutzer kann korrekt mergen → keine Daten weg

---

## Stage 8 — SFTP v1 (Quality-of-life)

**Ziel:** Dateien hoch/runter.

**Deliverables**

* SFTP Browser pro Session
* Upload/download
* Permissions basics

**Akzeptanzkriterien**

* Datei nach `/tmp` hochladen, wieder runterladen

---

## Stage 9 — Advanced Networking: Jump Host, Port Forwarding

**Ziel:** Pro-Features.

**Deliverables**

* Jump Host / Bastion chain (mind. 1 hop)
* Port forwarding:

  * Local forward
  * Dynamic (SOCKS) optional

**Akzeptanzkriterien**

* Verbindung über Bastion klappt
* Local forward zu internem Dienst funktioniert

---

## Stage 10 — Native Cloud Sync Provider (optional „hard mode“)

**Ziel:** OneDrive/Google Drive direkt per API (ohne Sync-Ordner).

**Deliverables**

* OAuth flows
* Provider:

  * `OneDriveProvider` (Graph)
  * `GDriveProvider`
* Lock/Lease (best effort)
* Delta sync (optional)

**Akzeptanzkriterien**

* Login → Vault list → download/upload
* Konflikte sauber behandelt

---

# „Definition of Done“ pro Stage (für Codex)

Jede Stage bekommt:

* ✅ Unit Tests (mind. core_vault & merge)
* ✅ `README.md` Update (How to run + stage notes)
* ✅ Demo-Skript (z. B. `scripts/demo_stage_4.md`)

---

# Codex-Workflow: so gibst du Aufgaben

Für jede Stage arbeitest du in kleinen PR-artigen Häppchen:

**Beispiel Prompt an Codex**

* “Implement `core_vault` with AES-GCM encryption, file header, Argon2id KDF, and roundtrip tests. Follow this vault spec: …”
* “Add Vault CRUD for Hosts + Identities. Provide models, validation, and migration v1→v2 scaffold.”
* “Implement SshConnectionManager using dartssh2 and integrate xterm widget; add Android extra keys row.”

Ich kann dir auch direkt eine **`docs/plan.md`** Vorlage formulieren, die du 1:1 ins Repo legst, inkl. Task-Checkboxen pro Stage.

---

# Wichtigste Risiken (damit du nicht in Sackgassen läufst)

* **Terminal UX auf Android** (Keyboard, Ctrl/Alt) → früh testen (Stage 4)
* **Linux Keystore** ist nicht überall verfügbar → optional machen, fallback auf Passwort
* **Vault Crypto**: lieber simpel & korrekt als “clever”
* **Native Cloud Sync** erst ganz am Ende (Stage 10), sonst frisst OAuth deine Zeit

---

Wenn du willst, erstelle ich dir als nächsten Schritt:

1. eine **Vault-Spezifikation v1** (Headerfelder, KDF Params, Beispiel in Hex/Base64)
2. eine **Codex-Taskliste als Issues** (Stage 0–6) mit Akzeptanzkriterien
3. ein minimales **Repo-Skeleton** (Ordnerstruktur + leere Packages + CI) als „Paste-ready“ Struktur.
