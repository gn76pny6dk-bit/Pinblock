import AVFoundation
import Foundation
import Observation
import PinblockCore
import UIKit

enum MicPermission: Equatable {
    case unknown
    case granted
    case denied
}

enum ListenMode: Equatable {
    case tune
    case measure
}

struct AnalysisSnapshot: Equatable {
    var targetFrequency: Double = 440
    var partial: Int = 1
    var searchCents: Double = 90
    var tunings: [NoteTuning] = []
    var detectNote = false
    var measurePartials = false
    var expectedF1: Double = 440
    var bGuess: Double = 0.0004
}

final class AnalysisBridge: @unchecked Sendable {
    var onResult: ((PitchReading) -> Void)?
    private let queue = DispatchQueue(label: "pinblock.analysis", qos: .userInteractive)
    private let lock = NSLock()
    private var snapshot = AnalysisSnapshot()
    private let tracker = LivePitchTracker()
    private var measureCounter = 0

    func update(_ snapshot: AnalysisSnapshot) {
        lock.lock()
        self.snapshot = snapshot
        lock.unlock()
    }

    func submit(samples: [Float], sampleRate: Double) {
        queue.async { [weak self] in
            self?.process(samples, sampleRate)
        }
    }

    private func process(_ samples: [Float], _ sampleRate: Double) {
        lock.lock()
        let snap = snapshot
        measureCounter += 1
        let measureNow = snap.measurePartials && measureCounter % 3 == 0
        lock.unlock()
        let reading = tracker.push(
            samples: samples,
            sampleRate: sampleRate,
            targetFrequency: snap.targetFrequency,
            partial: snap.partial,
            searchCents: snap.searchCents,
            tunings: snap.tunings,
            detectNote: snap.detectNote,
            measurePartials: measureNow,
            expectedF1: snap.expectedF1,
            bGuess: snap.bGuess
        )
        onResult?(reading)
    }
}

@MainActor
@Observable
final class TunerSession {
    var selectedMidi = NotePitch.a4Midi
    var partial = 2
    var suggestPartials = true
    var autoNote = false
    var autoAdvanceEnabled = false
    var advanceThreshold = 1.5
    var advanceHold = 1.2
    var advanceDirection = 1
    var strobeSensitivity = 1.0
    var permission: MicPermission = .unknown
    var isRunning = false
    var statusMessage: String?
    var reading = PitchReading.silent(target: 440)
    var mode: ListenMode = .tune
    var inTuneToken = 0
    private(set) var consensus: InharmonicityFit?

    private var partialLocked = false
    private var advance = AutoAdvanceTracker()
    private var pendingMidi: Int?
    private var pendingCount = 0
    private var measureAccumulator = MeasurementAccumulator()
    private var piano = PianoDocument.makeNew(name: "My piano")
    private var wasInTune = false
    private let bridge = AnalysisBridge()
    private let audio = AudioCapture()

    var overshootCents: Double {
        guard piano.pitchRaiseEnabled else { return 0 }
        return PitchRaise.overshootCents(
            flatnessCents: piano.recordedFlatnessCents,
            userPercent: piano.overpullPercent
        )
    }

