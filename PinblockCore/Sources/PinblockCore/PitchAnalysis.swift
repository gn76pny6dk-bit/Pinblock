import Foundation

public struct PitchReading: Equatable, Sendable {
    public var measuredFrequency: Double
    public var targetFrequency: Double
    public var cents: Double
    public var confidence: Double
    public var rms: Double
    public var coarseFrequency: Double
    public var isClipping: Bool
    public var isRefined: Bool
    public var detectedMidi: Int?
    public var fit: InharmonicityFit?

    public static func silent(target: Double, rms: Double = 0, clipping: Bool = false) -> PitchReading {
        PitchReading(
            measuredFrequency: 0,
            targetFrequency: target,
            cents: 0,
            confidence: 0,
            rms: rms,
            coarseFrequency: 0,
            isClipping: clipping,
            isRefined: false,
            detectedMidi: nil,
            fit: nil
        )
    }
}

struct SampleRing {
    private var storage: [Float]
    private var writeIndex = 0
    private(set) var count = 0

    init(capacity: Int) {
        storage = [Float](repeating: 0, count: max(1, capacity))
    }

    mutating func clear() {
        writeIndex = 0
        count = 0
    }

    mutating func append(_ samples: [Float]) {
        for sample in samples {
            storage[writeIndex] = sample
            writeIndex += 1
            if writeIndex == storage.count { writeIndex = 0 }
            if count < storage.count { count += 1 }
        }
    }

    func suffix(_ length: Int) -> [Float] {
        let n = min(length, count)
        guard n > 0 else { return [] }
        var out = [Float](repeating: 0, count: n)
        let start = (writeIndex - n + storage.count * 2) % storage.count
        for index in 0..<n {
            out[index] = storage[(start + index) % storage.count]
        }
        return out
    }
}

enum RMS {
    static func of(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        var acc = 0.0
        for sample in samples {
            let value = Double(sample)
            acc += value * value
        }
        return (acc / Double(samples.count)).squareRoot()
    }
}

public enum Synth {
    public static func sine(
        frequency: Double,
        sampleRate: Double = 48_000,
        seconds: Double,
        amplitude: Float = 0.5
    ) -> [Float] {
        let count = Int(sampleRate * seconds)
        var out = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let time = Double(index) / sampleRate
            out[index] = amplitude * Float(PB.sin(2 * PB.pi * frequency * time))
        }
        return out
    }

    public static func inharmonic(
        f1: Double,
        b: Double,
        partials: Int,
        sampleRate: Double = 48_000,
        seconds: Double,
        shiftCents: Double = 0,
        decay: Double = 0.62,
        fromPartial: Int = 1
    ) -> [Float] {
        let count = Int(sampleRate * seconds)
        var out = [Float](repeating: 0, count: count)
        let scale = Cents.shift(1, by: shiftCents)
        let first = max(1, fromPartial)
        for partial in first...max(first, partials) {
            let frequency = Inharmonicity.partialFrequency(f1: f1, n: partial, b: b) * scale
            let amplitude = Float(PB.pow(decay, Double(partial)))
            for index in 0..<count {
                let time = Double(index) / sampleRate
                out[index] += amplitude * Float(PB.sin(2 * PB.pi * frequency * time))
            }
        }
        var peak: Float = 0
        for sample in out { peak = max(peak, abs(sample)) }
        if peak > 0.0001 {
            let gain = Float(0.55) / peak
            for index in 0..<count { out[index] *= gain }
        }
        return out
    }
}

enum PartialFitter {
    static func fit(
        samples: [Float],
        sampleRate: Double,
        expectedF1: Double,
        bGuess: Double,
        searchCents: Double = 70
    ) -> InharmonicityFit? {
        let length = Fourier.bestLength(upTo: min(samples.count, 32_768))
        guard length >= 8192, expectedF1 > 0 else { return nil }
        let window = Array(samples.suffix(length))
        let magnitudes = Fourier.magnitudes(of: window)
        let noise = Spectrum.median(magnitudes)
        var guessF1 = expectedF1
        var guessB = max(0, bGuess)
        var readings: [PartialReading] = []
        for _ in 0..<2 {
            readings = locate(
                magnitudes: magnitudes,
                fftLength: length,
                sampleRate: sampleRate,
                f1: guessF1,
                b: guessB,
                searchCents: searchCents,
                noise: noise
            )
            guard let fitted = fitInliers(readings) else { return nil }
            readings = fitted.partials
            guessF1 = fitted.f1
            guessB = fitted.b
        }
        let refined = refine(readings: readings, samples: samples, sampleRate: sampleRate)
        guard let finalFit = fitInliers(refined) else { return nil }
        return finalFit
    }

