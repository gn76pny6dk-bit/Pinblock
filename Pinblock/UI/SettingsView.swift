import PinblockCore
import SwiftUI

struct SettingsView: View {
    @Environment(TunerSession.self) private var session
    @Environment(TuningStore.self) private var store

    var body: some View {
        Screen {
            Form {
                referenceSection
                temperamentSection
                octaveSection
                pitchRaiseSection
                listeningSection
                notesSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var referenceSection: some View {
        Section {
            HStack {
                Text("A4")
                Spacer()
                Text(String(format: "%.1f Hz", store.active?.referencePitch ?? 440))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Theme.amber)
            }
            Slider(
                value: referenceBinding,
                in: 415...466,
                step: 0.1
            )
            HStack {
                ForEach([440.0, 441, 442, 443], id: \.self) { pitch in
                    Button(String(format: "%.0f", pitch)) {
                        setReference(pitch)
                    }
                    .buttonStyle(.bordered)
                    .tint(abs((store.active?.referencePitch ?? 440) - pitch) < 0.05 ? Theme.amber : Theme.secondary)
                }
            }
        } header: {
            Text("Reference pitch")
        } footer: {
            Text("A stays on this frequency in every temperament. The other notes move around it.")
        }
    }

    private var temperamentSection: some View {
        Section {
            Picker("Temperament", selection: temperamentBinding) {
                ForEach(TemperamentLibrary.all) { temperament in
                    Text(temperament.displayName).tag(temperament.id)
                }
            }
            Text(store.active?.temperament.summary ?? "")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
        } header: {
            Text("Temperament")
        }
    }

    private var octaveSection: some View {
        Section {
            Picker("Octave", selection: octaveBinding) {
                ForEach(OctavePreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            Text(store.active?.octavePreset.summary ?? "")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
            if store.active?.octavePreset == .custom {
                weightSlider("2:1", keyPath: \.w21)
                weightSlider("4:2", keyPath: \.w42)
                weightSlider("6:3", keyPath: \.w63)
            }
        } header: {
            Text("Stretch")
        } footer: {
            Text("The curve locks A4 and asks every other octave to line up the partials you choose. A smoothness term keeps neighboring semitones from kinking.")
        }
    }

    private var pitchRaiseSection: some View {
        Section {
            Toggle("Pitch raise", isOn: pitchRaiseBinding)
            if store.active?.pitchRaiseEnabled == true {
                HStack {
                    Text("Overpull")
                    Spacer()
                    Text("\(Int(store.active?.overpullPercent ?? 25))%")
                        .foregroundStyle(Theme.amber)
                }
                Slider(value: overpullBinding, in: 0...45, step: 1)
                HStack {
                    Text("Piano is flat by")
                    Spacer()
                    Text(String(format: "%.1f¢", store.active?.recordedFlatnessCents ?? 0))
                        .font(.system(.body, design: .monospaced))
                }
                Slider(value: flatnessBinding, in: 0...80, step: 0.5)
                Button("Use the note I’m hearing") {
                    guard let flatness = session.recordFlatnessFromCurrentNote() else { return }
                    store.updateActive { $0.recordedFlatnessCents = flatness }
                }
                Text("Overshoot now \(Format.cents(session.overshootCents))¢. The strobe zeros there and does not chase as the note rises. Turn this off for the fine pass.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
        } header: {
            Text("Pitch raise")
        }
    }

    private var listeningSection: some View {
        Section {
            Toggle("Suggest partials when the note changes", isOn: suggestBinding)
            Toggle("Auto note", isOn: autoNoteBinding)
            Toggle("Auto-advance after the note is in tune", isOn: advanceBinding)
            if session.autoAdvanceEnabled {
                Picker("Direction", selection: directionBinding) {
                    Text("Up").tag(1)
                    Text("Down").tag(-1)
                }
                .pickerStyle(.segmented)
                Stepper(value: thresholdBinding, in: 0.5...5, step: 0.5) {
                    Text("Window \(String(format: "%.1f", session.advanceThreshold))¢")
                }
                Stepper(value: holdBinding, in: 0.6...3, step: 0.2) {
                    Text(String(format: "Hold %.1f s", session.advanceHold))
                }
            }
            HStack {
                Text("Strobe sensitivity")
                Spacer()
                Text(String(format: "%.1f×", session.strobeSensitivity))
                    .foregroundStyle(Theme.secondary)
            }
            Slider(value: sensitivityBinding, in: 0.4...2.2, step: 0.1)
            if !session.isRunning {
                Button("Start microphone") { session.startEngine() }
            }
        } header: {
            Text("Listening")
        } footer: {
            Text("Auto-advance waits until you leave auto note. Deep bass is steadier on partial 4 or 6; the top octave is steadier on partial 1.")
        }
    }

    private var notesSection: some View {
        Section {
            TextField(
                "Notes about this piano",
                text: commentsBinding,
                axis: .vertical
            )
            .lineLimit(3...6)
            if let piano = store.active {
                ShareLink(item: store.fileURL(piano.id)) {
                    Label("Share tuning file", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text("This piano")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: "1.0")
            Text("Pinblock is an aural and electronic tuning aid. It does not replace listening to unisons. Mute to one string, tune it to the strobe, then tune the others to it by ear.")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
        }
    }

    private var referenceBinding: Binding<Double> {
        Binding(get: { store.active?.referencePitch ?? 440 }, set: setReference)
    }

    private var temperamentBinding: Binding<String> {
        Binding(
            get: { store.active?.temperamentID ?? "equal" },
            set: { id in
                store.updateActive {
                    $0.temperamentID = id
                    $0.recalculate()
                }
            }
        )
    }

    private var octaveBinding: Binding<OctavePreset> {
        Binding(
            get: { store.active?.octavePreset ?? .register },
            set: { preset in
                store.updateActive {
                    $0.octavePreset = preset
                    $0.recalculate()
                }
            }
        )
    }

    private var pitchRaiseBinding: Binding<Bool> {
        Binding(
            get: { store.active?.pitchRaiseEnabled ?? false },
            set: { enabled in store.updateActive { $0.pitchRaiseEnabled = enabled } }
        )
    }

    private var overpullBinding: Binding<Double> {
        Binding(
            get: { store.active?.overpullPercent ?? 25 },
            set: { value in store.updateActive { $0.overpullPercent = value } }
        )
    }

    private var flatnessBinding: Binding<Double> {
        Binding(
            get: { store.active?.recordedFlatnessCents ?? 0 },
            set: { value in store.updateActive { $0.recordedFlatnessCents = value } }
        )
    }

    private var commentsBinding: Binding<String> {
        Binding(
            get: { store.active?.comments ?? "" },
            set: { text in store.updateActive { $0.comments = text } }
        )
    }

    private var suggestBinding: Binding<Bool> {
        Binding(get: { session.suggestPartials }, set: { session.suggestPartials = $0; session.persistPreferences() })
    }

    private var autoNoteBinding: Binding<Bool> {
        Binding(get: { session.autoNote }, set: { session.autoNote = $0; session.persistPreferences() })
    }

    private var advanceBinding: Binding<Bool> {
        Binding(get: { session.autoAdvanceEnabled }, set: { session.autoAdvanceEnabled = $0; session.persistPreferences() })
    }

    private var directionBinding: Binding<Int> {
        Binding(get: { session.advanceDirection }, set: { session.advanceDirection = $0; session.persistPreferences() })
    }

    private var thresholdBinding: Binding<Double> {
        Binding(get: { session.advanceThreshold }, set: { session.advanceThreshold = $0; session.persistPreferences() })
    }

    private var holdBinding: Binding<Double> {
        Binding(get: { session.advanceHold }, set: { session.advanceHold = $0; session.persistPreferences() })
    }

    private var sensitivityBinding: Binding<Double> {
        Binding(get: { session.strobeSensitivity }, set: { session.strobeSensitivity = $0; session.persistPreferences() })
    }

    private func setReference(_ pitch: Double) {
        store.updateActive {
            $0.referencePitch = min(466, max(415, pitch))
            $0.recalculate()
        }
    }

    private func weightSlider(_ title: String, keyPath: WritableKeyPath<OctaveWeights, Double>) -> some View {
        let value = store.active?.customWeights[keyPath: keyPath] ?? 0
        return VStack(alignment: .leading) {
            Text("\(title)  \(Int(value * 100))%")
                .font(.subheadline)
            Slider(
                value: Binding(
                    get: { store.active?.customWeights[keyPath: keyPath] ?? 0 },
                    set: { newValue in
                        store.updateActive {
                            $0.customWeights[keyPath: keyPath] = newValue
                            $0.recalculate()
                        }
                    }
                ),
                in: 0...1,
                step: 0.05
            )
        }
    }
}
