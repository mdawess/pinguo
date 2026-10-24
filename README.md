# pinguo

Learning Mandarin by reading and listening to real material. Native SwiftUI app for iPhone and iPad.

## Building

Open `Pinguo.xcodeproj` in Xcode 26 and run the `Pinguo` scheme. Source folders are synchronised groups, so new files
dropped into `Pinguo/` are picked up automatically.

## Bundled data

- `Pinguo/Resources/dictionary.sqlite` — CC-CEDICT (CC BY-SA 4.0, mdbg.net) joined with HSK levels from
  [complete-hsk-vocabulary](https://github.com/drkameleon/complete-hsk-vocabulary). Rebuild with
  `scripts/build_dictionary.py`.
- Geist (SIL Open Font License) in `Pinguo/Resources/Fonts`.
