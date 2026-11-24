import Foundation

public struct PianoDocument: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var comments: String
    public var createdAt: Date
    public var updatedAt: Date
    public var referencePitch: Double
    public var temperamentID: String
    public var octavePreset: OctavePreset
    public var customWeights: OctaveWeights
    public var samples: [InharmonicitySample]
    public var pitchRaiseEnabled: Bool
    public var overpullPercent: Double
    /// How many cents flat the piano was when the pitch raise was planned. Positive means flat.
    public var recordedFlatnessCents: Double
    public var curve: [NoteTuning]

    public init(
        id: UUID,
        name: String,
        comments: String,
        createdAt: Date,
        updatedAt: Date,
        referencePitch: Double,
        temperamentID: String,
        octavePreset: OctavePreset,
        customWeights: OctaveWeights,
        samples: [InharmonicitySample],
        pitchRaiseEnabled: Bool,
        overpullPercent: Double,
        recordedFlatnessCents: Double,
        curve: [NoteTuning]
    ) {
        self.id = id
        self.name = name
        self.comments = comments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.referencePitch = referencePitch
        self.temperamentID = temperamentID
        self.octavePreset = octavePreset
        self.customWeights = customWeights
        self.samples = samples
        self.pitchRaiseEnabled = pitchRaiseEnabled
        self.overpullPercent = overpullPercent
        self.recordedFlatnessCents = recordedFlatnessCents
        self.curve = curve
    }

    public static func makeNew(name: String, now: Date = Date()) -> PianoDocument {
        var document = PianoDocument(
            id: UUID(),
            name: name,
            comments: "",
            createdAt: now,
            updatedAt: now,
            referencePitch: 440,
            temperamentID: TemperamentLibrary.equal.id,
            octavePreset: .register,
            customWeights: OctaveWeights(w21: 0.20, w42: 0.55, w63: 0.25),
            samples: [],
            pitchRaiseEnabled: false,
            overpullPercent: 25,
            recordedFlatnessCents: 0,
            curve: []
        )
        document.recalculate(now: now)
        return document
    }

    public var temperament: Temperament {
        TemperamentLibrary.named(temperamentID)
    }

    public var usesMeasuredInharmonicity: Bool {
        samples.count >= 3
    }

    public func tuning(midi: Int) -> NoteTuning? {
        guard let index = NotePitch.index(midi: midi), curve.indices.contains(index), curve[index].midi == midi else {
            return curve.first { $0.midi == midi }
        }
        return curve[index]
    }

    public mutating func recalculate(now: Date = Date()) {
        curve = CurveBuilder.build(
            CurveRequest(
                referencePitch: referencePitch,
                temperament: temperament,
                octavePreset: octavePreset,
                customWeights: customWeights,
                samples: samples
            )
        )
        updatedAt = now
    }

    public static let measureTargets: [Int] = [21, 33, 45, 57, 69, 81, 93, 105]
}

public enum PinblockJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
