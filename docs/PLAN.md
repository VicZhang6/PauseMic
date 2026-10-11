# PauseMic implementation plan

Repository initialization was published before this plan: `be5ba4c`.

## Product decisions
- Native macOS 14.2+ application, Swift + AppKit, no web runtime or private APIs.
- Core Audio process input activity detects microphone use without recording. Poll at 300 ms; wait 1.5 seconds of continuous inactivity before restoring volume.
- While input is active, save the default output device's original volume and set it to 0. Media keeps playing. No player integration or Automation permission is needed.
- Save volume ownership per device UID. On output switching, quiet the new output and retain each original volume separately. Restore only unchanged zero-volume states; observed user volume/mute changes take precedence.
- A recovery journal is written atomically before changing volume. Restart recovers receipts and restores after mic inactivity. Disconnected outputs retain receipts until reconnection. Normal quit or disabling restores owned volume immediately. An explicit keep-at-zero action cancels restoration.
- A single-instance lock prevents two copies from interfering. Already-zero or hardware-muted outputs are untouched. Devices without software volume control show a clear error.
- English and Simplified Chinese, menu bar, closable settings window, optional launch at login through SMAppService.
- GitHub latest stable release check at launch and every hour while running, plus manual checks and wake catch-up. Display updates and open the validated GitHub release page.
- Public MIT repository, hecara.com homepage and hecara Factory attribution.

## Execution
1. Implement volume ownership, restoration and version logic.
2. Add native Core Audio microphone detection and system volume adapter.
3. Build localized menu bar/settings, login item and release checker.
4. Add universal app packaging and GitHub Actions test/build/release templates (activation requires workflow access unavailable in the current credential).
5. Verify state-machine cases, native UID lookup and real volume round trip, both architectures, bundled resources and settings lifecycle.
6. Publish implementation and an initial downloadable release with accurate signing status.

## Validation boundaries
macOS core logic and native volume operations are tested locally. Intel is cross-compiled, not run on physical Intel hardware. Bluetooth, HDMI, multiple physical outputs, actual dictation sessions and login after reboot need hardware verification; simulated tests cover their state transitions. Changes shorter than the polling interval, or an extra volume-0 command while already at 0, may not be observable. “Keep volume at 0” provides an explicit override.
