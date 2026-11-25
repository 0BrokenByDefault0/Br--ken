# Building and installing Br--ken

The app is distributed as an **unsigned IPA** built by GitHub Actions. There is no Mac in the loop.

## Getting the IPA

- **On demand:** GitHub, Actions, CI, "Run workflow" (pick the branch). When it finishes, download the `Broken.ipa` artifact from the run page. GitHub only offers "Run workflow" once `ci.yml` is on the repository's default branch; until then, push a commit with `[ipa]` in its message or use a tag release (below).
- **On a commit:** put `[ipa]` in the commit message and push; the macOS job runs and uploads the artifact.
- **Release:** push a tag starting with `v` (for example `v0.1.0`). The IPA is attached to a GitHub Release, which is the easiest download on the phone.

Artifacts are zipped; unzip once to get `Broken.ipa`. Releases serve the `.ipa` directly.

## Installing

Use any sideloading tool that signs with your own (free) Apple ID:

- **AltStore or SideStore:** open the IPA in the app (share sheet, "Open in AltStore/SideStore") and install.
- **Sideloadly:** connect the phone to a computer, drag the IPA in, sign in with your Apple ID.

TrollStore does not support the latest iOS, so it is not an option.

### Developer Mode

iOS only opens sideloaded apps with Developer Mode on. The first time, turn it on in **Settings › Privacy & Security › Developer Mode** (the switch appears once a sideloaded app is installed), let the phone restart, and confirm "Turn On" after it boots.

## The 7-day limit

Apps signed with a free Apple ID expire after 7 days and must be re-signed. AltStore and SideStore can refresh the app automatically in the background (AltStore needs AltServer running on a computer on the same Wi-Fi; SideStore refreshes on-device). Data in the app's Documents folder survives a refresh; do not delete and reinstall the app.

## Local build (macOS only)

```
brew install xcodegen
xcodegen generate
scripts/build-ipa.sh
```

## What's in this version (v0.1.0)

Phase 1 of the app:

- **Journey map:** 8 stages; stages 1–4 (First sounds, The idea, Harmony, Drums & groove) are open, with 15 lessons.
- **Lesson player:** each lesson goes Idea → Hear it → Do it → Keep it → Koala. Nothing is locked; checks and hints help but never block.
- **Instruments:** keyboard with scale lock; piano roll with live recording; drum grid with rolls, velocity, and swing; chord pads; the Chord Finder (chords that fit your melody); 808 glide.
- **Your Track:** the beat every lesson builds on, plus a track list to start, switch, rename, and delete tracks.
- **Export to Koala:** full mix, a single part, or stems, as loop-ready WAV files through the share sheet (also kept in Files app › Br--ken › Exports).

Known limits:

- Tracks are 2 bars long.
- No pitched hi-hats yet.
- Stages 5–8 and the style guides come in later versions.
