import XCTest
@testable import PinblockCore

final class TuningMathTests: XCTestCase {
    func testEqualTemperamentLandmarks() {
        XCTAssertEqual(NotePitch.equalTemperament(midi: 69, reference: 440), 440, accuracy: 1e-9)
        XCTAssertEqual(NotePitch.equalTemperament(midi: 69, reference: 442), 442, accuracy: 1e-9)
        XCTAssertEqual(NotePitch.equalTemperament(midi: 81, reference: 440), 880, accuracy: 1e-9)
        XCTAssertEqual(NotePitch.equalTemperament(midi: 21, reference: 440), 27.5, accuracy: 1e-9)
        XCTAssertEqual(NotePitch.equalTemperament(midi: 60, reference: 440), 261.6255653005986, accuracy: 1e-6)
        XCTAssertEqual(NotePitch.equalTemperament(midi: 108, reference: 440), 4186.009044809578, accuracy: 1e-4)
    }

    func testNoteNamesAndCompass() {
        XCTAssertEqual(NotePitch.name(midi: 21), "A0")
        XCTAssertEqual(NotePitch.name(midi: 60), "C4")
        XCTAssertEqual(NotePitch.name(midi: 69), "A4")
        XCTAssertEqual(NotePitch.name(midi: 70), "A#4")
        XCTAssertEqual(NotePitch.name(midi: 108), "C8")
        XCTAssertEqual(NotePitch.highestMidi - NotePitch.lowestMidi + 1, 88)
        XCTAssertTrue(NotePitch.isBlackKey(midi: 70))
        XCTAssertFalse(NotePitch.isBlackKey(midi: 69))
        XCTAssertEqual(NotePitch.nearestMidi(frequency: 440, reference: 440), 69)
        XCTAssertEqual(NotePitch.nearestMidi(frequency: 27.5, reference: 440), 21)
        XCTAssertEqual(NotePitch.suggestedPartial(midi: 21), 6)
        XCTAssertEqual(NotePitch.suggestedPartial(midi: 40), 4)
        XCTAssertEqual(NotePitch.suggestedPartial(midi: 69), 2)
        XCTAssertEqual(NotePitch.suggestedPartial(midi: 108), 1)
    }

    func testCentsRoundTrip() {
        XCTAssertEqual(Cents.between(440, 880)!, 1200, accuracy: 1e-9)
        XCTAssertEqual(Cents.between(880, 440)!, -1200, accuracy: 1e-9)
        let up = Cents.shift(440, by: 0.1)
        XCTAssertEqual(Cents.between(440, up)!, 0.1, accuracy: 1e-9)
        XCTAssertEqual(Cents.shift(up, by: -0.1), 440, accuracy: 1e-6)
        XCTAssertNil(Cents.between(0, 440))
        XCTAssertNil(Cents.between(-1, 440))
    }

    func testTemperamentAnchorAndCircle() {
        for temperament in TemperamentLibrary.all {
            XCTAssertEqual(temperament.cents(forMidi: 69), 0, accuracy: 1e-8, temperament.id)
            XCTAssertEqual(temperament.frequency(midi: 69, reference: 442), 442, accuracy: 1e-6, temperament.id)
        }
        XCTAssertEqual(TemperamentLibrary.equal.offsets, Array(repeating: 0, count: 12))
    }

    func testWerckmeisterFifths() {
        let temperament = TemperamentLibrary.werckmeisterIII
        let narrow = TemperamentLibrary.pureFifth - TemperamentLibrary.pythagoreanComma / 4
        for pitchClass in [0, 2, 7, 11] {
            XCTAssertEqual(temperament.fifthCents(fromPitchClass: pitchClass), narrow, accuracy: 0.01)
        }
        for pitchClass in [1, 3, 4, 5, 6, 8, 9, 10] {
            XCTAssertEqual(temperament.fifthCents(fromPitchClass: pitchClass), TemperamentLibrary.pureFifth, accuracy: 0.01)
        }
    }

