import XCTest
@testable import PinblockCore

final class DSPTests: XCTestCase {
    func testSwiftFFTMatchesDirectDFT() {
        let n = 64
        var samples = [Double](repeating: 0, count: n)
        for time in 0..<n {
            samples[time] = sin(2 * Double.pi * Double(time * 5) / Double(n))
        }
        let transformed = SwiftFourier.forward(real: samples)
        var real = 0.0
        var imag = 0.0
        for time in 0..<n {
            let angle = -2 * Double.pi * Double(5 * time) / Double(n)
            real += samples[time] * cos(angle)
            imag += samples[time] * sin(angle)
        }
        XCTAssertEqual(transformed.re[5], real, accuracy: 1e-6)
        XCTAssertEqual(transformed.im[5], imag, accuracy: 1e-6)
    }

    func testSineIsMeasuredToATenthOfACent() {
        let cases: [(Double, Double)] = [
            (55, 0.1),
            (110, -0.1),
            (440, 0.1),
            (440, -3),
            (4186.009, 0.1)
        ]
        for (base, offset) in cases {
            let frequency = Cents.shift(base, by: offset)
            let samples = Synth.sine(frequency: frequency, seconds: 1.2)
            let reading = LivePitchTracker().push(
                samples: samples,
                sampleRate: 48_000,
                targetFrequency: base,
                partial: 1
            )
            XCTAssertTrue(reading.isRefined, "refined \(base)")
            XCTAssertGreaterThan(reading.confidence, 0.4, "confidence \(base)")
            XCTAssertEqual(reading.cents, offset, accuracy: 0.1, "cents \(base) \(offset)")
        }
    }

    func testInharmonicPartialAndInterferingHarmonic() {
        let f1 = 110.0
        let b = 0.0008
        let target = Inharmonicity.partialFrequency(f1: f1, n: 4, b: b)
        let samples = Synth.inharmonic(f1: f1, b: b, partials: 7, seconds: 1.2, shiftCents: 0.2)
        let reading = LivePitchTracker().push(
            samples: samples,
            sampleRate: 48_000,
            targetFrequency: target,
            partial: 4,
            searchCents: 40
        )
        XCTAssertEqual(reading.cents, 0.2, accuracy: 0.1)
        XCTAssertGreaterThan(reading.confidence, 0.35)
    }

    func testChunkedTrackerSettles() {
        let target = 440.0
        let frequency = Cents.shift(target, by: -0.1)
        let samples = Synth.sine(frequency: frequency, seconds: 1.3)
        let tracker = LivePitchTracker()
        var last = PitchReading.silent(target: target)
        var index = 0
        while index < samples.count {
            let end = min(index + 4096, samples.count)
            last = tracker.push(
                samples: Array(samples[index..<end]),
                sampleRate: 48_000,
                targetFrequency: target,
                partial: 1
            )
            index = end
        }
        XCTAssertTrue(last.isRefined)
        XCTAssertEqual(last.cents, -0.1, accuracy: 0.1)
    }

    func testSilenceIsNotAPitch() {
        let samples = [Float](repeating: 0, count: 48_000)
        let reading = LivePitchTracker().push(
            samples: samples,
            sampleRate: 48_000,
            targetFrequency: 440,
            partial: 1
        )
        XCTAssertEqual(reading.confidence, 0, accuracy: 0.001)
        XCTAssertFalse(reading.isRefined)
    }

    func testPartialFitRecoversBFromADetunedNote() {
        let f1 = 220.0
        let b = 0.00045
        let samples = Synth.inharmonic(f1: f1, b: b, partials: 8, seconds: 1.2, shiftCents: 8)
        let fit = PartialFitter.fit(
            samples: samples,
            sampleRate: 48_000,
            expectedF1: f1,
            bGuess: 0.0002
        )!
        XCTAssertEqual(Cents.between(f1, fit.f1)!, 8, accuracy: 0.3)
        XCTAssertEqual(fit.b, b, accuracy: b * 0.08)
        XCTAssertLessThan(fit.residualCents, 0.5)
        XCTAssertGreaterThanOrEqual(fit.partials.count, 4)
    }

    func testNoteDetectorFindsMidrangeAndBassWithoutFundamental() {
        let document = PianoDocument.makeNew(name: "Detect")
        let a4 = document.tuning(midi: 69)!
        let a4Tone = Synth.inharmonic(f1: a4.f1, b: a4.b, partials: 6, seconds: 1.0)
        let a4Midi = detect(a4Tone, tunings: document.curve)
        XCTAssertEqual(a4Midi, 69)

        let a1 = document.tuning(midi: 33)!
        let a1Tone = Synth.inharmonic(f1: a1.f1, b: a1.b, partials: 8, seconds: 1.0, fromPartial: 2)
        let a1Midi = detect(a1Tone, tunings: document.curve)
        XCTAssertEqual(a1Midi, 33)
    }

    func testAccelerateAgreesWithTheReferenceFFT() {
        #if canImport(Accelerate)
        let samples = Synth.sine(frequency: 440 * pow(2, 0.3 / 1200), seconds: 16_384.0 / 48_000)
        let accelerate = AccelerateFourier.magnitudes(of: samples)
        let reference = SwiftFourier.magnitudes(of: samples)
        func peakBin(_ magnitudes: [Float]) -> Int {
            var best = 1
            for bin in 1..<(magnitudes.count - 1) where magnitudes[bin] > magnitudes[best] {
                best = bin
            }
            return best
        }
        XCTAssertEqual(peakBin(accelerate), peakBin(reference))
        #else
        XCTAssertTrue(true)
        #endif
    }

    private func detect(_ samples: [Float], tunings: [NoteTuning]) -> Int? {
        let length = 16_384
        let magnitudes = Fourier.magnitudes(of: Array(samples.prefix(length)))
        return NoteDetector.detect(magnitudes: magnitudes, fftLength: length, sampleRate: 48_000, tunings: tunings)
    }
}
