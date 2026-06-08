# Tauri Updater Signing Keypair Setup

## Generate keypair

```powershell
tauri signer generate -w ~/.tauri/riptide.key
```

This outputs:
- Private key (PEM) → save to `~/.tauri/riptide.key`
- Public key → paste into `tauri.conf.json` → `plugins.updater.pubkey`

## GitHub Secrets

Add to the repo's GitHub Actions secrets:
- `TAURI_SIGNING_PRIVATE_KEY` — contents of `~/.tauri/riptide.key`
- `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` — passphrase (if set)

## Update tauri.conf.json

Replace the placeholder pubkey:
```json
"plugins": {
  "updater": {
    "pubkey": "YOUR_PUBLIC_KEY_HERE",
    "endpoints": ["https://releases.riptide.app/{{target}}/{{arch}}/{{current_version}}"]
  }
}
```

## CI Integration

The `release.yml` workflow already passes `TAURI_SIGNING_PRIVATE_KEY` to `tauri build`.
Once the secret is set, releases will include `latest.json` + `.sig` files.

## Verify

1. `npm run tauri build` locally
2. Check `src-tauri/target/release/bundle/nsis/` for `.sig` files
3. Check `src-tauri/target/release/bundle/nsis/latest.json` exists
