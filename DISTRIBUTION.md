# Distribution Guide

## Quick Start (No Code Signing)

For immediate testing and distribution without Apple Developer account:

1. **Build locally**:
   ```sh
   xcodebuild -project Maccy.xcodeproj -scheme Maccy -configuration Release
   ```

2. **Find the app**:
   - Located in: `build/Build/Products/Release/Clipp.app`

3. **Create distributable**:
   ```sh
   cd build/Build/Products/Release
   zip -r Clipp.zip Clipp.app
   ```

4. **Upload to GitHub Releases**:
   - Go to: https://github.com/juanmaramos/clipp/releases
   - Click "Create a new release"
   - Upload `Clipp.zip`

5. **Users install**:
   - Download `Clipp.zip`
   - Extract and move to Applications
   - Right-click → Open (first time only to bypass warning)

---

## Code Signing + Notarization Setup

When you're ready for better UX (no warnings), follow these steps:

### Prerequisites

1. **Apple Developer Account** ($99/year)
   - Sign up at: https://developer.apple.com/programs/

2. **Create certificates** (in Xcode):
   - Xcode → Settings → Accounts
   - Select your Apple ID → Manage Certificates
   - Click "+" → "Developer ID Application"

### GitHub Secrets Setup

Add these secrets to your repository (Settings → Secrets and variables → Actions):

#### 1. Export Certificate

```sh
# Export certificate from Keychain Access
# File → Export Items → Save as .p12
# Convert to base64:
base64 -i DeveloperIDApplication.p12 | pbcopy
```

Add to GitHub as: `BUILD_CERTIFICATE_BASE64`

#### 2. Other Secrets

| Secret Name | Description | Where to find |
|-------------|-------------|---------------|
| `P12_PASSWORD` | Password you set when exporting .p12 | You chose this |
| `KEYCHAIN_PASSWORD` | Any password (for build keychain) | Make one up |
| `APPLE_ID` | Your Apple ID email | developer.apple.com |
| `APPLE_ID_PASSWORD` | App-specific password | See below |
| `TEAM_ID` | 10-character team ID | developer.apple.com/account |

#### 3. Generate App-Specific Password

1. Go to: https://appleid.apple.com/account/manage
2. Sign in with your Apple ID
3. Security → App-Specific Passwords
4. Click "+" and generate
5. Add to GitHub as: `APPLE_ID_PASSWORD`

### Enable Code Signing in Workflow

Uncomment the relevant sections in `.github/workflows/build.yml`:
- Import certificates section
- Notarize app section

### Test the Workflow

```sh
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions will automatically:
1. Build the app
2. Code sign it
3. Notarize with Apple
4. Create a GitHub Release
5. Upload the notarized app

---

## Distribution Options Comparison

### Option A: GitHub Releases (Recommended)

**Setup:**
- No recurring costs (if no code signing)
- $99/year (if code signing + notarization)
- Full control over updates

**User Experience:**
- Download from GitHub
- Automatic updates via Sparkle (built-in)
- No review delays

**Best for:** Open source projects, quick iterations

### Option B: Your Website

Same as GitHub Releases, but host the .zip on your own domain:
- More professional appearance
- Direct download links
- Still uses Sparkle for updates

**appcast.xml location:**
```
https://yourwebsite.com/clipp/appcast.xml
```

Update `Info.plist`:
```xml
<key>SUFeedURL</key>
<string>https://yourwebsite.com/clipp/appcast.xml</string>
```

### Option C: Mac App Store

**Setup:**
- $99/year Apple Developer Program
- 3-7 day review per update
- Sandboxing required (may break features)

**User Experience:**
- Most trusted (no warnings)
- Auto-updates via App Store
- Easy discovery

**Best for:** Maximum reach, commercial apps

---

## Recommended Approach

**Phase 1: Launch Fast** (Week 1)
- Build locally
- Upload to GitHub Releases
- No code signing
- Users right-click → Open

**Phase 2: Better UX** (When ready)
- Get Apple Developer account
- Set up code signing + notarization
- Automated builds via GitHub Actions
- Users double-click to install

**Phase 3: Optional** (If successful)
- Consider Mac App Store
- Or keep GitHub/website distribution

---

## Building for Release

### Manual Build

```sh
# Clean build
rm -rf build/

# Build release version
xcodebuild \
  -project Maccy.xcodeproj \
  -scheme Maccy \
  -configuration Release \
  -derivedDataPath build \
  build

# App is at: build/Build/Products/Release/Clipp.app
```

### Create DMG (Optional - better than .zip)

Install `create-dmg`:
```sh
brew install create-dmg
```

Create installer:
```sh
create-dmg \
  --volname "Clipp" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "Clipp.app" 200 190 \
  --hide-extension "Clipp.app" \
  --app-drop-link 600 185 \
  "Clipp.dmg" \
  "build/Build/Products/Release/Clipp.app"
```

---

## Questions?

- **Do I need code signing?** No, but it's better UX
- **Can I use website + GitHub?** Yes, host files anywhere
- **Should I use App Store?** Not initially - too much friction
- **How do updates work?** Sparkle (built-in) checks GitHub/website

Start with GitHub Releases and no signing. Upgrade later when you have users and revenue to justify the $99/year.
