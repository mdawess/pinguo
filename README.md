# pinguo

Learning Mandarin by reading and listening to real material. A native SwiftUI app for iPhone and iPad: read EPUBs,
PDFs, articles and pasted text with tap-to-define and pinyin, listen with the spoken sentence highlighted, review
looked-up words with FSRS, practise speaking with a tutor and turn English audio into a bilingual Chinese document.
Everything runs on the device, with no accounts or API keys, and works offline.

## Building

Open `Pinguo.xcodeproj` in Xcode 26 and run the `Pinguo` scheme (iOS 26). Source folders are synchronised groups, so
new files dropped into `Pinguo/`, `Shared/` or `PinguoShare/` are picked up automatically.

Targets: `Pinguo` (app), `PinguoShare` (share extension), `PinguoTests` (Swift Testing), `PinguoUITests` (XCUITest).

### Running on a device

Select your team under Signing & Capabilities for `Pinguo` and `PinguoShare`. The app uses:

- **App Group** `group.com.mdawes.pinguo` — the share extension hands links, text and files to the app.
- **iCloud / CloudKit** container `iCloud.com.mdawes.pinguo` — library, word states, cards and review logs sync through
  your private database. If CloudKit is unavailable the store falls back to local only.

If you change the bundle identifier, update both identifiers in `Config/*.entitlements`, `Shared/PendingImports.swift`
and `PinguoStore.cloudContainer`.

### Tests

```sh
xcodebuild test -project Pinguo.xcodeproj -scheme Pinguo -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The conversation tests need Apple Intelligence on the host Mac and skip themselves without it. The English-audio test
is skipped in the simulator, which has no Translation framework; set `TEST_RUNNER_PINGUO_TRANSLATION_AVAILABLE=1` to
run it on a device.

## On-device engines

- **Narration**: an installed Mandarin `AVSpeechSynthesizer` voice, rendered to cached AAC clips with sentence timings,
  so the spoken sentence is highlighted. Premium or Enhanced voices (Settings › Accessibility › Spoken Content ›
  Voices › Chinese) sound much better than the built-in compact ones; they appear in the voice picker once downloaded.
- **Translation**: Apple's Translation framework. Download Chinese–English from **Progress → Settings → On-device**.
- **Speaking tutor and level-adapted audio translation**: Foundation Models (needs Apple Intelligence). Pinyin comes from
  the bundled dictionary, and corrections that don't resemble what the learner said are dropped.
- **Speech recognition**: the Speech framework, on-device.

**Prepare while charging** (on by default) renders narration and translations for the next chapters (3 by default) of
the three most recently opened books. It runs while the app is open and plugged in, and as a `BGProcessingTask` that
iOS only starts on external power (usually overnight). After that, reading plays from the cache instead of using
battery.

## Bundled data

- `Pinguo/Resources/dictionary.sqlite` — CC-CEDICT (CC BY-SA 4.0, mdbg.net) joined with HSK levels from
  [complete-hsk-vocabulary](https://github.com/drkameleon/complete-hsk-vocabulary), with preferred readings for common
  polyphones. Rebuild with `scripts/build_dictionary.py`.
- Geist and Noto Serif SC (SIL Open Font License) in `Pinguo/Resources/Fonts`. Songti SC is not installed on iOS by
  default, so the reader uses Noto Serif SC.
- `scripts/render_app_icon.swift` renders the app icon.
