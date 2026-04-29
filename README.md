# Garble

Pop letters to reveal words.

## What it is

Each level shows a scrambled string of letters — a "garble" — that hides a set of valid English words as subsequences. Tap a letter to pop it; whenever the remaining letters spell one of the level's allowed words, it's banked. Score is `word_length × 10`, doubled when a word is found after popping exactly one letter since the last bank ("1-pop bonus"). Hitting the level's max score unlocks the next.

Built with Flutter for iOS and Android. Custom physics-driven letter-pop animation via `forge2d`.

## Project layout

```
lib/
├── data/        # Hardcoded levels (garble strings + valid word sets)
├── models/      # Level, GameController (state + scoring rules)
├── screens/     # level_select_screen.dart, game_screen.dart
├── services/    # scorer, progress (shared_preferences), glyph_profiler
└── widgets/     # garble_stage.dart — the forge2d-driven letter canvas
```

Levels live in `lib/data/levels.dart` and are generated offline from a Scrabble dictionary intersected with a common-use word list, then hand-filtered.

## Notable dependencies

| Package | Role |
|---|---|
| `forge2d` | Physics engine driving the letter-pop animation. |
| `flutter_svg` | Renders the wordmark on the level-select screen. |
| `shared_preferences` | Persists per-user progress (max level cleared, words found). |
| `flutter_launcher_icons` | Build-time launcher icon generation from `assets/branding/`. |
| `flutter_native_splash` | Build-time native splash screen generation. |

## Getting started

Requires the Flutter SDK (Dart `^3.11`).

```sh
flutter pub get
flutter run            # add `-d <device-id>` if multiple devices/simulators are connected
flutter test           # currently covers the scoring algorithm in test/scorer_test.dart
```

## Building locally

```sh
flutter build apk --release    # Android
flutter build ipa --release    # iOS (requires Xcode + an Apple Developer account)
```

The Android release build expects `android/key.properties` and the upload keystore to be present locally. Both are gitignored — keep them in your password manager. iOS local release builds use Xcode automatic signing.

## Shorebird

The app is wired up for [Shorebird](https://shorebird.dev) code-push. `shorebird.yaml` is checked in; the `app_id` lives there. To push an over-the-air patch against the currently released version:

```sh
shorebird patch android
shorebird patch ios
```

For full version releases (new build numbers shipped to TestFlight / Play Console), use the tag-driven CI flow below — don't run `shorebird release` locally.

## Releasing

```sh
./scripts/version 0.1.0     # bumps pubspec.yaml, commits, creates tag v0.1.0
git push && git push --tags # triggers .github/workflows/release.yml
```

The workflow builds in parallel on macOS and Ubuntu runners and uploads to:
- **Play Console** — internal track (Android, AAB).
- **TestFlight** — current testers (iOS, IPA).

Full setup — required GitHub secrets, distribution cert and provisioning profile generation, App Store Connect API key, Play Console service account — is documented in [`docs/release-pipeline.md`](docs/release-pipeline.md).

## Assets and branding

- Brand colour: `#FFF200` (yellow on near-black `#0A0A0A`).
- Custom font: `assets/fonts/TG-MilesToGo-Regular.otf`, loaded as the `Garble` family.
- Launcher icon and splash sources: `assets/branding/icon-source.png`, `assets/branding/icon-foreground.png`, `assets/branding/splash-logo.png`.
- Wordmark SVG: `assets/svg/garble.svg`.

## License

Private project — all rights reserved.
