#!/bin/bash
# Scripts/sign-sparkle-update.sh
# Sparkle 2.x edDSA key generation and DMG signing helper.
# https://sparkle-project.org/

set -euo pipefail

# ---- Configuration ----
SPARKLE_VERSION="${SPARKLE_VERSION:-2.6.4}"
SPARKLE_RELEASE_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
KEY_DIR_DEFAULT="${HOME}/Keys"
PRIVATE_KEY_NAME="riptide-sparkle-ed25519.pem"
SPARKLE_TMP_DIR="$(mktemp -d -t riptide-sparkle-XXXXXX)"
FORCE=0

# ---- Styling (respects NO_COLOR) ----
if [ -z "${NO_COLOR:-}" ] && [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BOLD=''; NC=''
fi

# ---- Cleanup ----
cleanup() {
    rm -rf "$SPARKLE_TMP_DIR"
}
trap cleanup EXIT

# ---- Helpers ----
die() { echo -e "${RED}Error:${NC} $*" >&2; exit 1; }
warn() { echo -e "${YELLOW}Warning:${NC} $*" >&2; }
info() { echo -e "${GREEN}$*${NC}"; }
heading() { echo ""; echo -e "${BOLD}==========================================${NC}"; echo -e "${BOLD}$*${NC}"; echo -e "${BOLD}==========================================${NC}"; }

usage() {
    cat <<EOF
Usage: $0 <command> [args]

Commands:
  keygen [--force]        Generate edDSA keypair, save private key to ~/Keys/
  sign <dmg>              Sign a DMG using \$SPARKLE_PRIVATE_KEY
  help                    Show this message

Examples:
  $0 keygen               # generate new keypair (refuses overwrite)
  $0 keygen --force       # overwrite existing key (DESTRUCTIVE)
  $0 sign ./Riptide.dmg   # sign using \$SPARKLE_PRIVATE_KEY=<path>

Environment:
  SPARKLE_PRIVATE_KEY     Path to private key file (required for 'sign')
  SPARKLE_VERSION         Sparkle release to fetch (default: ${SPARKLE_VERSION})
  NO_COLOR                Disable ANSI color output

Filesystem:
  Default private key path: ${KEY_DIR_DEFAULT}/${PRIVATE_KEY_NAME}

Security model:
  - Private key NEVER leaves your machine except via GitHub Secrets.
  - Run 'keygen' ONCE on a secure machine, then copy the public key into
    Riptide.entitlements (SUPublicEDKey) and store the private key in the
    SPARKLE_PRIVATE_KEY GitHub Secret.
  - This script will refuse to overwrite an existing key without --force.
EOF
}

# Locate generate_keys + sign_update (vendored first, then downloaded).
fetch_sparkle_tools() {
    # Vendored: <repo>/.sparkle/bin/{generate_keys,sign_update}
    local repo_root
    repo_root="$(cd "$(dirname "$0")/.." && pwd)"
    local vendored="${repo_root}/.sparkle"
    if [ -x "${vendored}/bin/generate_keys" ] && [ -x "${vendored}/bin/sign_update" ]; then
        info "Using vendored Sparkle at ${vendored}"
        GENERATE_KEYS="${vendored}/bin/generate_keys"
        SIGN_UPDATE="${vendored}/bin/sign_update"
        return 0
    fi

    info "Fetching Sparkle ${SPARKLE_VERSION}..."
    (cd "$SPARKLE_TMP_DIR" && \
        curl -fsSL -o sparkle.tar.xz "$SPARKLE_RELEASE_URL") \
        || die "Failed to download Sparkle ${SPARKLE_VERSION} from ${SPARKLE_RELEASE_URL}
Hint: check the version at https://github.com/sparkle-project/Sparkle/releases"

    (cd "$SPARKLE_TMP_DIR" && tar -xf sparkle.tar.xz) \
        || die "Failed to extract Sparkle archive"

    GENERATE_KEYS="$(find "$SPARKLE_TMP_DIR" -name generate_keys -type f | head -1)"
    SIGN_UPDATE="$(find "$SPARKLE_TMP_DIR" -name sign_update -type f | head -1)"
    [ -n "$GENERATE_KEYS" ] && [ -n "$SIGN_UPDATE" ] \
        || die "Could not find generate_keys / sign_update in Sparkle archive"
    chmod +x "$GENERATE_KEYS" "$SIGN_UPDATE"
}

# ---- Commands ----

cmd_keygen() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --force) FORCE=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die "Unknown keygen argument: $1" ;;
        esac
    done

    local key_dir="${RIPTIDE_KEY_DIR:-$KEY_DIR_DEFAULT}"
    local priv_key="${key_dir}/${PRIVATE_KEY_NAME}"

    heading "Sparkle edDSA keypair generation"

    # Refuse to clobber without --force
    if [ -f "$priv_key" ] && [ $FORCE -eq 0 ]; then
        die "Private key already exists at ${priv_key}
