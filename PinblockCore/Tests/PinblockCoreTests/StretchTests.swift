import XCTest
@testable import PinblockCore

final class StretchTests: XCTestCase {
    func testZeroInharmonicityIsTemperedEqualTemperament() {
        for preset in [OctavePreset.twoToOne, .fourToTwo, .sixToThree, .balanced, .register] {
            let curve = curve(b: 0, preset: preset, temperament: TemperamentLibrary.vallotti)
            for note in curve {
                let expected = TemperamentLibrary.vallotti.cents(forMidi: note.midi)
                XCTAssertEqual(note.centsFromEqual, expected, accuracy: 0.02, "\(preset) \(note.midi)")
                XCTAssertEqual(note.f1, TemperamentLibrary.vallotti.frequency(midi: note.midi, reference: 440), accuracy: 0.05)
            }
        }
    }

    func testA4StaysOnTheReference() {
        let curve = PianoDocument.makeNew(name: "Test").curve
        XCTAssertEqual(curve[69 - 21].f1, 440, accuracy: 1e-6)
        XCTAssertEqual(curve[69 - 21].centsFromEqual, 0, accuracy: 0.01)
    }

    func testFourToTwoPartialsLineUp() {
        let curve = curve(preset: .fourToTwo)
        assertOctaves(curve: curve, lowerPartial: 4, upperPartial: 2, tolerance: 0.08)
    }

    func testTwoToOneAndSixToThreePartialsLineUp() {
        assertOctaves(curve: curve(preset: .twoToOne), lowerPartial: 2, upperPartial: 1, tolerance: 0.08)
        assertOctaves(curve: curve(preset: .sixToThree), lowerPartial: 6, upperPartial: 3, tolerance: 0.12)
    }

    func testBlendIsTheCentsAverageOfItsStyles() {
        let b = 0.001
        let weights = OctaveWeights(w21: 0.5, w42: 0.5, w63: 0)
        let blended = CurveBuilder.octaveStretchCents(bLower: b, bUpper: b, weights: weights)
        let two = CurveBuilder.octaveStretchCents(bLower: b, bUpper: b, weights: OctaveWeights(w21: 1, w42: 0, w63: 0))
        let four = CurveBuilder.octaveStretchCents(bLower: b, bUpper: b, weights: OctaveWeights(w21: 0, w42: 1, w63: 0))
        XCTAssertEqual(blended, 0.5 * (two + four), accuracy: 1e-9)
        XCTAssertGreaterThan(four, two)
    }

    func testDefaultCurveHasRailsbackShape() {
        let curve = PianoDocument.makeNew(name: "Grand").curve
        let a0 = curve[0].centsFromEqual
        let a3 = curve[57 - 21].centsFromEqual
        let a4 = curve[69 - 21].centsFromEqual
        let a5 = curve[81 - 21].centsFromEqual
        let c8 = curve[87].centsFromEqual
        XCTAssertLessThan(a0, -12)
        XCTAssertLessThan(a0, a3)
        XCTAssertLessThan(a3, a4 + 0.2)
        XCTAssertEqual(a4, 0, accuracy: 0.05)
        XCTAssertGreaterThan(a5, 2)
        XCTAssertGreaterThan(c8, 20)
        XCTAssertLessThan(c8, 50)
    }

    func testTemperamentSurvivesOnTopOfStretch() {
        var document = PianoDocument.makeNew(name: "Meantone")
        document.temperamentID = TemperamentLibrary.quarterCommaMeantone.id
        document.octavePreset = .fourToTwo
        document.recalculate()
        let c4 = document.tuning(midi: 60)!
        let equalC4 = NotePitch.equalTemperament(midi: 60, reference: 440)
        let stretchedEqual = curve(preset: .fourToTwo).first { $0.midi == 60 }!
        let temperamentOnly = TemperamentLibrary.quarterCommaMeantone.cents(forMidi: 60)
        let actual = Cents.between(equalC4, c4.f1)!
        XCTAssertEqual(actual, stretchedEqual.centsFromEqual + temperamentOnly, accuracy: 0.15)
    }

    private func curve(
        b: Double? = nil,
        preset: OctavePreset,
        temperament: Temperament = TemperamentLibrary.equal
    ) -> [NoteTuning] {
        let samples: [InharmonicitySample]
        if let b {
            samples = (NotePitch.lowestMidi...NotePitch.highestMidi).map {
                InharmonicitySample(midi: $0, b: b, f1: 1, residualCents: 0, partials: [])
            }
        } else {
            samples = []
        }
        return CurveBuilder.build(
            CurveRequest(
                referencePitch: 440,
                temperament: temperament,
                octavePreset: preset,
                customWeights: OctaveWeights(w21: 0.2, w42: 0.55, w63: 0.25),
                samples: samples
            )
        )
    }

    private func assertOctaves(curve: [NoteTuning], lowerPartial: Int, upperPartial: Int, tolerance: Double) {
        for midi in [21, 33, 45, 57, 69, 76, 81, 93] {
            let lower = curve[midi - 21]
            let upper = curve[midi + 12 - 21]
            let low = Inharmonicity.partialFrequency(f1: lower.f1, n: lowerPartial, b: lower.b)
            let high = Inharmonicity.partialFrequency(f1: upper.f1, n: upperPartial, b: upper.b)
            XCTAssertEqual(Cents.between(low, high)!, 0, accuracy: tolerance, "octave \(midi)")
        }
    }
}
