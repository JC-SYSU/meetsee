# Releasing

This project publishes source and ad-hoc signed binaries on GitHub. There is no Apple Developer ID and no notarization.

## 1. Prepare

- Update `CFBundleShortVersionString` and `CFBundleVersion` in `build.sh`.
- Move the relevant entries from `Unreleased` in `CHANGELOG.md` into a new version section.
- Run the full test suite:

```bash
./test.sh
```

- Confirm the working tree is clean.

## 2. Build the release binary

```bash
SIGNING_IDENTITY=- ./build.sh build/MeetSee.app
```

This forces ad-hoc signing. Verify the bundle:

```bash
codesign -dv --verbose=2 build/MeetSee.app
codesign --verify --strict build/MeetSee.app
plutil -p build/MeetSee.app/Contents/Info.plist | grep CFBundleIdentifier
```

The expected identifier is `cn.meetsee.app`. The signature is `adhoc`.

Gatekeeper on another Mac will reject the app until the user approves it. The release notes must state the first-launch steps and the TCC re-grant behavior.

## 3. Package

```bash
ditto -c -k --keepParent build/MeetSee.app MeetSee-0.1.0-arm64.zip
shasum -a 256 MeetSee-0.1.0-arm64.zip
```

The published build is arm64 only. Do not describe it as universal.

## 4. Tag and publish

```bash
git tag -a v0.1.0 -m "Meet&See 0.1.0"
git push origin main --tags
gh release create v0.1.0 MeetSee-0.1.0-arm64.zip \
  --title "Meet&See 0.1.0" \
  --notes-file RELEASE_NOTES.md
```

The release notes must include:

- A one-paragraph summary.
- Requirements: macOS 13+, Liquid Glass requires macOS 26, arm64 only.
- The ad-hoc first-launch steps.
- A note that updates may require re-granting Full Disk Access and Contacts.
- A link to the source tag, to satisfy GPL-3.0 section 6.
- The SHA-256 of the zip.

## 5. Verify

- Download the release asset from GitHub and check the checksum.
- Verify the app's `CFBundleIdentifier` and signature.
- Run `git log --format='%ae %ce'` and confirm the public commit identity is the repository noreply address.
- Confirm the release page links to the corresponding source tag.

## Release notes template

```markdown
## Meet&See 0.1.0

Local file and application search for macOS, with Chinese-friendly matching.

### Requirements
- macOS 13 or later
- macOS 26 for Liquid Glass
- Apple Silicon (arm64)

### Install
1. Unzip and move `觅见.app` to `/Applications`.
2. Double-click once, dismiss the warning.
3. Open System Settings → Privacy & Security → Open Anyway.

This build is ad-hoc signed, not notarized. After an update, macOS may ask again for Full Disk Access, Contacts, or Finder automation.

### Source
Built from tag `v0.1.0`. Corresponding source: https://github.com/JC-SYSU/meetsee/tree/v0.1.0

SHA-256: `<checksum>`
```
