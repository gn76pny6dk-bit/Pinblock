struct SpectralPeak {
    var frequency: Double
    var magnitude: Float
    var bin: Int
    var noiseFloor: Float
}

enum Spectrum {
    static func frequency(bin: Int, fftLength: Int, sampleRate: Double) -> Double {
        Double(bin) * sampleRate / Double(fftLength)
    }

    static func interpolatedMagnitude(
        _ magnitudes: [Float],
        fftLength: Int,
        sampleRate: Double,
        frequency: Double
    ) -> Float {
        guard fftLength > 0, sampleRate > 0, magnitudes.count > 1 else { return 0 }
        let position = frequency * Double(fftLength) / sampleRate
        let lower = Int(position)
        let fraction = Float(position - Double(lower))
        if lower <= 0 { return magnitudes[0] }
        if lower >= magnitudes.count - 1 { return magnitudes[magnitudes.count - 1] }
        return magnitudes[lower] * (1 - fraction) + magnitudes[lower + 1] * fraction
    }

    static func median(_ magnitudes: [Float]) -> Float {
        guard !magnitudes.isEmpty else { return 0 }
        let sorted = magnitudes.sorted()
        return sorted[sorted.count / 2]
    }

    static func refinedFrequency(magnitudes: [Float], bin: Int, fftLength: Int, sampleRate: Double) -> Double {
        guard bin > 0, bin < magnitudes.count - 1 else {
            return frequency(bin: bin, fftLength: fftLength, sampleRate: sampleRate)
        }
        let alpha = PB.ln(max(Double(magnitudes[bin - 1]), 1e-20))
        let beta = PB.ln(max(Double(magnitudes[bin]), 1e-20))
        let gamma = PB.ln(max(Double(magnitudes[bin + 1]), 1e-20))
        let denominator = alpha - 2 * beta + gamma
        var delta = 0.0
        if abs(denominator) > 1e-12 {
            delta = 0.5 * (alpha - gamma) / denominator
        }
        delta = min(0.5, max(-0.5, delta))
        return (Double(bin) + delta) * sampleRate / Double(fftLength)
    }

    static func prominentPeak(
        magnitudes: [Float],
        fftLength: Int,
        sampleRate: Double,
        near target: Double,
        windowCents: Double
    ) -> SpectralPeak? {
        guard target > 0, magnitudes.count > 4 else { return nil }
        let low = Cents.shift(target, by: -windowCents)
        let high = Cents.shift(target, by: windowCents)
        var first = Int(low / sampleRate * Double(fftLength))
        var last = Int(high / sampleRate * Double(fftLength)) + 1
        first = min(max(1, first), magnitudes.count - 2)
        last = min(max(first, last), magnitudes.count - 2)
        var bestBin = first
        var bestMagnitude = magnitudes[first]
        if first <= last {
            for bin in first...last where magnitudes[bin] > bestMagnitude {
                bestMagnitude = magnitudes[bin]
                bestBin = bin
            }
        }
        guard bestBin > 0, bestBin < magnitudes.count - 1 else { return nil }
        guard magnitudes[bestBin] >= magnitudes[bestBin - 1], magnitudes[bestBin] >= magnitudes[bestBin + 1] else {
            return nil
        }
        let noise = median(magnitudes)
        let frequency = refinedFrequency(
            magnitudes: magnitudes,
            bin: bestBin,
            fftLength: fftLength,
            sampleRate: sampleRate
        )
        return SpectralPeak(frequency: frequency, magnitude: bestMagnitude, bin: bestBin, noiseFloor: noise)
    }

    static func peaks(
        magnitudes: [Float],
        fftLength: Int,
        sampleRate: Double,
        minMagnitude: Float,
        limit: Int
    ) -> [SpectralPeak] {
        let noise = median(magnitudes)
        var found: [SpectralPeak] = []
        guard magnitudes.count > 4 else { return [] }
        for bin in 2..<(magnitudes.count - 2) {
            let mag = magnitudes[bin]
            guard mag >= minMagnitude, mag >= magnitudes[bin - 1], mag > magnitudes[bin + 1] else { continue }
            let frequency = refinedFrequency(magnitudes: magnitudes, bin: bin, fftLength: fftLength, sampleRate: sampleRate)
            found.append(SpectralPeak(frequency: frequency, magnitude: mag, bin: bin, noiseFloor: noise))
        }
        found.sort { $0.magnitude > $1.magnitude }
        if found.count > limit {
            found.removeLast(found.count - limit)
        }
        return found
    }

    /// Keep the search window from reaching the neighboring partial.
    static func safeSearchCents(partial: Int, requested: Double) -> Double {
        let n = max(1, partial)
        let spacing = 1200 * PB.log2(Double(n + 1) / Double(n))
        return min(max(8, requested), spacing * 0.4)
    }
}
