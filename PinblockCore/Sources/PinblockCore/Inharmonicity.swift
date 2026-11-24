import Foundation

public struct PartialReading: Codable, Equatable, Sendable {
    public var n: Int
    public var frequency: Double
    public var magnitude: Double

    public init(n: Int, frequency: Double, magnitude: Double) {
        self.n = n
        self.frequency = frequency
        self.magnitude = magnitude
    }
}

public struct InharmonicityFit: Equatable, Sendable {
    public var f1: Double
    public var b: Double
    public var residualCents: Double
    public var partials: [PartialReading]

    public init(f1: Double, b: Double, residualCents: Double, partials: [PartialReading]) {
        self.f1 = f1
        self.b = b
        self.residualCents = residualCents
        self.partials = partials
    }
}

public struct InharmonicitySample: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var midi: Int
    public var b: Double
    public var f1: Double
    public var residualCents: Double
    public var partials: [PartialReading]
    public var measuredAt: Date

    public init(
        id: UUID = UUID(),
        midi: Int,
        b: Double,
        f1: Double,
        residualCents: Double,
        partials: [PartialReading],
        measuredAt: Date = Date()
    ) {
        self.id = id
        self.midi = midi
        self.b = b
        self.f1 = f1
        self.residualCents = residualCents
        self.partials = partials
        self.measuredAt = measuredAt
    }
}

/// Stiff-string partials: f_n = n · f1 · sqrt( (1 + B n²) / (1 + B) ).
/// f1 is the sounding fundamental, so partial 1 is exactly f1.
public enum Inharmonicity {
    /// A generic grand, used until this piano has been measured.
    /// Log-interpolated. Bass is moderate; treble rises, but not so fast that a 4:2 octave runs away.
    public static let defaultAnchors: [(midi: Int, b: Double)] = [
        (21, 0.00035),
        (33, 0.00016),
        (45, 0.00022),
        (57, 0.00040),
        (69, 0.00070),
        (81, 0.00150),
        (93, 0.00320),
        (105, 0.0075),
        (108, 0.011)
    ]

    public static func stiffnessFactor(b: Double, n: Int) -> Double {
        let bb = min(max(b, 0), 0.5)
        let nn = Double(n)
        return ((1 + bb * nn * nn) / (1 + bb)).squareRoot()
    }

    public static func partialFrequency(f1: Double, n: Int, b: Double) -> Double {
        guard f1 > 0, n > 0 else { return 0 }
        return Double(n) * f1 * stiffnessFactor(b: b, n: n)
    }

    public static func impliedFundamental(frequency: Double, n: Int, b: Double) -> Double? {
        let unit = partialFrequency(f1: 1, n: n, b: b)
        guard frequency > 0, unit > 0 else { return nil }
        return frequency / unit
    }

    public static func defaultB(midi: Int) -> Double {
        let anchors = defaultAnchors
        if midi <= anchors[0].midi { return anchors[0].b }
        if midi >= anchors[anchors.count - 1].midi { return anchors[anchors.count - 1].b }
        for index in 0..<(anchors.count - 1) {
            let left = anchors[index]
            let right = anchors[index + 1]
            if midi >= left.midi && midi <= right.midi {
                let span = Double(right.midi - left.midi)
                let t = span == 0 ? 0 : Double(midi - left.midi) / span
                return PB.pow(left.b, 1 - t) * PB.pow(right.b, t)
            }
        }
        return anchors[anchors.count - 1].b
    }

    /// Ordinary least squares of (f_n / n)² against n².
    /// Intercept a = f0², slope c = f0² B, and f1² = a (1 + B) = a + c.
    public static func fit(partials: [(n: Int, frequency: Double)]) -> (f1: Double, b: Double)? {
        var xs: [Double] = []
        var ys: [Double] = []
        for partial in partials where partial.n > 0 && partial.frequency > 0 {
            let n = Double(partial.n)
            xs.append(n * n)
            let y = partial.frequency / n
            ys.append(y * y)
        }
        guard let fit = Regression.line(x: xs, y: ys), fit.intercept > 0 else { return nil }
        let a = fit.intercept
        let c = fit.slope
        if c <= 0 {
            return (a.squareRoot(), 0)
        }
        let b = c / a
        guard b < 0.5 else { return nil }
        return ((a + c).squareRoot(), b)
    }

    public static func residualCents(f1: Double, b: Double, partials: [(n: Int, frequency: Double)]) -> Double {
        var acc = 0.0
        var count = 0
        for partial in partials {
            let predicted = partialFrequency(f1: f1, n: partial.n, b: b)
            guard let cents = Cents.between(predicted, partial.frequency) else { continue }
            acc += cents * cents
            count += 1
        }
        guard count > 0 else { return 0 }
        return (acc / Double(count)).squareRoot()
    }

    /// B for every key. No samples: the generic curve. One sample: scale that curve
    /// so it passes through the measurement. Two or more: log-linear between them,
    /// holding the end value outside the measured span (no runaway extrapolation).
    public static func bCurve(samples: [InharmonicitySample]) -> [Double] {
        let defaults = (NotePitch.lowestMidi...NotePitch.highestMidi).map { defaultB(midi: $0) }
        let points = consolidate(samples)
        if points.isEmpty { return defaults }
        if points.count == 1, let only = points.first {
            let base = defaultB(midi: only.midi)
            let scale = base > 0 ? only.b / base : 1
            return defaults.map { clamp($0 * scale) }
        }
        var curve = [Double](repeating: 0, count: NotePitch.count)
        for midi in NotePitch.lowestMidi...NotePitch.highestMidi {
            curve[midi - NotePitch.lowestMidi] = clamp(interpolate(midi: midi, points: points))
        }
        for point in points {
            curve[point.midi - NotePitch.lowestMidi] = clamp(point.b)
        }
        return curve
    }

    private static func consolidate(_ samples: [InharmonicitySample]) -> [(midi: Int, b: Double)] {
        var buckets: [Int: [Double]] = [:]
        for sample in samples where sample.b >= 0 && (NotePitch.lowestMidi...NotePitch.highestMidi).contains(sample.midi) {
            buckets[sample.midi, default: []].append(sample.b)
        }
        return buckets.keys.sorted().map { midi in
            let logs = buckets[midi]!.map { PB.log2($0) }
            let mean = logs.reduce(0, +) / Double(logs.count)
            return (midi, PB.pow(2, mean))
        }
    }

    private static func interpolate(midi: Int, points: [(midi: Int, b: Double)]) -> Double {
        if midi <= points[0].midi { return points[0].b }
        if midi >= points[points.count - 1].midi { return points[points.count - 1].b }
        var upperIndex = 1
        while upperIndex < points.count - 1 && points[upperIndex].midi < midi {
            upperIndex += 1
        }
        let left = points[upperIndex - 1]
        let right = points[upperIndex]
        let span = Double(right.midi - left.midi)
        let t = span == 0 ? 0 : Double(midi - left.midi) / span
        return PB.pow(left.b, 1 - t) * PB.pow(right.b, t)
    }

    private static func clamp(_ b: Double) -> Double {
        min(0.2, max(0, b))
    }
}