    /// Drop buried partials, then peel off the worst outlier until the series agrees.
    /// High partials have a lot of leverage on B, so one bad peak would tilt the whole fit.
    private static func fitInliers(_ readings: [PartialReading]) -> InharmonicityFit? {
        guard let strongest = readings.map(\.magnitude).max(), strongest > 0 else { return nil }
        var chosen = readings.filter { $0.magnitude >= strongest * 0.05 }
        guard chosen.count >= 3 else { return nil }
        for _ in 0..<6 {
            guard let fitted = Inharmonicity.fit(partials: chosen.map { ($0.n, $0.frequency) }) else { return nil }
            let errors: [(Int, Double)] = chosen.compactMap { reading in
                let predicted = Inharmonicity.partialFrequency(f1: fitted.f1, n: reading.n, b: fitted.b)
                guard let cents = Cents.between(predicted, reading.frequency) else { return nil }
                return (reading.n, abs(cents))
            }
            guard let worst = errors.max(by: { $0.1 < $1.1 }), worst.1 > 0.35, chosen.count > 3 else {
                let residual = Inharmonicity.residualCents(
                    f1: fitted.f1,
                    b: fitted.b,
                    partials: chosen.map { ($0.n, $0.frequency) }
                )
                return InharmonicityFit(f1: fitted.f1, b: fitted.b, residualCents: residual, partials: chosen)
            }
            chosen.removeAll { $0.n == worst.0 }
        }
        return nil
    }

    private static func locate(
        magnitudes: [Float],
        fftLength: Int,
        sampleRate: Double,
        f1: Double,
        b: Double,
        searchCents: Double,
        noise: Float
    ) -> [PartialReading] {
        var readings: [PartialReading] = []
        for n in 1...10 {
            let predicted = Inharmonicity.partialFrequency(f1: f1, n: n, b: b)
            if predicted > sampleRate * 0.45 { break }
            let window = min(searchCents, Spectrum.safeSearchCents(partial: n, requested: searchCents))
            guard let peak = Spectrum.prominentPeak(
                magnitudes: magnitudes,
                fftLength: fftLength,
                sampleRate: sampleRate,
                near: predicted,
                windowCents: window
            ), peak.magnitude > noise * 6 else { continue }
            readings.append(PartialReading(n: n, frequency: peak.frequency, magnitude: Double(peak.magnitude)))
        }
        return readings
    }

    private static func refine(readings: [PartialReading], samples: [Float], sampleRate: Double) -> [PartialReading] {
        readings.map { reading in
            let tracker = HeterodyneTracker()
            tracker.start(centerFrequency: reading.frequency, sampleRate: sampleRate)
            tracker.process(samples)
            guard let estimate = tracker.estimate() else { return reading }
            return PartialReading(n: reading.n, frequency: estimate.frequency, magnitude: reading.magnitude)
        }
    }
}

enum NoteDetector {
    static func detect(
        magnitudes: [Float],
        fftLength: Int,
        sampleRate: Double,
        tunings: [NoteTuning]
    ) -> Int? {
        let noise = Spectrum.median(magnitudes)
        let peaks = Spectrum.peaks(
            magnitudes: magnitudes,
            fftLength: fftLength,
            sampleRate: sampleRate,
            minMagnitude: max(noise * 8, 1e-7),
            limit: 8
        )
        guard !peaks.isEmpty else { return nil }
        let reference = tunings.first { $0.midi == NotePitch.a4Midi }?.f1 ?? 440
        var candidates = Set<Int>()
        for peak in peaks.prefix(6) {
            for n in 1...8 {
                guard let midi = NotePitch.nearestMidi(frequency: peak.frequency / Double(n), reference: reference) else { continue }
                candidates.insert(midi)
                if midi > NotePitch.lowestMidi { candidates.insert(midi - 1) }
                if midi < NotePitch.highestMidi { candidates.insert(midi + 1) }
            }
        }
        var bestMidi = 0
        var bestScore = 0.0
        for midi in candidates {
            guard let tuning = tunings.first(where: { $0.midi == midi }) else { continue }
            var offsets: [Double] = []
            for peak in peaks {
                var closest: Double?
                for n in 1...8 {
                    let predicted = Inharmonicity.partialFrequency(f1: tuning.f1, n: n, b: tuning.b)
                    guard let cents = Cents.between(predicted, peak.frequency), abs(cents) < 45 else { continue }
                    if closest == nil || abs(cents) < abs(closest!) {
                        closest = cents
                    }
                }
                if let closest { offsets.append(closest) }
            }
            guard offsets.count >= 3, let shift = Regression.median(offsets), abs(shift) < 60 else { continue }
            let f1 = Cents.shift(tuning.f1, by: shift)
            var explained = 0
            var energy = 0.0
            for n in 1...8 {
                let predicted = Inharmonicity.partialFrequency(f1: f1, n: n, b: tuning.b)
                let matched = peaks.contains { peak in
                    guard let cents = Cents.between(predicted, peak.frequency) else { return false }
                    return abs(cents) < 25
                }
                if matched {
                    explained += 1
                    energy += 1.0 / Double(n)
                }
            }
            let unexplained = peaks.filter { peak in
                for n in 1...8 {
                    let predicted = Inharmonicity.partialFrequency(f1: f1, n: n, b: tuning.b)
                    if let cents = Cents.between(predicted, peak.frequency), abs(cents) < 25 {
                        return false
                    }
                }
                return true
            }.count
            let score = Double(explained) * 10 + energy * 3 - Double(unexplained) * 7
            if explained >= 3 && score > bestScore {
                bestScore = score
                bestMidi = midi
            }
        }
        return bestMidi == 0 ? nil : bestMidi
    }
}

