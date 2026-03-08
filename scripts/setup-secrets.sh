#!/bin/bash
# Run once locally to export your signing certificate and push all
# required secrets to GitHub. Requires: gh CLI (brew install gh), openssl.
#
# Usage:
#   chmod +x scripts/setup-secrets.sh
#   ./scripts/setup-secrets.sh

set -e

TEAM_ID="T569L7X7QJ"

# ── Helpers ──────────────────────────────────────────────────────────────────

ok()   { echo "✅ $*"; }
info() { echo "   $*"; }
fail() { echo "❌ $*"; exit 1; }
hr()   { echo "────────────────────────────────────────"; }

# ── Preflight checks ─────────────────────────────────────────────────────────

hr
echo "Clipp – GitHub Secrets Setup"
hr

command -v gh   >/dev/null 2>&1 || fail "gh CLI not found. Install: brew install gh"
command -v openssl >/dev/null 2>&1 || fail "openssl not found. Install: brew install openssl"

gh auth status >/dev/null 2>&1 || fail "Not authenticated with gh. Run: gh auth login"

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) \
  || fail "Could not detect GitHub repo. Are you inside the repo directory?"
ok "Repo: $REPO"

# ── 1. Developer ID Application certificate ──────────────────────────────────

echo ""
echo "── Certificate ──"

CERT_LINE=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1)

if [ -z "$CERT_LINE" ]; then
  echo ""
  echo "❌ No Developer ID Application certificate found in your keychain."
  echo ""
  echo "   Create one first (one-time GUI step):"
  echo "   Xcode → Settings → Accounts → select your Apple ID"
  echo "   → Manage Certificates → + → Developer ID Application"
  echo ""
  exit 1
fi

CERT_NAME=$(echo "$CERT_LINE" | sed 's/.*"\(.*\)"/\1/')
ok "Found: $CERT_NAME"

# Generate random passwords (never leave your machine)
P12_PASSWORD=$(openssl rand -hex 24)
KEYCHAIN_PASSWORD=$(openssl rand -hex 24)

TMP_P12=$(mktemp /tmp/clipp_cert.XXXXXX.p12)

# Export the Developer ID identity (cert + private key) as .p12
security export \
  -k ~/Library/Keychains/login.keychain-db \
  -t identities \
  -f pkcs12 \
  -P "$P12_PASSWORD" \
  -o "$TMP_P12" 2>/dev/null

CERT_BASE64=$(base64 -i "$TMP_P12")
rm "$TMP_P12"
ok "Certificate exported and base64-encoded"

# ── 2. Apple ID credentials ───────────────────────────────────────────────────

echo ""
echo "── Apple ID ──"
echo "   Get an app-specific password at: appleid.apple.com"
echo "   → Sign-In & Security → App-Specific Passwords → Generate"
echo ""
printf "   Apple ID (email): "
read -r APPLE_ID_INPUT

printf "   App-Specific Password: "
read -rs APPLE_ID_PASS_INPUT
echo ""

[ -z "$APPLE_ID_INPUT" ]      && fail "Apple ID cannot be empty"
[ -z "$APPLE_ID_PASS_INPUT" ] && fail "App-specific password cannot be empty"

# ── 3. Sparkle private key ────────────────────────────────────────────────────

echo ""
echo "── Sparkle Update Signing Key ──"
echo "   The app's Info.plist already contains a SUPublicEDKey."
echo "   You need the matching private key to sign update packages."
echo ""
echo "   If you don't have it yet, generate a new key pair:"
echo "   (this will print a new public + private key)"
echo ""
printf "   Generate new Sparkle key pair? [y/N]: "
read -r GEN_SPARKLE

if [[ "$GEN_SPARKLE" =~ ^[Yy]$ ]]; then
  # Try to find generate_keys from a previous Xcode build
  GENERATE_KEYS=$(find ~/Library/Developer/Xcode/DerivedData -name "generate_keys" 2>/dev/null | head -1)

  if [ -z "$GENERATE_KEYS" ]; then
    echo ""
    echo "   Sparkle tools not found in DerivedData. Downloading..."
    SPARKLE_VERSION="2.7.5"
    TMP_DIR=$(mktemp -d)
    curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
      -o "$TMP_DIR/sparkle.tar.xz"
    tar -xf "$TMP_DIR/sparkle.tar.xz" -C "$TMP_DIR"
    GENERATE_KEYS="$TMP_DIR/bin/generate_keys"
  fi

  echo ""
  echo "   ⚠️  IMPORTANT — copy both values below before continuing:"
  echo ""
  "$GENERATE_KEYS"
  echo ""
  echo "   → Paste the PUBLIC KEY into Maccy/Info.plist as SUPublicEDKey"
  echo "   → Paste the PRIVATE KEY below when prompted"
  echo ""
fi

printf "   Sparkle Private Key: "
read -rs SPARKLE_KEY_INPUT
echo ""

[ -z "$SPARKLE_KEY_INPUT" ] && fail "Sparkle private key cannot be empty"

# ── 4. Push all secrets to GitHub ─────────────────────────────────────────────

echo ""
echo "── Pushing secrets to GitHub ──"

gh secret set BUILD_CERTIFICATE_BASE64 --body "$CERT_BASE64"  --repo "$REPO"
ok "BUILD_CERTIFICATE_BASE64"

gh secret set P12_PASSWORD             --body "$P12_PASSWORD"  --repo "$REPO"
ok "P12_PASSWORD"

gh secret set KEYCHAIN_PASSWORD        --body "$KEYCHAIN_PASSWORD" --repo "$REPO"
ok "KEYCHAIN_PASSWORD"

gh secret set TEAM_ID                  --body "$TEAM_ID"       --repo "$REPO"
ok "TEAM_ID"

gh secret set APPLE_ID                 --body "$APPLE_ID_INPUT"       --repo "$REPO"
ok "APPLE_ID"

gh secret set APPLE_ID_PASSWORD        --body "$APPLE_ID_PASS_INPUT"  --repo "$REPO"
ok "APPLE_ID_PASSWORD"

gh secret set SPARKLE_PRIVATE_KEY      --body "$SPARKLE_KEY_INPUT"    --repo "$REPO"
ok "SPARKLE_PRIVATE_KEY"

# ── Done ──────────────────────────────────────────────────────────────────────

hr
echo ""
echo "🎉 All secrets are set for $REPO"
echo ""
echo "   Next: push a v* tag to trigger a signed, notarized release."
echo "   git tag v1.0.2 && git push origin v1.0.2"
echo ""