    func testVallottiAndYoung() {
        let sixth = TemperamentLibrary.pureFifth - TemperamentLibrary.pythagoreanComma / 6
        let vallotti = TemperamentLibrary.vallotti
        for pitchClass in [5, 0, 7, 2, 9, 4] {
            XCTAssertEqual(vallotti.fifthCents(fromPitchClass: pitchClass), sixth, accuracy: 0.02)
        }
        XCTAssertEqual(vallotti.fifthCents(fromPitchClass: 11), TemperamentLibrary.pureFifth, accuracy: 0.02)
        let young = TemperamentLibrary.young1799
        for pitchClass in [0, 7, 2, 9, 4, 11] {
            XCTAssertEqual(young.fifthCents(fromPitchClass: pitchClass), sixth, accuracy: 0.02)
        }
        XCTAssertEqual(young.fifthCents(fromPitchClass: 5), TemperamentLibrary.pureFifth, accuracy: 0.02)
    }

    func testKirnbergerAndMeantonePureThird() {
        let pureThird = 1200 * PB.log2(1.25)
        for temperament in [TemperamentLibrary.kirnbergerIII, TemperamentLibrary.quarterCommaMeantone] {
            let third = 400 + temperament.offsets[4] - temperament.offsets[0]
            XCTAssertEqual(third, pureThird, accuracy: 0.01, temperament.id)
        }
        let meantone = TemperamentLibrary.quarterCommaMeantone
        let wolf = meantone.fifthCents(fromPitchClass: 8)
        XCTAssertGreaterThan(wolf, TemperamentLibrary.pureFifth + 20)
        let narrow = TemperamentLibrary.pureFifth - TemperamentLibrary.syntonicComma / 4
        XCTAssertEqual(meantone.fifthCents(fromPitchClass: 0), narrow, accuracy: 0.02)
        let schisma = TemperamentLibrary.pythagoreanComma - TemperamentLibrary.syntonicComma
        XCTAssertEqual(TemperamentLibrary.kirnbergerIII.fifthCents(fromPitchClass: 6), TemperamentLibrary.pureFifth - schisma, accuracy: 0.02)
    }

    func testInharmonicityIdentityAndFit() {
        let f1 = 440.0
        let b = 0.0008
        XCTAssertEqual(Inharmonicity.partialFrequency(f1: f1, n: 1, b: b), f1, accuracy: 1e-9)
        var partials: [(n: Int, frequency: Double)] = []
        for n in 1...8 {
            partials.append((n, Inharmonicity.partialFrequency(f1: f1, n: n, b: b)))
        }
        let fitted = Inharmonicity.fit(partials: partials)!
        XCTAssertEqual(fitted.f1, f1, accuracy: 1e-6)
        XCTAssertEqual(fitted.b, b, accuracy: 1e-9)
        XCTAssertEqual(Inharmonicity.residualCents(f1: fitted.f1, b: fitted.b, partials: partials), 0, accuracy: 1e-6)
        let harmonic = (1...6).map { (n: $0, frequency: Double($0) * 220.0) }
        let flat = Inharmonicity.fit(partials: harmonic)!
        XCTAssertEqual(flat.f1, 220, accuracy: 1e-6)
        XCTAssertEqual(flat.b, 0, accuracy: 1e-8)
        let two = Inharmonicity.fit(partials: [partials[1], partials[5]])!
        XCTAssertEqual(two.b, b, accuracy: 1e-6)
        XCTAssertEqual(Inharmonicity.impliedFundamental(frequency: partials[3].frequency, n: 4, b: b)!, f1, accuracy: 1e-6)
    }

    func testInharmonicityInterpolation() {
        XCTAssertGreaterThan(Inharmonicity.defaultB(midi: 108), Inharmonicity.defaultB(midi: 69))
        XCTAssertGreaterThan(Inharmonicity.defaultB(midi: 69), Inharmonicity.defaultB(midi: 33))
        let low = InharmonicitySample(midi: 21, b: 0.001, f1: 27.5, residualCents: 0.1, partials: [])
        let high = InharmonicitySample(midi: 108, b: 0.01, f1: 4186, residualCents: 0.1, partials: [])
        let curve = Inharmonicity.bCurve(samples: [high, low])
        XCTAssertEqual(curve[0], 0.001, accuracy: 1e-12)
        XCTAssertEqual(curve[87], 0.01, accuracy: 1e-12)
        let midi = 64
        let t = Double(midi - 21) / Double(108 - 21)
        let expected = pow(0.001, 1 - t) * pow(0.01, t)
        XCTAssertEqual(curve[midi - 21], expected, accuracy: 1e-12)
        let only = InharmonicitySample(midi: 69, b: Inharmonicity.defaultB(midi: 69) * 2, f1: 440, residualCents: 0, partials: [])
        let scaled = Inharmonicity.bCurve(samples: [only])
        XCTAssertEqual(scaled[69 - 21], Inharmonicity.defaultB(midi: 69) * 2, accuracy: 1e-12)
        XCTAssertEqual(scaled[81 - 21], Inharmonicity.defaultB(midi: 81) * 2, accuracy: 1e-9)
    }

