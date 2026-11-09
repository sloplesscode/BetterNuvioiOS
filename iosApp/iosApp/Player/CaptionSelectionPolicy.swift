import Foundation

struct CaptionTrack: Equatable {
    let id: Int
    let title: String
    let language: String
    let codec: String
    let forced: Bool
    let ordinal: Int
    var externalURL: String? = nil

    private var words: Set<String> {
        Set(title.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    var isEnglish: Bool {
        let language = language.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: "-")
        if !language.isEmpty && !["und", "unknown"].contains(language) {
            return ["en", "eng", "english"].contains(language.split(separator: "-").first.map(String.init) ?? "")
        }
        // A codec or release-group name alone is not evidence of English.
        return !words.isDisjoint(with: ["english", "eng", "en"])
    }

    var isSigns: Bool {
        forced || !words.isDisjoint(with: ["sign", "signs", "signage", "forced", "songs", "song", "lyrics", "typesetting", "typeset", "onscreen", "opening", "ending"])
            || title.lowercased().contains("on-screen") || title.lowercased().contains("on screen")
            || title.lowercased().contains("foreign parts") || title.lowercased().contains("non-dialogue")
            || title.lowercased().range(of: #"\bs\s*[&+/]\s*s\b"#, options: .regularExpression) != nil
            || title.lowercased().range(of: #"\bop\s*[/&+]\s*ed\b"#, options: .regularExpression) != nil
    }

    var dialogueScore: Int {
        // Sign markers take precedence over CC, CR, SRT and other dialogue labels.
        guard isEnglish && !isSigns else { return -1 }
        return words.isDisjoint(with: ["closed", "captions", "caption", "cc", "sdh", "cr", "srt", "dialogue", "dialog", "full", "subtitles", "subs"]) ? 0 : 1
    }

    var fingerprint: String {
        // Track numbers can change between streams; never persist an mpv id.
        [title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), language.lowercased(), codec.lowercased(), String(ordinal)].joined(separator: "\u{1f}")
    }
}

struct SavedCaptionChoice: Codable, Equatable {
    // nil means automatic; an empty string means explicitly Off.
    var dialogue: String?
    var signs: String?
    var dialogueExternalURL: String?
    var signsExternalURL: String?
}

struct CaptionPair: Equatable {
    var dialogue: Int
    var signs: Int
}

enum CaptionSelectionPolicy {
    static func selection(tracks: [CaptionTrack], dialogueEnabled: Bool, saved: SavedCaptionChoice?) -> CaptionPair {
        func resolve(_ fingerprint: String?, externalURL: String?, fallback: Int) -> Int {
            guard let fingerprint else { return fallback }
            guard !fingerprint.isEmpty else { return -1 }
            return tracks.first { $0.fingerprint == fingerprint }?.id
                ?? tracks.first { externalURL != nil && $0.externalURL == externalURL }?.id ?? -1
        }
        let dialogue = tracks.filter { $0.dialogueScore >= 0 }.sorted {
            $0.dialogueScore == $1.dialogueScore ? $0.id < $1.id : $0.dialogueScore > $1.dialogueScore
        }.first?.id ?? -1
        let signs = tracks.first { $0.isEnglish && $0.isSigns }?.id ?? -1
        return CaptionPair(dialogue: resolve(saved?.dialogue, externalURL: saved?.dialogueExternalURL, fallback: dialogueEnabled ? dialogue : -1),
                           signs: resolve(saved?.signs, externalURL: saved?.signsExternalURL, fallback: signs))
    }
}

final class CaptionChoiceStore {
    private let defaults: UserDefaults
    private let key = "BetterNuvio.captionChoices.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load(content: String) -> SavedCaptionChoice? {
        guard let data = defaults.dictionary(forKey: key)?[content] as? Data else { return nil }
        return try? JSONDecoder().decode(SavedCaptionChoice.self, from: data)
    }
    func save(_ choice: SavedCaptionChoice, content: String) {
        guard !content.isEmpty, let data = try? JSONEncoder().encode(choice) else { return }
        var choices = defaults.dictionary(forKey: key) ?? [:]
        choices[content] = data
        defaults.set(choices, forKey: key)
    }
}

struct CaptionRewindPreview {
    private(set) var original: CaptionPair?
    private(set) var deadline: TimeInterval?
    mutating func begin(current: CaptionPair, available: CaptionPair, now: TimeInterval, duration: TimeInterval = 10) -> CaptionPair? {
        let baseline = original ?? current
        guard (baseline.dialogue < 0 && available.dialogue >= 0) || (baseline.signs < 0 && available.signs >= 0) else { return nil }
        original = baseline
        deadline = now + duration
        return CaptionPair(dialogue: baseline.dialogue >= 0 ? baseline.dialogue : available.dialogue,
                           signs: baseline.signs >= 0 ? baseline.signs : available.signs)
    }
    mutating func finish(now: TimeInterval, force: Bool = false) -> CaptionPair? {
        guard let deadline, force || now >= deadline else { return nil }
        let restored = original
        cancel()
        return restored
    }
    mutating func cancel() { original = nil; deadline = nil }
}
