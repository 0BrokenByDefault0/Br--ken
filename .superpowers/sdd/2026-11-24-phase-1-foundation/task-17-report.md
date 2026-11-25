# Task 17 report

## Implemented
- Root is `RootView`: TabView with Journey, Lesson, Melody, Chords, Drums. Tint haze, forced dark. Playback stops on tab change. LabRootView, the lab views and JourneyPlaceholderView were removed.
- `AppModel`:
  - Journey: `stageStatus`, `currentStageID`, `nextLesson(in:)`, `openLesson`, `currentLesson` (in `Journey/AppModel+Journey.swift` and `AppModel.swift`).
  - Tracks: `startTrack`, `renameTrack(id:to:)`, `deleteTrack(id:)`, `setMuted(role:_:)`, `editActivePart` (creates an empty part on the first edit).
  - Playback: `play`, `stop`, `audition`, `isPlaying`, `metronome`. The metronome is a temporary rim part sent to audio only. `stop` restores the active track after an audition.
  - `audio` is now internal so tool screens can read the playhead and play live notes.
- Journey UI: `JourneyMapView`, `YourTrackBar`, `TrackListView`, `TrackSetupView` (also holds `NewTrackSheet`, `NoTrackView`, `TrackTransport`).
- Tool screens bound to the active track, each with `TrackTransport`: `MelodyScreen`, `ChordsScreen`, `DrumsScreen`. They show a "Start a track" empty state when there is no active track, and they refresh when the part changes elsewhere.
- `LessonPlaceholderView` shows the current lesson title, or "Pick a lesson from the Journey".

## TDD evidence
- RED: commit 1917761 has the tests only. It was pushed without `[ipa]`, so no app-test run exists for it; the tests could not compile without the new API. CI run 45550553394 is the core-tests-only run.
- GREEN: commit 0026067, run 45550857813. Both `app` (tests, build, IPA) and `core-tests` succeeded.

## Tests (App/Tests/AppModelTests.swift)
- Journey: `stageStatuses`, `currentStageIsFirstUnfinished`, `nextLessonSkipsCompleted`, `openLessonPersistsCurrent`.
- Tracks: `renameTrackPersists`, `deleteActiveTrackClearsActive`, `setMutedTogglesPartAndSendsAudio`, `editActivePartCreatesEmptyPartOnFirstEdit`, `startTrackCreatesAndActivates`.
- Playback: `playAndStopRestoreActiveTrackAfterAudition`, `metronomeAddsTemporaryRimPartToAudioOnly`.
- Setup: `genreFitHints`.
- The `Sandbox` helper now takes a custom stage list.

## Concerns
- Not run on a device. The view code (mini timeline canvas, pulse animation, tab bar styling) compiled but has not been looked at.
- The tempo slider in `TrackTransport` saves the track on every step.
- Stage 5-8 tagline and "coming later" display depend on content having no lessons for them.

## Fix round 1 (commit 48b4691, CI run 45552581758: app and core-tests green)
1. Chords tempo: `AppModel.audition` now always plays at the active track's current tempo. `ChordsScreen` also syncs `finder.tempo` when the tempo changes. Test: `playAndStopRestoreActiveTrackAfterAudition` (an audition built at tempo 100 plays at 140).
2. Sliders: `previewActiveTrack` / `updateActiveTrack(persist: false)` / `editActivePart(persist:)` keep the change in memory and send it to audio without writing to disk. `commitActiveTrack()` saves. Tempo (TransportBar `onTempoCommit`), sound controls (`onCommit`) and drum swing (a drag flag read by the grid callback) commit once when the drag ends. Tests: `previewDoesNotWriteToDiskCommitDoes`, `previewPartEditThenCommit`.
3. `deleteTrack` removes the track only after the file delete succeeds (a missing file counts as deleted). Failures set `lastError` and the track stays listed. `ErrorBanner` (dismissible, `dismissError()`) shows on the Journey and in TrackListView. `play()` with no active track does nothing. Tests: `failedDeleteKeepsTrackAndReportsError` (read-only tracks dir), `playWithoutActiveTrackIsNoOpEvenAfterDelete`.
4. TrackListView rename alert and delete dialog use `presenting:`. `AppModel.defaultTrackName` gives "My first beat", then "Beat 2", "Beat 3" and so on, skipping names in use; `NewTrackSheet` uses it. Test: `defaultTrackNamesAreUnique`.