public final class LivePitchTracker {
    private var ring = SampleRing(capacity: 65_536)
    private let heterodyne = HeterodyneTracker()
    private var lockedTarget = 0.0
    private var sampleRate = 0.0

    public init() {}

    public func reset() {
        ring.clear()
        heterodyne.reset()
        lockedTarget = 0
        sampleRate = 0
    }

    public func push(
        samples: [Float],
        sampleRate: Double,
        targetFrequency: Double,
        partial: Int,
        searchCents: Double = 100,
        tunings: [NoteTuning] = [],
        detectNote: Bool = false,
        measurePartials: Bool = false,
        expectedF1: Double = 0,
        bGuess: Double = 0
    ) -> PitchReading {
        if self.sampleRate != sampleRate {
            reset()
            self.sampleRate = sampleRate
        }
        ring.append(samples)
        let rms = RMS.of(samples)
        let clipping = samples.contains { abs($0) >= 0.985 }
        let targetMoved: Bool
        if lockedTarget <= 0 {
            targetMoved = true
        } else if let delta = Cents.between(lockedTarget, targetFrequency) {
            targetMoved = abs(delta) > 1.5
        } else {
            targetMoved = true
        }
        guard ring.count >= 16_384, targetFrequency > 0 else {
            return PitchReading.silent(target: targetFrequency, rms: rms, clipping: clipping)
        }
        let length = 16_384
        let window = ring.suffix(length)
        let magnitudes = Fourier.magnitudes(of: window)
        let windowCents = Spectrum.safeSearchCents(partial: partial, requested: searchCents)
        guard let peak = Spectrum.prominentPeak(
            magnitudes: magnitudes,
            fftLength: length,
            sampleRate: sampleRate,
            near: targetFrequency,
            windowCents: windowCents
        ) else {
            var reading = PitchReading.silent(target: targetFrequency, rms: rms, clipping: clipping)
            if detectNote {
                reading.detectedMidi = NoteDetector.detect(
                    magnitudes: magnitudes,
                    fftLength: length,
                    sampleRate: sampleRate,
                    tunings: tunings
                )
            }
            return reading
        }
        if targetMoved || abs(peak.frequency - heterodyne.centerFrequency) > 6 {
            heterodyne.start(centerFrequency: peak.frequency, sampleRate: sampleRate)
            heterodyne.process(ring.suffix(ring.count))
            lockedTarget = targetFrequency
        } else {
            heterodyne.process(samples)
        }
        let refined = heterodyne.estimate()
        let measured = refined?.frequency ?? peak.frequency
        let cents = Cents.between(targetFrequency, measured) ?? 0
        let prominence = Double(peak.magnitude / max(peak.noiseFloor, 1e-8))
        var confidence = min(1, max(0, (prominence - 6) / 30))
        if rms < 0.0015 { confidence = 0 }
        if refined == nil {
            confidence *= 0.5
        } else if let refined, refined.amplitude < 0.004 {
            confidence *= 0.35
        }
        var detected: Int?
        if detectNote {
            detected = NoteDetector.detect(
                magnitudes: magnitudes,
                fftLength: length,
                sampleRate: sampleRate,
                tunings: tunings
            )
        }
        var fit: InharmonicityFit?
        if measurePartials, expectedF1 > 0 {
            fit = PartialFitter.fit(
                samples: ring.suffix(min(ring.count, 48_000)),
                sampleRate: sampleRate,
                expectedF1: expectedF1,
                bGuess: bGuess
            )
        }
        return PitchReading(
            measuredFrequency: measured,
            targetFrequency: targetFrequency,
            cents: cents,
            confidence: confidence,
            rms: rms,
            coarseFrequency: peak.frequency,
            isClipping: clipping,
            isRefined: refined != nil,
            detectedMidi: detected,
            fit: fit
        )
    }
}
