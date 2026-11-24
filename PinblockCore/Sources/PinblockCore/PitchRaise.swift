/// A practical overpull hint for a piano that is flat enough to need a pitch raise.
///
/// The amount is locked from a measurement (or a number the tuner types). It does not
/// shrink as the note comes up, which would make the target chase itself.
/// Larger raises get a little extra overpull, and the result is capped.
public enum PitchRaise {
    public static func overshootCents(flatnessCents: Double, userPercent: Double) -> Double {
        guard flatnessCents > 0.5 else { return 0 }
        let extra = min(12.0, flatnessCents * 0.12)
        let effective = min(45.0, max(0, userPercent) + extra)
        return flatnessCents * effective / 100
    }

    public static func targetFrequency(finalFrequency: Double, overshootCents: Double) -> Double {
        Cents.shift(finalFrequency, by: overshootCents)
    }
}

public struct AutoAdvanceTracker: Equatable, Sendable {
    public var thresholdCents: Double
    public var holdSeconds: Double
    public var minimumConfidence: Double
    private var stableSince: Double?

    public init(thresholdCents: Double = 1.5, holdSeconds: Double = 1.2, minimumConfidence: Double = 0.55) {
        self.thresholdCents = thresholdCents
        self.holdSeconds = holdSeconds
        self.minimumConfidence = minimumConfidence
    }

    public mutating func reset() {
        stableSince = nil
    }

    /// `now` is any monotonic clock in seconds. Returns true once, when the note has
    /// been inside the window long enough, then starts the wait over.
    public mutating func consume(cents: Double, confidence: Double, now: Double) -> Bool {
        let steady = abs(cents) <= thresholdCents && confidence >= minimumConfidence
        guard steady else {
            stableSince = nil
            return false
        }
        if let stableSince {
            if now - stableSince >= holdSeconds {
                self.stableSince = now
                return true
            }
            return false
        }
        stableSince = now
        return false
    }
}

public struct MeasurementAccumulator: Equatable, Sendable {
    public private(set) var recent: [InharmonicityFit]
    public var capacity: Int

    public init(capacity: Int = 8) {
        self.recent = []
        self.capacity = max(3, capacity)
    }

    public mutating func reset() {
        recent.removeAll()
    }

    public mutating func add(_ fit: InharmonicityFit) {
        guard fit.partials.count >= 3, fit.b >= 0, fit.f1 > 0 else { return }
        recent.append(fit)
        if recent.count > capacity {
            recent.removeFirst(recent.count - capacity)
        }
    }

    /// Stable when several fits agree on B and on the fundamental.
    public var consensus: InharmonicityFit? {
        guard recent.count >= 5 else { return nil }
        let bs = recent.map(\.b)
        let f1s = recent.map(\.f1)
        guard let medianB = Regression.median(bs), let medianF1 = Regression.median(f1s), medianB > 0 else {
            return nil
        }
        let meanB = bs.reduce(0, +) / Double(bs.count)
        let variance = bs.reduce(0) { $0 + ($1 - meanB) * ($1 - meanB) } / Double(bs.count)
        let coefficient = variance.squareRoot() / meanB
        let f1Spread = f1s.compactMap { Cents.between(medianF1, $0) }.map(abs)
        guard coefficient < 0.20, f1Spread.allSatisfy({ $0 < 1.0 }) else { return nil }
        let residuals = recent.map(\.residualCents)
        let partials = recent.max(by: { $0.partials.count < $1.partials.count })?.partials ?? []
        return InharmonicityFit(
            f1: medianF1,
            b: medianB,
            residualCents: Regression.median(residuals) ?? 0,
            partials: partials
        )
    }
}
