# Building and installing Br--ken

The app is distributed as an **unsigned IPA** built by GitHub Actions. There is no Mac in the loop.

## Getting the IPA

- **On demand:** GitHub, Actions, CI, "Run workflow" (pick the branch). When it finishes, download the `Broken.ipa` artifact from the run page.
- **On a commit:** put `[ipa]` in the commit message and push; the macOS job runs and uploads the artifact.
- **Release:** push a tag starting with `v` (for example `v0.1.0`). The IPA is attached to a GitHub Release, which is the easiest download on the phone.

Artifacts are zipped; unzip once to get `Broken.ipa`. Releases serve the `.ipa` directly.

## Installing

Use any sideloading tool that signs with your own (free) Apple ID:

- **AltStore or SideStore:** open the IPA in the app (share sheet, "Open in AltStore/SideStore") and install.
- **Sideloadly:** connect the phone to a computer, drag the IPA in, sign in with your Apple ID.

TrollStore does not support the latest iOS, so it is not an option.

## The 7-day limit

Apps signed with a free Apple ID expire after 7 days and must be re-signed. AltStore and SideStore can refresh the app automatically in the background (AltStore needs AltServer running on a computer on the same Wi-Fi; SideStore refreshes on-device). Data in the app's Documents folder survives a refresh; do not delete and reinstall the app.

## Local build (macOS only)

```
brew install xcodegen
xcodegen generate
scripts/build-ipa.sh
```
