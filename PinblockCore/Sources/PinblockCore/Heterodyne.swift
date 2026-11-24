/// Streaming quadrature demodulator.
///
/// The oscillator sits on a coarse FFT estimate. A one-pole lowpass rejects every
/// partial except the one being measured, and a linear fit to the unwrapped
/// baseband phase gives the residual frequency. A real lowpass does not bias that
/// frequency. The first 0.35 s are discarded so the filter transient can die.
final class HeterodyneTracker {
    private(set) var centerFrequency: Double = 0
    private var sampleRate: Double = 0
    private var phase = 0.0
    private var iState = 0.0
    private var qState = 0.0
    private var sampleIndex = 0
    private var times: [Double] = []
    private var iSamples: [Double] = []
    private var qSamples: [Double] = []
    private let decimation = 8
    private let settleSeconds = 0.35

    func reset() {
        centerFrequency = 0
        sampleRate = 0
        phase = 0
        iState = 0
        qState = 0
        sampleIndex = 0
        times.removeAll(keepingCapacity: true)
        iSamples.removeAll(keepingCapacity: true)
        qSamples.removeAll(keepingCapacity: true)
    }

    func start(centerFrequency: Double, sampleRate: Double) {
        reset()
        self.centerFrequency = centerFrequency
        self.sampleRate = sampleRate
    }

    func process(_ samples: [Float]) {
        guard centerFrequency > 0, sampleRate > 0 else { return }
        let cutoff = centerFrequency < 1500 ? 8.0 : 20.0
        let alpha = 1 - PB.exp(-2 * PB.pi * cutoff / sampleRate)
        let dPhase = 2 * PB.pi * centerFrequency / sampleRate
        for sample in samples {
            let cosine = PB.cos(phase)
            let sine = PB.sin(phase)
            phase += dPhase
            if phase >= 2 * PB.pi { phase -= 2 * PB.pi }
            let x = Double(sample)
            iState += alpha * (x * cosine - iState)
            qState += alpha * (x * (-sine) - qState)
            if sampleIndex % decimation == 0 {
                let time = Double(sampleIndex) / sampleRate
                if time > settleSeconds {
                    times.append(time)
                    iSamples.append(iState)
                    qSamples.append(qState)
                }
            }
            sampleIndex += 1
        }
        let maxCount = Int(sampleRate / Double(decimation) * 2.5)
        if times.count > maxCount {
            let drop = times.count - maxCount
            times.removeFirst(drop)
            iSamples.removeFirst(drop)
            qSamples.removeFirst(drop)
        }
    }

    /// Absolute frequency and mean baseband amplitude, once the filter has settled.
    func estimate() -> (frequency: Double, amplitude: Double)? {
        let count = times.count
        guard count >= 40 else { return nil }
        var unwrapped = [Double](repeating: 0, count: count)
        unwrapped[0] = PB.atan2(qSamples[0], iSamples[0])
        var previous = unwrapped[0]
        var amplitude = 0.0
        for index in 0..<count {
            amplitude += (iSamples[index] * iSamples[index] + qSamples[index] * qSamples[index]).squareRoot()
            if index == 0 { continue }
            let angle = PB.atan2(qSamples[index], iSamples[index])
            var delta = angle - previous
            if delta > PB.pi { delta -= 2 * PB.pi }
            if delta < -PB.pi { delta += 2 * PB.pi }
            previous = angle
            unwrapped[index] = unwrapped[index - 1] + delta
        }
        amplitude /= Double(count)
        guard amplitude > 1e-6 else { return nil }
        var sumT = 0.0
        var sumP = 0.0
        var sumTT = 0.0
        var sumTP = 0.0
        for index in 0..<count {
            let time = times[index]
            let phase = unwrapped[index]
            sumT += time
            sumP += phase
            sumTT += time * time
            sumTP += time * phase
        }
        let n = Double(count)
        let denominator = n * sumTT - sumT * sumT
        guard abs(denominator) > 1e-12 else { return nil }
        let slope = (n * sumTP - sumT * sumP) / denominator
        return (centerFrequency + slope / (2 * PB.pi), amplitude)
    }
}
