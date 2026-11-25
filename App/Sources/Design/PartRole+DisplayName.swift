import MusicCore

extension PartRole {
    /// The part's name on buttons, chips, and pickers.
    var displayName: String {
        switch self {
        case .melody: "Melody"
        case .chords: "Chords"
        case .drums: "Drums"
        case .bass808: "808"
        case .counter: "Counter"
        case .texture: "Texture"
        }
    }
}