Refusing to overwrite. Use --force to destroy and regenerate."
    fi

    if [ -f "$priv_key" ] && [ $FORCE -eq 1 ]; then
        warn "--force specified. Existing key at ${priv_key} will be DESTROYED."
        warn "Press Ctrl+C within 5 seconds to abort..."
        sleep 5
    fi

    mkdir -p "$key_dir"
    chmod 0700 "$key_dir" || warn "Could not chmod 0700 ${key_dir} (continuing)"

    fetch_sparkle_tools

    info "Generating keypair..."
    local output
    if ! output="$("$GENERATE_KEYS" -p "$priv_key" 2>&1)"; then
        echo "$output" >&2
        die "generate_keys failed"
    fi
    echo "$output" >&2

    # ed25519 public key: 32 raw bytes -> 43 base64 chars + '=' padding = 44 chars.
    local pub_key
    pub_key="$(printf '%s\n' "$output" | grep -E '^[A-Za-z0-9+/]{43}=$' | head -1 || true)"
    [ -n "$pub_key" ] || die "Could not extract public key from generate_keys output.
Above output did not contain a 44-char base64 string."

    # Lock down private key
    chmod 0600 "$priv_key" || warn "Could not chmod 0600 ${priv_key}"

    # Verify private key looks like a PEM
    if ! head -1 "$priv_key" | grep -q "BEGIN"; then
        die "Private key at ${priv_key} does not look like a PEM file (missing BEGIN marker).
Aborting — the key may be invalid; do NOT delete it without backup."
    fi

    heading "Keypair generated"
    echo "Private key:  ${priv_key}  (mode 0600)"
    echo ""
    echo -e "${GREEN}${BOLD}Public key (paste into Riptide.entitlements SUPublicEDKey):${NC}"
    echo ""
    echo "  ${pub_key}"
    echo ""
    heading "Next steps"
    echo "1. Edit Riptide.entitlements:"
    echo "     <key>SUPublicEDKey</key>"
    echo "     <string>${pub_key}</string>"
    echo ""
    echo "2. Add SPARKLE_PRIVATE_KEY to GitHub Secrets (Repository Settings → Secrets):"
    echo "     Name:  SPARKLE_PRIVATE_KEY"
    echo "     Value: absolute path to ${priv_key}"
    echo "     (the value is the PATH to the file, not the file contents)"
    echo ""
    echo "3. Back up the private key to a secure location OUTSIDE this repo:"
    echo "     cp ${priv_key} /secure/backup/"
    echo ""
    echo "4. The Resources/sparkle-pubkey.pem file is a stub for the public key record."
    echo "   Replace its body with:"
    echo ""
    echo "     -----BEGIN PUBLIC KEY-----"
    echo "     ${pub_key}"
    echo "     -----END PUBLIC KEY-----"
    echo ""
    echo "5. Commit the entitlements + Resources/sparkle-pubkey.pem changes. NEVER commit the private key."
}

cmd_sign() {
    [ $# -ge 1 ] || die "sign requires a DMG path. Usage: $0 sign <dmg>"
    local dmg="$1"
    shift

    [ -f "$dmg" ] || die "DMG not found: $dmg"

    if [ -z "${SPARKLE_PRIVATE_KEY:-}" ]; then
        die "SPARKLE_PRIVATE_KEY env var not set.
Set it to the PATH of the private key file (not the key contents).
Example: export SPARKLE_PRIVATE_KEY=\$HOME/Keys/${PRIVATE_KEY_NAME}"
    fi

    # Defensive checks: SPARKLE_PRIVATE_KEY must be a path to a file.
    [ -d "${SPARKLE_PRIVATE_KEY}" ] && die "SPARKLE_PRIVATE_KEY points to a directory, expected a file path: ${SPARKLE_PRIVATE_KEY}"
    [ -f "${SPARKLE_PRIVATE_KEY}" ] || die "Private key file not found: ${SPARKLE_PRIVATE_KEY}"

    # Heuristic: detect if user accidentally pasted key body instead of a path.
    case "${SPARKLE_PRIVATE_KEY}" in
        *PRIVATE*|*BEGIN*) die "SPARKLE_PRIVATE_KEY looks like key contents, not a path. Set it to the FILE PATH." ;;
    esac

    heading "Signing ${dmg}"
    info "Using private key: ${SPARKLE_PRIVATE_KEY}"

    fetch_sparkle_tools

    # sign_update defaults: writes <dmg>.signature next to <dmg>.
    # Delta is only produced when --delta-from is supplied; we don't force it here.
    local out_dir
    out_dir="$(dirname "$dmg")"
    "$SIGN_UPDATE" -f "$dmg" -s "$SPARKLE_PRIVATE_KEY" -o "$out_dir" || die "sign_update failed"

    local sig="${dmg}.signature"
    if [ -f "$sig" ]; then
        info "Signature:  ${sig}"
        echo ""
        echo "Signature contents (base64 edDSA):"
        cat "$sig"
        echo ""
    else
        die "sign_update did not produce expected ${sig}"
    fi

    local delta="${dmg}.delta"
    if [ -f "$delta" ]; then
        info "Delta:      ${delta}"
    else
        echo "(no delta produced — supply --delta-from <previous-dmg> in your release script if needed)"
    fi

    echo ""
    info "Done. Upload ${sig} to your appcast.xml feed entry."
}

# ---- Dispatch ----
cmd="${1:-}"
shift || true

case "$cmd" in
    keygen)  cmd_keygen  "$@" ;;
    sign)    cmd_sign    "$@" ;;
    help|-h|--help) usage ;;
    "")      usage; exit 1 ;;
    *)       echo "Unknown command: $cmd" >&2; usage; exit 1 ;;
esac
