import Foundation

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--read-persisted" {
    let defaults = UserDefaults(suiteName: CommandLine.arguments[2])!
    let saved = CaptionChoiceStore(defaults: defaults).load(content: "series:example:season1:episode1")
    assert(saved?.dialogue?.isEmpty == false && saved?.signs == "")
    exit(0)
}

func track(_ id: Int, _ title: String, _ language: String = "eng", _ codec: String = "ass", forced: Bool = false) -> CaptionTrack {
    CaptionTrack(id: id, title: title, language: language, codec: codec, forced: forced, ordinal: 0)
}
let dialogue = track(1, "English Closed Captions [CR] SRT")
let signs = track(2, "English Signs & Songs [CR]")
let spanish = track(3, "Spanish Signs", "spa")
let frenchCC = track(4, "Closed Captions", "fra")
let unknown = track(5, "CR SRT", "")
let tracks = [spanish, frenchCC, unknown, dialogue, signs]
func selection(_ enabled: Bool, saved: SavedCaptionChoice? = nil, available: [CaptionTrack] = tracks) -> CaptionPair {
    CaptionSelectionPolicy.selection(tracks: available, dialogueEnabled: enabled, saved: saved)
}
assert(selection(true) == CaptionPair(dialogue: 1, signs: 2))
assert(selection(false) == CaptionPair(dialogue: -1, signs: 2))
assert(selection(true, available: [spanish, frenchCC, unknown]) == CaptionPair(dialogue: -1, signs: -1))
assert(selection(true, available: [dialogue]) == CaptionPair(dialogue: 1, signs: -1))
assert(track(1, "English CC Signs").isSigns)
assert(track(1, "English S&S").isSigns)
assert(track(1, "English Forced SRT").isSigns)
assert(track(1, "English", forced: true).isSigns)
assert(track(1, "English SDH", "en-US").isEnglish)
assert(!track(1, "English Signs", "jpn").isEnglish)
assert(!unknown.isEnglish)

let suite = "BetterNuvio.CaptionPolicyTests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let store = CaptionChoiceStore(defaults: defaults)
let choice = SavedCaptionChoice(dialogue: dialogue.fingerprint, signs: "")
store.save(choice, content: "series:example:season1:episode1")
store.save(SavedCaptionChoice(dialogue: "", signs: signs.fingerprint), content: "movie:example")
let reopened = CaptionChoiceStore(defaults: defaults)
assert(reopened.load(content: "series:example:season1:episode1") == choice)
assert(reopened.load(content: "series:example:season1:episode2") == nil)
assert(defaults.synchronize())
let restartedApp = Process()
restartedApp.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
restartedApp.arguments = ["--read-persisted", suite]
try restartedApp.run()
restartedApp.waitUntilExit()
assert(restartedApp.terminationStatus == 0)
assert(selection(false, saved: reopened.load(content: "series:example:season1:episode1")) == CaptionPair(dialogue: 1, signs: -1))
let renumbered = track(41, dialogue.title)
assert(selection(false, saved: choice, available: [renumbered]) == CaptionPair(dialogue: 41, signs: -1))
assert(selection(true, saved: choice, available: [signs]) == CaptionPair(dialogue: -1, signs: -1))
let remote = CaptionTrack(id: 8, title: "Refreshed filename", language: "eng", codec: "srt", forced: false, ordinal: 0, externalURL: "https://example.test/subtitles.srt")
assert(selection(false, saved: SavedCaptionChoice(dialogue: "old title", signs: "", dialogueExternalURL: remote.externalURL), available: [remote]) == CaptionPair(dialogue: 8, signs: -1))

for original in [CaptionPair(dialogue: -1, signs: -1), CaptionPair(dialogue: 1, signs: -1), CaptionPair(dialogue: -1, signs: 2)] {
    var preview = CaptionRewindPreview()
    assert(preview.begin(current: original, available: CaptionPair(dialogue: 1, signs: 2), now: 100) == CaptionPair(dialogue: 1, signs: 2))
    assert(preview.finish(now: 109.99) == nil)
    assert(preview.finish(now: 110) == original)
    assert(preview.original == nil)
}
var preview = CaptionRewindPreview()
assert(preview.begin(current: CaptionPair(dialogue: 1, signs: 2), available: CaptionPair(dialogue: 1, signs: 2), now: 0) == nil)
assert(preview.begin(current: CaptionPair(dialogue: -1, signs: -1), available: CaptionPair(dialogue: -1, signs: -1), now: 0) == nil)
let original = CaptionPair(dialogue: -1, signs: 2)
_ = preview.begin(current: original, available: CaptionPair(dialogue: 1, signs: 2), now: 10)
_ = preview.begin(current: CaptionPair(dialogue: 1, signs: 2), available: CaptionPair(dialogue: 1, signs: 2), now: 15)
assert(preview.finish(now: 20) == nil)
assert(preview.finish(now: 25) == original)
_ = preview.begin(current: original, available: CaptionPair(dialogue: 1, signs: 2), now: 30)
preview.cancel() // A manual selection or a new movie/episode owns the state now.
assert(preview.finish(now: 100) == nil)
print("PASS: English role detection, missing/foreign tracks, per-episode persistence, changed track IDs, rewind restoration and repeated rewinds")
