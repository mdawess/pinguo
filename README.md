# pinguo

Learning Mandarin by reading and listening to real material. A native SwiftUI app for iPhone and iPad: read EPUBs,
PDFs, articles and pasted text with tap-to-define and pinyin, listen in a natural ElevenLabs voice with the spoken
sentence highlighted, review looked-up words with FSRS, practise speaking with a Claude tutor and turn English audio
into a bilingual Chinese document.

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

### API keys

Keys are stored in the Keychain and never compiled in. Paste them in **Progress → Settings → API keys**:

- ElevenLabs — narration, word audio, voice picker and Scribe speech-to-text fallback. Library (native Mandarin)
  voices and voice design need a paid ElevenLabs plan; the free plan works with the premade voices.
- Anthropic — sentence translation, the conversation tutor and English audio translation (`claude-opus-5-5`).

Debug builds also read `ELEVENLABS_API_KEY` / `ANTHROPIC_API_KEY` from the launch environment and copy them into the
Keychain, e.g. `SIMCTL_CHILD_ELEVENLABS_API_KEY=… xcrun simctl launch booted com.mdawes.pinguo`.

### Tests

```sh
xcodebuild test -project Pinguo.xcodeproj -scheme Pinguo -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The UI tests that call ElevenLabs and Claude skip themselves unless the keys are passed to the runner:
`TEST_RUNNER_ELEVENLABS_API_KEY=… TEST_RUNNER_ANTHROPIC_API_KEY=… xcodebuild test …`.

## Bundled data

- `Pinguo/Resources/dictionary.sqlite` — CC-CEDICT (CC BY-SA 4.0, mdbg.net) joined with HSK levels from
  [complete-hsk-vocabulary](https://github.com/drkameleon/complete-hsk-vocabulary), with preferred readings for common
  polyphones. Rebuild with `scripts/build_dictionary.py`.
- Geist and Noto Serif SC (SIL Open Font License) in `Pinguo/Resources/Fonts`. Songti SC is not installed on iOS by
  default, so the reader uses Noto Serif SC.
- `scripts/render_app_icon.swift` renders the app icon.
