/// Offsets from equal temperament, in cents, indexed by pitch class with C = 0.
/// Every temperament here is shifted so A is exactly 0: A4 stays on the reference pitch.
public struct Temperament: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let summary: String
    public let offsets: [Double]

    public init(id: String, displayName: String, summary: String, offsets: [Double]) {
        precondition(offsets.count == 12)
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.offsets = offsets
    }

    public func cents(forMidi midi: Int) -> Double {
        offsets[NotePitch.pitchClass(midi: midi)]
    }

    public func frequency(midi: Int, reference: Double) -> Double {
        Cents.shift(NotePitch.equalTemperament(midi: midi, reference: reference), by: cents(forMidi: midi))
    }

    /// Size of the fifth rising from `pitchClass`, in cents. 700 is equal; about 701.955 is pure.
    public func fifthCents(fromPitchClass pitchClass: Int) -> Double {
        let upper = (pitchClass + 7) % 12
        return 700 + offsets[upper] - offsets[pitchClass]
    }
}

public enum TemperamentLibrary {
    public static let pureFifth = 1200 * PB.log2(1.5)
    public static let syntonicComma = 1200 * PB.log2(81.0 / 80.0)
    public static let pythagoreanComma = 12 * pureFifth - 7 * 1200

    public static let all: [Temperament] = [
        equal, vallotti, werckmeisterIII, kirnbergerIII, young1799, quarterCommaMeantone
    ]

    public static func named(_ id: String) -> Temperament {
        all.first { $0.id == id } ?? equal
    }

    public static let equal = Temperament(
        id: "equal",
        displayName: "Equal",
        summary: "Every fifth is narrowed by 1/12 of the Pythagorean comma. This is the default.",
        offsets: Array(repeating: 0, count: 12)
    )

    /// Modern circulating Vallotti: F–C–G–D–A–E–B each narrowed by 1/6 Pythagorean comma; the other fifths pure.
    public static let vallotti = make(
        id: "vallotti",
        displayName: "Vallotti",
        summary: "Six diatonic fifths from F to B are each narrowed by 1/6 of a Pythagorean comma. The rest are pure.",
        narrowing: { pc in
            [5, 0, 7, 2, 9, 4].contains(pc) ? pythagoreanComma / 6 : 0
        }
    )

    /// The temperament usually called Werckmeister III: C–G, G–D, D–A, and B–F♯ narrowed by 1/4 Pythagorean comma.
    public static let werckmeisterIII = make(
        id: "werckmeister-iii",
        displayName: "Werckmeister III",
        summary: "Fifths C–G, G–D, D–A, and B–F♯ are each narrowed by 1/4 of a Pythagorean comma. The rest are pure.",
        narrowing: { pc in
            [0, 7, 2, 11].contains(pc) ? pythagoreanComma / 4 : 0
        }
    )

    /// Kirnberger III: C–E is a pure 5:4 third. The schisma that is left after four 1/4-syntonic fifths sits on F♯–C♯.
    public static let kirnbergerIII = make(
        id: "kirnberger-iii",
        displayName: "Kirnberger III",
        summary: "C–G–D–A–E are each narrowed by 1/4 of a syntonic comma, so C–E is a pure major third. F♯–C♯ absorbs the leftover schisma.",
        narrowing: { pc in
            if [0, 7, 2, 9].contains(pc) { return syntonicComma / 4 }
            if pc == 6 { return pythagoreanComma - syntonicComma }
            return 0
        }
    )

    /// Thomas Young's 1799 temperament: C–G–D–A–E–B–F♯ each narrowed by 1/6 Pythagorean comma.
    public static let young1799 = make(
        id: "young-1799",
        displayName: "Young 1799",
        summary: "Six fifths from C to F♯ are each narrowed by 1/6 of a Pythagorean comma. The rest are pure.",
        narrowing: { pc in
            [0, 7, 2, 9, 4, 11].contains(pc) ? pythagoreanComma / 6 : 0
        }
    )

    /// Quarter-comma meantone. Eleven fifths are narrowed by 1/4 syntonic comma; the wolf sits on G♯–E♭.
    public static let quarterCommaMeantone = make(
        id: "meantone-quarter",
        displayName: "¼-comma meantone",
        summary: "Eleven fifths are narrowed by 1/4 of a syntonic comma, so the major thirds are pure. The wolf fifth is G♯–E♭.",
        narrowing: { pc in
            if pc == 8 { return pythagoreanComma - 11 * (syntonicComma / 4) }
            return syntonicComma / 4
        }
    )

    /// `narrowing(pc)` is how many cents the fifth above that pitch class is narrower than a pure 3:2.
    /// The twelve narrowings must sum to the Pythagorean comma so the circle closes.
    public static func offsets(fifthNarrowing: [Double]) -> [Double] {
        precondition(fifthNarrowing.count == 12)
        var position = [Double](repeating: 0, count: 12)
        var pc = 0
        for _ in 0..<11 {
            let next = (pc + 7) % 12
            position[next] = position[pc] + (pureFifth - fifthNarrowing[pc])
            pc = next
        }
        var fromEqual = (0..<12).map { pitch -> Double in
            var folded = position[pitch].truncatingRemainder(dividingBy: 1200)
            if folded < 0 { folded += 1200 }
            return folded - Double(pitch) * 100
        }
        let a = fromEqual[9]
        fromEqual = fromEqual.map { $0 - a }
        return fromEqual
    }

    private static func make(
        id: String,
        displayName: String,
        summary: String,
        narrowing: (Int) -> Double
    ) -> Temperament {
        let amounts = (0..<12).map(narrowing)
        return Temperament(
            id: id,
            displayName: displayName,
            summary: summary,
            offsets: offsets(fifthNarrowing: amounts)
        )
    }
}
