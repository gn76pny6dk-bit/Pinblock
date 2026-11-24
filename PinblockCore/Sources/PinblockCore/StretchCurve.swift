import Foundation

public struct OctaveWeights: Codable, Equatable, Sendable {
    public var w21: Double
    public var w42: Double
    public var w63: Double

    public init(w21: Double, w42: Double, w63: Double) {
        self.w21 = w21
        self.w42 = w42
        self.w63 = w63
    }

    public func normalized() -> OctaveWeights {
        let a = max(0, w21)
        let b = max(0, w42)
        let c = max(0, w63)
        let sum = a + b + c
        if sum <= 1e-9 { return OctaveWeights(w21: 0, w42: 1, w63: 0) }
        return OctaveWeights(w21: a / sum, w42: b / sum, w63: c / sum)
    }

    /// Bass leans on 6:3, the middle on 4:2, the high treble on 2:1.
    public static func registerBlend(lowerMidi: Int) -> OctaveWeights {
        let midi = Double(lowerMidi)
        func smooth(_ x: Double, _ edge0: Double, _ edge1: Double) -> Double {
            let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
            return t * t * (3 - 2 * t)
        }
        let treble = smooth(midi, 70, 96)
        let bass = 1 - smooth(midi, 40, 62)
        let w63 = 0.70 * bass + 0.08 * (1 - bass) * (1 - treble)
        let w21 = 0.72 * treble + 0.06 * (1 - treble)
        let w42 = max(0.05, 1 - w63 - w21)
        return OctaveWeights(w21: w21, w42: w42, w63: w63).normalized()
    }
}

public enum OctavePreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case twoToOne
    case fourToTwo
    case sixToThree
    case balanced
    case register
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .twoToOne: return "2:1"
        case .fourToTwo: return "4:2"
        case .sixToThree: return "6:3"
        case .balanced: return "Balanced blend"
        case .register: return "By register"
        case .custom: return "Custom blend"
        }
    }

    public var summary: String {
        switch self {
        case .twoToOne: return "2nd partial of the lower note matches the fundamental of the upper. Narrower octaves, useful in the high treble."
        case .fourToTwo: return "4th partial of the lower note matches the 2nd of the upper. A common midrange stretch."
        case .sixToThree: return "6th partial of the lower note matches the 3rd of the upper. Wider, often what the bass wants."
        case .balanced: return "20% 2:1, 55% 4:2, 25% 6:3 everywhere."
        case .register: return "6:3 in the bass, 4:2 through the middle, 2:1 in the high treble."
        case .custom: return "Set the three weights yourself. They are averaged in cents."
        }
    }

    public func weights(lowerMidi: Int, custom: OctaveWeights) -> OctaveWeights {
        switch self {
        case .twoToOne: return OctaveWeights(w21: 1, w42: 0, w63: 0)
        case .fourToTwo: return OctaveWeights(w21: 0, w42: 1, w63: 0)
        case .sixToThree: return OctaveWeights(w21: 0, w42: 0, w63: 1)
        case .balanced: return OctaveWeights(w21: 0.20, w42: 0.55, w63: 0.25)
        case .register: return OctaveWeights.registerBlend(lowerMidi: lowerMidi)
        case .custom: return custom.normalized()
        }
    }
}

public struct NoteTuning: Codable, Equatable, Identifiable, Sendable {
    public var midi: Int
    public var f1: Double
    public var b: Double
    /// Cents above equal temperament at the same reference pitch. Includes temperament and stretch.
    public var centsFromEqual: Double

    public var id: Int { midi }

    public init(midi: Int, f1: Double, b: Double, centsFromEqual: Double) {
        self.midi = midi
        self.f1 = f1
        self.b = b
        self.centsFromEqual = centsFromEqual
    }
}

public struct CurveRequest: Equatable, Sendable {
    public var referencePitch: Double
    public var temperament: Temperament
    public var octavePreset: OctavePreset
    public var customWeights: OctaveWeights
    public var samples: [InharmonicitySample]

    public init(
        referencePitch: Double,
        temperament: Temperament,
        octavePreset: OctavePreset,
        customWeights: OctaveWeights,
        samples: [InharmonicitySample]
    ) {
        self.referencePitch = referencePitch
        self.temperament = temperament
        self.octavePreset = octavePreset
        self.customWeights = customWeights
        self.samples = samples
    }
}

