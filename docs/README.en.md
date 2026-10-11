# PauseMic

A native macOS menu bar utility from [hecara Factory](https://hecara.com), a project for practical, reliable little tools. [MIT licensed](../LICENSE).

PauseMic detects microphone input, saves the default system output volume, sets it to **0**, and restores the original volume after **1.5 seconds** of continuous microphone inactivity. Music, podcasts and videos keep progressing. No player-specific integration is needed.

## Install

Download the universal ZIP from [GitHub Releases](https://github.com/hecara/PauseMic/releases), extract it, and move PauseMic.app into Applications. Requires macOS **14.2+** on Apple Silicon or Intel. The first download is Developer ID signed but not yet Apple notarized; Gatekeeper may require an explicit Open Anyway confirmation in System Settings → Privacy & Security. GitHub Actions artifacts are ad-hoc signed by default.

Open the menu bar microphone icon for settings. Closing settings keeps the utility running. Optional launch at login uses macOS login items; approval may be required in System Settings → General → Login Items. English, Simplified Chinese and system language are available.

Updates are checked at launch and hourly while the app is running, with a catch-up check after waking when due. Manual checking is also available. Update prompts open the official release download page. Automatic checks can be disabled.

## Volume ownership

- Only the **default sound output** is controlled. Audio explicitly routed elsewhere is unaffected.
- Switching outputs saves and quiets the new default device; each device has its own original volume.
- Outputs already at 0 or hardware-muted are left unchanged.
- Detected manual volume/mute changes cancel restoration for that device and prevent re-muting in the same input session.
- “Keep volume at 0” explicitly cancels restoration. Repeated volume-0 commands or changes shorter than the roughly 300 ms polling interval may be invisible.
- Disabling automatic quiet or quitting normally restores volume still owned by PauseMic.
- An atomic local recovery journal is saved before changing volume. Following a crash, reopening the app restores unchanged owned volume after the microphone becomes idle. Disconnected devices retain recovery data until reconnection. A force quit cannot immediately restore volume; you can also adjust the system volume manually.
- Unknown microphone state never triggers automatic volume changes. Read/write failures preserve recovery data where applicable.

Some HDMI, digital, USB or virtual outputs do not expose writable software volume control. The app reports unsupported outputs. All sound through the controlled output is silenced, including alerts; playback itself continues.

No audio recording, microphone permission, Automation permission, audio uploads or telemetry. The local journal stores output identifiers and volume state in `~/Library/Application Support/com.hecara.PauseMic/volume-recovery.json`. GitHub Release checking is the only network use.

## Build

macOS 14.2+, Xcode 15.2+ / Swift 5.9+:

```sh
scripts/install-hooks.sh
swift test
scripts/build-app.sh
open dist/PauseMic.app
```

To run the opt-in native test that briefly zeros the real output volume and restores it:

```sh
PAUSEMIC_HARDWARE_TEST=1 swift test --filter NativeTests/testRealVolumeRoundTrip
```

For signing and notarization, provide an existing Developer ID identity and existing notarytool keychain profile as `SIGNING_IDENTITY` and `NOTARY_PROFILE` to the build script. Without them, it uses ad-hoc signing. Build/test and tag-release workflow templates are included in `docs/workflow-templates/`. They are not enabled because the current publishing credential lacks the GitHub `workflow` scope; this release was tested, signed and published locally. With the appropriate workflow access, copy them into `.github/workflows/` to enable CI. Existing releases are never replaced automatically.

[Implementation plan](PLAN.md) · [Validation](VALIDATION.md) · [Release notes](RELEASE.md)

## Private-key upload protection

Signing uses the local Keychain without exporting private keys. Install the repository hooks with `scripts/install-hooks.sh`: pre-commit scans staged blobs, while pre-push scans all local Git history, including files deleted in later commits. The build script checks bundles and ZIP contents before notarization upload and release packaging; workflow templates check explicit upload targets too. Checks block common signing-key filenames and PEM private-key content without printing secrets. Public `.cer` certificates and embedded public signature information remain allowed.

Fresh clones need hook installation. Local hooks can be bypassed, and renamed binary keys, other credential formats or manual uploads are not guaranteed to be caught. Keep private signing material in the Keychain.