    func testPitchRaiseDoesNotChaseAndStaysPositive() {
        XCTAssertEqual(PitchRaise.overshootCents(flatnessCents: 0, userPercent: 25), 0)
        XCTAssertEqual(PitchRaise.overshootCents(flatnessCents: -10, userPercent: 25), 0)
        let mild = PitchRaise.overshootCents(flatnessCents: 10, userPercent: 25)
        XCTAssertGreaterThan(mild, 2)
        XCTAssertLessThan(mild, 5)
        let large = PitchRaise.overshootCents(flatnessCents: 40, userPercent: 25)
        XCTAssertGreaterThan(large, 10)
        XCTAssertLessThan(large, 20)
        let target = PitchRaise.targetFrequency(finalFrequency: 440, overshootCents: large)
        XCTAssertEqual(Cents.between(440, target)!, large, accuracy: 1e-6)
    }

    func testAutoAdvanceAndMeasurementConsensus() {
        var tracker = AutoAdvanceTracker(thresholdCents: 1, holdSeconds: 1, minimumConfidence: 0.5)
        XCTAssertFalse(tracker.consume(cents: 0.4, confidence: 0.9, now: 0))
        XCTAssertFalse(tracker.consume(cents: 0.4, confidence: 0.9, now: 0.9))
        XCTAssertTrue(tracker.consume(cents: 0.2, confidence: 0.9, now: 1.1))
        XCTAssertFalse(tracker.consume(cents: 5, confidence: 0.9, now: 2))
        XCTAssertFalse(tracker.consume(cents: 0.1, confidence: 0.1, now: 3))
        XCTAssertFalse(tracker.consume(cents: 0.1, confidence: 0.9, now: 3.2))

        var accumulator = MeasurementAccumulator()
        for index in 0..<5 {
            let wobble = Double(index - 2) * 0.000001
            accumulator.add(InharmonicityFit(f1: 440 + Double(index - 2) * 0.01, b: 0.0008 + wobble, residualCents: 0.2, partials: [
                PartialReading(n: 1, frequency: 440, magnitude: 1),
                PartialReading(n: 2, frequency: 880, magnitude: 1),
                PartialReading(n: 3, frequency: 1320, magnitude: 1)
            ]))
        }
        let consensus = accumulator.consensus!
        XCTAssertEqual(consensus.b, 0.0008, accuracy: 0.00001)
        XCTAssertEqual(consensus.f1, 440, accuracy: 0.05)
        accumulator.reset()
        accumulator.add(InharmonicityFit(f1: 440, b: 0.001, residualCents: 0, partials: []))
        XCTAssertNil(accumulator.consensus)
    }

    func testDocumentRoundTripKeepsA4() throws {
        var document = PianoDocument.makeNew(name: "Steinway B", now: Date(timeIntervalSince1970: 1_700_000_000))
        document.comments = "Front room"
        document.temperamentID = TemperamentLibrary.vallotti.id
        document.recalculate(now: document.createdAt)
        let data = try PinblockJSON.encoder().encode(document)
        let decoded = try PinblockJSON.decoder().decode(PianoDocument.self, from: data)
        XCTAssertEqual(decoded.name, "Steinway B")
        XCTAssertEqual(decoded.comments, "Front room")
        XCTAssertEqual(decoded.curve.count, 88)
        XCTAssertEqual(decoded.tuning(midi: 69)!.f1, 440, accuracy: 1e-6)
        XCTAssertEqual(decoded.temperamentID, "vallotti")
    }
}