/// Calculated stretch.
///
/// Each note's fundamental is the tempered equal-temperament pitch plus a cents
/// offset `s`. A4 is locked (`s = 0`), so the reference pitch never moves.
/// For every octave, `s[upper] - s[lower]` is asked to equal the extra cents that
/// make the chosen partials (2:1, 4:2, 6:3, or a cents-weighted blend) line up.
/// Neighboring semitones are asked to have a smooth second difference, which ties
/// the twelve pitch-class chains together without kinks at the temperament octave.
/// Octave equations are weighted much more heavily than the smoothness terms.
public enum CurveBuilder {
    public static let octaveWeight = 10.0
    public static let smoothnessWeight = 0.15

    public static func octaveStretchCents(bLower: Double, bUpper: Double, weights: OctaveWeights) -> Double {
        let w = weights.normalized()
        var acc = 0.0
        var sum = 0.0
        for (partial, weight) in [(2, w.w21), (4, w.w42), (6, w.w63)] where weight > 0 {
            let ratio = Inharmonicity.stiffnessFactor(b: bLower, n: partial)
                / Inharmonicity.stiffnessFactor(b: bUpper, n: partial / 2)
            acc += weight * (1200 * PB.log2(ratio))
            sum += weight
        }
        guard sum > 0 else { return 0 }
        return acc / sum
    }

    public static func build(_ request: CurveRequest) -> [NoteTuning] {
        let bValues = Inharmonicity.bCurve(samples: request.samples)
        let stretch = solveStretch(bValues: bValues, request: request)
        return (NotePitch.lowestMidi...NotePitch.highestMidi).map { midi in
            let index = midi - NotePitch.lowestMidi
            let tempered = request.temperament.frequency(midi: midi, reference: request.referencePitch)
            let f1 = Cents.shift(tempered, by: stretch[index])
            let equal = NotePitch.equalTemperament(midi: midi, reference: request.referencePitch)
            let cents = (Cents.between(equal, f1) ?? 0)
            return NoteTuning(midi: midi, f1: f1, b: bValues[index], centsFromEqual: cents)
        }
    }

    private static func solveStretch(bValues: [Double], request: CurveRequest) -> [Double] {
        let columns = NotePitch.count - 1
        func variable(_ midi: Int) -> Int? {
            if midi == NotePitch.a4Midi { return nil }
            if midi < NotePitch.a4Midi { return midi - NotePitch.lowestMidi }
            return midi - NotePitch.lowestMidi - 1
        }

        var normal = Array(repeating: Array(repeating: 0.0, count: columns), count: columns)
        var rhs = [Double](repeating: 0, count: columns)

        func addEquation(terms: [(midi: Int, coefficient: Double)], rightHand: Double, weight: Double) {
            let active = terms.compactMap { term -> (Int, Double)? in
                guard let column = variable(term.midi) else { return nil }
                return (column, term.coefficient)
            }
            for (column, coefficient) in active {
                rhs[column] += weight * coefficient * rightHand
                for (other, otherCoefficient) in active {
                    normal[column][other] += weight * coefficient * otherCoefficient
                }
            }
        }

        for midi in NotePitch.lowestMidi...(NotePitch.highestMidi - 12) {
            let weights = request.octavePreset.weights(lowerMidi: midi, custom: request.customWeights)
            let sigma = octaveStretchCents(
                bLower: bValues[midi - NotePitch.lowestMidi],
                bUpper: bValues[midi + 12 - NotePitch.lowestMidi],
                weights: weights
            )
            addEquation(
                terms: [(midi + 12, 1), (midi, -1)],
                rightHand: sigma,
                weight: octaveWeight
            )
        }
        for midi in (NotePitch.lowestMidi + 1)..<(NotePitch.highestMidi) {
            addEquation(
                terms: [(midi + 1, 1), (midi, -2), (midi - 1, 1)],
                rightHand: 0,
                weight: smoothnessWeight
            )
        }

        guard let solution = LinearSolver.solve(matrix: normal, rhs: rhs) else {
            return Array(repeating: 0, count: NotePitch.count)
        }
        var stretch = [Double](repeating: 0, count: NotePitch.count)
        for midi in NotePitch.lowestMidi...NotePitch.highestMidi {
            if let column = variable(midi) {
                stretch[midi - NotePitch.lowestMidi] = solution[column]
            }
        }
        return stretch
    }
}