    var centsFromCurve: Double {
        reading.cents + overshootCents
    }

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.suggest) != nil {
            suggestPartials = defaults.bool(forKey: Keys.suggest)
        }
        autoNote = defaults.bool(forKey: Keys.autoNote)
        autoAdvanceEnabled = defaults.bool(forKey: Keys.advance)
        if defaults.object(forKey: Keys.threshold) != nil {
            advanceThreshold = defaults.double(forKey: Keys.threshold)
        }
        if defaults.object(forKey: Keys.hold) != nil {
            advanceHold = defaults.double(forKey: Keys.hold)
        }
        if defaults.object(forKey: Keys.direction) != nil {
            advanceDirection = defaults.integer(forKey: Keys.direction)
        }
        if defaults.object(forKey: Keys.sensitivity) != nil {
            strobeSensitivity = defaults.double(forKey: Keys.sensitivity)
        }
        partial = NotePitch.suggestedPartial(midi: selectedMidi)
        syncAdvance()
        let bridge = self.bridge
        audio.onSamples = { samples, rate in
            bridge.submit(samples: samples, sampleRate: rate)
        }
        bridge.onResult = { [weak self] reading in
            Task { @MainActor in
                self?.apply(reading)
            }
        }
    }

    func use(piano: PianoDocument?) {
        guard let piano else { return }
        self.piano = piano
        pushSnapshot()
    }

    func prepare() async {
        if permission == .granted {
            startEngine()
            return
        }
        let granted = await AVAudioApplication.requestRecordPermission()
        permission = granted ? .granted : .denied
        if granted {
            startEngine()
        } else {
            statusMessage = "Microphone access is off. Enable it in Settings to tune."
        }
    }

    func startEngine() {
        do {
            try audio.start()
            isRunning = true
            if permission == .granted {
                statusMessage = nil
            }
            UIApplication.shared.isIdleTimerDisabled = true
            pushSnapshot()
        } catch {
            isRunning = false
            statusMessage = error.localizedDescription
        }
    }

    func stopEngine() {
        audio.stop()
        isRunning = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func select(midi: Int) {
        let clamped = min(NotePitch.highestMidi, max(NotePitch.lowestMidi, midi))
        guard clamped != selectedMidi else { return }
        selectedMidi = clamped
        partialLocked = false
        if suggestPartials {
            partial = NotePitch.suggestedPartial(midi: clamped)
        }
        advance.reset()
        measureAccumulator.reset()
        consensus = nil
        pendingMidi = nil
        pendingCount = 0
        pushSnapshot()
    }

    func step(_ delta: Int) {
        select(midi: selectedMidi + delta)
    }

    func setPartial(_ value: Int) {
        partial = value
        partialLocked = true
        pushSnapshot()
    }

    func setMode(_ mode: ListenMode) {
        self.mode = mode
        if mode == .measure {
            measureAccumulator.reset()
            consensus = nil
        }
        pushSnapshot()
    }

    func keepMeasurement() -> InharmonicitySample? {
        guard let consensus else { return nil }
        return InharmonicitySample(
            midi: selectedMidi,
            b: consensus.b,
            f1: consensus.f1,
            residualCents: consensus.residualCents,
            partials: consensus.partials
        )
    }

    func recordFlatnessFromCurrentNote() -> Double? {
        guard reading.confidence > 0.35, reading.measuredFrequency > 0 else { return nil }
        let flatness = max(0, -centsFromCurve)
        return flatness
    }

    func persistPreferences() {
        let defaults = UserDefaults.standard
        syncAdvance()
        defaults.set(suggestPartials, forKey: Keys.suggest)
        defaults.set(autoNote, forKey: Keys.autoNote)
        defaults.set(autoAdvanceEnabled, forKey: Keys.advance)
        defaults.set(advanceThreshold, forKey: Keys.threshold)
        defaults.set(advanceHold, forKey: Keys.hold)
        defaults.set(advanceDirection, forKey: Keys.direction)
        defaults.set(strobeSensitivity, forKey: Keys.sensitivity)
        if suggestPartials && !partialLocked {
            partial = NotePitch.suggestedPartial(midi: selectedMidi)
        }
        pushSnapshot()
    }

    private func apply(_ reading: PitchReading) {
        self.reading = reading
        if autoNote, let midi = reading.detectedMidi, reading.confidence > 0.35 {
            if midi == pendingMidi {
                pendingCount += 1
            } else {
                pendingMidi = midi
                pendingCount = 1
            }
            if pendingCount >= 3, midi != selectedMidi {
                select(midi: midi)
            }
        }
        if mode == .measure, let fit = reading.fit {
            measureAccumulator.add(fit)
            consensus = measureAccumulator.consensus
        }
        let steady = reading.isRefined && abs(reading.cents) <= advanceThreshold && reading.confidence >= 0.55
        if autoAdvanceEnabled && !autoNote && steady {
            let now = Date().timeIntervalSinceReferenceDate
            if advance.consume(cents: reading.cents, confidence: reading.confidence, now: now) {
                let next = selectedMidi + (advanceDirection >= 0 ? 1 : -1)
                if (NotePitch.lowestMidi...NotePitch.highestMidi).contains(next) {
                    select(midi: next)
                }
            }
        } else if !steady {
            advance.reset()
        }
        let inTune = reading.isRefined && reading.confidence > 0.45 && abs(reading.cents) < 0.5
        if inTune && !wasInTune {
            inTuneToken += 1
        }
        wasInTune = inTune
    }

    private func syncAdvance() {
        advance.thresholdCents = advanceThreshold
        advance.holdSeconds = advanceHold
    }

    private func pushSnapshot() {
        let tuning = piano.tuning(midi: selectedMidi)
        let f1 = tuning?.f1 ?? NotePitch.equalTemperament(midi: selectedMidi, reference: piano.referencePitch)
        let b = tuning?.b ?? Inharmonicity.defaultB(midi: selectedMidi)
        let partialFrequency = Inharmonicity.partialFrequency(f1: f1, n: partial, b: b)
        let target = PitchRaise.targetFrequency(finalFrequency: partialFrequency, overshootCents: overshootCents)
        let search: Double = piano.pitchRaiseEnabled && piano.recordedFlatnessCents > 15 ? 140 : 90
        bridge.update(
            AnalysisSnapshot(
                targetFrequency: target,
                partial: partial,
                searchCents: search,
                tunings: piano.curve,
                detectNote: autoNote,
                measurePartials: mode == .measure,
                expectedF1: f1,
                bGuess: b
            )
        )
    }

    private enum Keys {
        static let suggest = "pinblock.suggestPartials"
        static let autoNote = "pinblock.autoNote"
        static let advance = "pinblock.autoAdvance"
        static let threshold = "pinblock.advanceThreshold"
        static let hold = "pinblock.advanceHold"
        static let direction = "pinblock.advanceDirection"
        static let sensitivity = "pinblock.strobeSensitivity"
    }
}
