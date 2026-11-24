/// The 88-key compass, A0 (MIDI 21) through C8 (MIDI 108). A4 is MIDI 69.
public enum NotePitch {
    public static let lowestMidi = 21
    public static let highestMidi = 108
    public static let a4Midi = 69
    public static let count = 88
    public static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    public static func pitchClass(midi: Int) -> Int {
        (midi % 12 + 12) % 12
    }

    public static func name(midi: Int) -> String {
        let octave = midi / 12 - 1
        return "\(names[pitchClass(midi: midi)])\(octave)"
    }

    public static func isBlackKey(midi: Int) -> Bool {
        switch pitchClass(midi: midi) {
        case 1, 3, 6, 8, 10: return true
        default: return false
        }
    }

    /// Equal temperament, A4 = `reference` hertz.
    public static func equalTemperament(midi: Int, reference: Double) -> Double {
        reference * PB.pow(2, Double(midi - a4Midi) / 12)
    }

    public static func nearestMidi(frequency: Double, reference: Double) -> Int? {
        guard frequency > 0, reference > 0 else { return nil }
        let midi = Double(a4Midi) + 12 * PB.log2(frequency / reference)
        guard midi.isFinite else { return nil }
        return min(highestMidi, max(lowestMidi, Int(midi.rounded())))
    }

    /// Partials a technician would usually listen to. Bass fundamentals are weak
    /// and high-treble upper partials die quickly.
    public static func suggestedPartial(midi: Int) -> Int {
        switch midi {
        case ..<33: return 6
        case ..<48: return 4
        case ..<96: return 2
        default: return 1
        }
    }

    public static func index(midi: Int) -> Int? {
        guard (lowestMidi...highestMidi).contains(midi) else { return nil }
        return midi - lowestMidi
    }
}
