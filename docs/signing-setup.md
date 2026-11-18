# Signing

Local testing does not need notarization. `Scripts/build-release.sh` signs with `SIGN_IDENTITY` if you set it, then a Developer ID Application identity, then any codesigning identity whose Team ID is `39Q4M52XNQ`. If none of those exist, it ad-hoc signs.

Do not commit the certificate, the private key, or a `.p12`. The public team ID in the helper policy is `39Q4M52XNQ`.

## Public distribution

Notarized releases need a Developer ID Application certificate and these GitHub Actions secrets:

| Secret | What it is |
|---|---|
| `MACOS_CERTIFICATE` | base64 of the `.p12` |
| `MACOS_CERTIFICATE_PWD` | password for that `.p12` |
| `MACOS_KEYCHAIN_PWD` | throwaway keychain password |
| `APPLE_ID` | Apple ID used by `notarytool` |
| `APPLE_TEAM_ID` | 10-character Team ID |
| `APPLE_APP_PASSWORD` | app-specific password |

```bash
base64 < certificate.p12 | pbcopy
```

Paste that into `MACOS_CERTIFICATE`. An Apple Development certificate cannot notarize.
