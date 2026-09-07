# Distribution

Clipp is distributed through [GitHub Releases](https://github.com/juanmaramos/clipp/releases). Release builds include Sparkle: users can enable automatic checks in **Settings → General**, or use **Check Now**.

## Homebrew

The application repository also serves as a custom tap:

```sh
brew trust --cask juanmaramos/clipp/clipp
brew tap juanmaramos/clipp https://github.com/juanmaramos/clipp.git
brew install --cask juanmaramos/clipp/clipp
```

The cask installs the same signed, notarized ZIP used by Sparkle. It declares `auto_updates true`; users who prefer to request an update through Homebrew can run:

```sh
brew update
brew upgrade --cask --greedy juanmaramos/clipp/clipp
```

The checked-in cask points to an existing published release. Publishing the next release updates its version and SHA-256 automatically. A source merge alone does not advertise an unavailable download. Normal uninstall keeps data; `brew uninstall --zap` also removes production history, pins, snippets, and preferences.

## Validation and publication are separate

- `.github/workflows/ci.yml` validates pull requests and pushes to main with the full unit-test target and a Release build.
- `.github/workflows/build.yml`, named **Publish release**, runs only through a manual workflow dispatch on main.
- Publishing requires the existing Developer ID, notarization, and Sparkle secrets in GitHub Actions.

Before publishing, increment `CURRENT_PROJECT_VERSION` in both build configurations and update `MARKETING_VERSION` and `CHANGELOG.md`. Production build numbers must increase regardless of how the app is built. Version 2.7.0 uses build 62, above the previously distributed local build 60 and public build 14. The release workflow rejects a build number that is not above the appcast version.

After validation, dispatch **Publish release** on main. The workflow:

1. Runs the full unit-test target.
2. Builds and signs with Developer ID and hardened runtime.
3. Notarizes, staples, and creates ZIP/DMG downloads and checksums.
4. Signs the ZIP with Sparkle’s EdDSA key.
5. Publishes `v<marketing-version>-build.<build-number>` and its downloads.
6. Updates `appcast.xml` and `Casks/clipp.rb` together, using the exact released ZIP.

Publishing is an explicit action; merging to main does not publish. The appcast-only loop protection is unnecessary for the manual release workflow.

## Existing installations and permissions

Clipp 2.7 is a Developer ID utility outside App Sandbox, because system-wide text replacement uses Accessibility APIs. Hardened runtime, code signing, notarization, and macOS privacy permissions remain in use. See [Apple’s sandbox restrictions](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox).

On upgrade, Clipp imports its old container preferences once, preserving newer explicit values, and opens an existing container database in place. It does not copy only the SQLite file or lose its WAL/external data. New installations store data in `~/Library/Application Support/Clipp`. If existing data cannot be read, the app offers Retry or Quit rather than silently opening an empty database.

Users enable typed expansion in Settings → Snippets, then allow Accessibility. Grant Input Monitoring only if the status asks for it. Permission status and links are shown there. Password fields, secure input, excluded apps, input-method composition, and unsupported text fields are skipped. Pasting a selected snippet uses the same keyboard-layout handling as history; typed expansion preserves the previous clipboard when no newer copy has replaced it.

## Development

Debug builds use `futurialabs.clipp.dev`, separate data/preferences, and no public updates. They are not release downloads. The unit-test plan uses an in-memory database and a private pasteboard and does not start the system-wide listener.

```sh
xcodebuild -project Maccy.xcodeproj -scheme Clipp -configuration Debug \
  -derivedDataPath /tmp/clipp-development -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  -only-testing:MaccyTests test
```

## Update signing validation

Before building, `scripts/check-update-key.swift` compares the public half of the existing CI signing key with `SUPublicEDKey`. After signing the ZIP, `scripts/verify-update.swift` verifies its signature against the shipped app's public key before any release is published. The manual **Check update signing key** workflow can diagnose a mismatch without exporting the secret.

Build 62 corrects the legacy embedded key to match the existing CI signing key. The Developer ID signing identity stays the same, which supports [Sparkle's documented signing-key rotation](https://sparkle-project.org/documentation/#security). Build 61 remains available as a historical release; build 62 is the corrected update. Homebrew 6+ requires trust in the individual cask; older Homebrew versions omit the `brew trust` line.

## Release acceptance

- CI must pass on the exact main commit to publish.
- Verify expansion, clipboard preservation, app exclusions, secure fields, immediate/Space triggers, and native/browser editing.
- Verify upgrades preserve history, pins, snippets, and explicit preferences.
- Verify release signing, notarization, checksums, appcast signature, and Homebrew URL/hash after publication.
- Exercise an upgrade from an older signed release through Sparkle before announcing availability.
