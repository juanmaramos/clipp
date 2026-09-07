# Distribution and updates

Clipp is distributed through [GitHub Releases](https://github.com/juanmaramos/clipp/releases). The release build includes Sparkle: users can enable automatic checks in **Settings → General**, or use **Check Now**. They do not need to visit GitHub for every update.

## Release pipeline

The checked-in `.github/workflows/build.yml` publishes automatically when code reaches `main`. A manual workflow dispatch on `main` also publishes. An appcast-only commit is ignored to avoid a release loop. Pushing a tag alone does not start this workflow.

The workflow:

1. Reads `MARKETING_VERSION` and uses `GITHUB_RUN_NUMBER` as `CFBundleVersion`.
2. Runs snippet, shortcut, and search regression tests, then builds the `Clipp` scheme with Developer ID signing.
3. Notarizes and staples the app, then creates ZIP and DMG downloads and SHA-256 checksums.
4. Signs the ZIP with the Sparkle Ed25519 private key.
5. Creates the tag and public release `v<marketing-version>-build.<run-number>`.
6. Updates `appcast.xml` on `main` with the version, download size, signature, and release notes URL.

Merging a feature into `main` therefore publishes it. Validate and review the feature branch before merging. Keep the marketing version and changelog ready for users.

Required Actions secrets are `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `KEYCHAIN_PASSWORD`, `TEAM_ID`, `APPLE_ID`, `APPLE_ID_PASSWORD`, and `SPARKLE_PRIVATE_KEY`. Do not commit signing keys or put their values in build logs.

## Update feed

The production `SUFeedURL` is:

```
https://raw.githubusercontent.com/juanmaramos/clipp/main/appcast.xml
```

`SUPublicEDKey` in `Maccy/Info.plist` must match the key that signs release ZIPs. Sparkle compares the numeric build version to the installed app. A locally compiled app with a higher build number than the release feed will not see that release as an upgrade.

After publishing, verify that the release assets exist, the appcast points to the new ZIP with its actual byte length, and **Check Now** in an older signed release offers and installs the update. Compilation alone does not verify a real update installation.

## Local development

Use a feature branch and the `Clipp` scheme:

```sh
xcodebuild -project Maccy.xcodeproj -scheme Clipp -configuration Debug \
  -derivedDataPath /tmp/clipp-development \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
```

The app is `/tmp/clipp-development/Build/Products/Debug/Clipp.app`. Debug uses the separate identifier `futurialabs.clipp.dev`, separate local data, and no public updater or automatic launch-at-login setup. Open Settings → Snippets to add examples and try expansion locally.

System-wide expansion requires Accessibility and Input Monitoring permissions for the development app itself. Ad-hoc signing is for local testing; rebuilding may require refreshing macOS permission approval. Keep a stable app location when testing permissions. Public distribution uses the signed, notarized Release build.

## Snippets release checks

- Resolve the App Sandbox distribution decision first. The current build disables system-wide expansion because Apple does not support the required Accessibility APIs in the sandbox. A move outside the sandbox must preserve existing history and settings, then receive permission and cross-app validation.
- Run snippet, search, keyboard shortcut, clipboard, and history migration tests.
- Verify that bare numbers search while the displayed Command-number shortcuts activate visible results.
- Add, edit, save, reload, import, and export snippets in the native editor.
- Test text expansion and clipboard preservation in native and browser text fields with permissions granted.
- Check excluded apps, secure fields, cursor moves, fast typing, optional sound, feedback, and ordinary Undo behavior in target apps.
- Upgrade an older signed release through Sparkle before announcing availability.
