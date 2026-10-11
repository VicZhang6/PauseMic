# Validation record

Validated locally on 2026-10-11 with Apple Silicon, Swift 6.4 / Xcode 27. The deployment target in both Mach-O slices is macOS 14.2.

## Completed

- 20 deterministic core tests passed: 17 volume ownership/restoration tests and 3 version/release validation tests.
- 3 native tests passed when explicitly enabled: Core Audio process input status, UID-based output lookup, and an actual output-volume round trip from the original value to 0 and back. No recording or player commands were used.
- Default test runs skip the volume-mutating hardware test; native status/UID checks skip on hosts without the required audio capability.
- Universal release `.app` built for arm64 and x86_64; both minimum OS load commands checked as 14.2.
- Bundle Info.plist and localized resources validated. The Automation usage description and all player scripting were removed.
- Developer ID signature, secure timestamp, hardened runtime, and strict bundle signature verification succeeded for the initial local release build.
- Native settings opened with English strings; Chinese settings layout inspected visually. Menu/application text updates with language choice.
- Native window close/reopen checked; the application retains its menu bar lifecycle after closing settings. No login preference was changed during validation.

The real volume round-trip test restored the exact original scalar value and left the hardware mute state unchanged.

## Automated scenarios

Already-zero or hardware-muted devices; overlapping microphone activity; short idle gaps; manual volume or mute changes; separate output-device receipts; disconnect/reconnect; journal-before-write ordering; journal failure; crash recovery; unknown input state; final input recheck; explicit disable/quit restoration; keep-at-zero; unsupported output; read/write failure; a concurrent user change at the setter; invalid recovery data; absent output.

## GitHub publishing

Source and release publishing use the existing hecara account. The current OAuth credential lacks the `workflow` scope, so workflow files are provided as templates in `docs/workflow-templates/` instead of active Actions. Cloud CI has not run; all test/build results above are local.

## Not yet physically verified

- Intel execution (cross-compiled only).
- Bluetooth/AirPods profile transitions and reconnects, HDMI/digital/USB hardware, multiple physical outputs. Their ownership transitions are covered by simulated tests.
- A complete real microphone dictation session and login after a physical reboot. Input status and actual volume control have been tested independently.
- Apple notarization: no configured credentials/profile were available. The initial binary is Developer ID signed, not notarized.

The program uses public APIs and polls at approximately 300 ms. Short-lived activity may occur between samples. Manual commands that leave the observed state unchanged cannot be distinguished; the explicit keep-at-zero action handles intentional silence.
