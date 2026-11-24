import PinblockCore
import SwiftUI

struct MeasureView: View {
    @Environment(TunerSession.self) private var session
    @Environment(TuningStore.self) private var store

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Measure inharmonicity")
                        .font(.title2.weight(.semibold))
                    Text("Play one string of the note and hold it. Pinblock fits the partials to the stiff-string model and stores B for that note. Four or more notes across the compass are enough to replace the generic curve.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                    targetStrip
                    liveCard
                    if let fit = session.reading.fit ?? session.consensus {
                        partialList(fit)
                    }
                    Button {
                        guard let sample = session.keepMeasurement() else { return }
                        store.upsertSample(sample)
                    } label: {
                        Text(session.consensus == nil ? "Hold until the fit settles" : "Keep \(NotePitch.name(midi: session.selectedMidi))")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.amber)
                    .disabled(session.consensus == nil)
                    storedList
                }
                .padding(16)
            }
        }
        .onAppear { session.setMode(.measure) }
    }

    private var targetStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PianoDocument.measureTargets, id: \.self) { midi in
                    let saved = store.active?.samples.contains { $0.midi == midi } ?? false
                    Button {
                        session.select(midi: midi)
                    } label: {
                        VStack(spacing: 2) {
                            Text(NotePitch.name(midi: midi))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Text(saved ? "saved" : "open")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(session.selectedMidi == midi ? Theme.amber : Theme.surface)
                        )
                        .foregroundStyle(session.selectedMidi == midi ? Color.black : Theme.text)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var liveCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(NotePitch.name(midi: session.selectedMidi))
                    .font(.title.weight(.medium))
                Spacer()
                Text(session.consensus == nil ? "Listening" : "Stable")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(session.consensus == nil ? Theme.surfaceRaised : Theme.green.opacity(0.25)))
                    .foregroundStyle(session.consensus == nil ? Theme.secondary : Theme.green)
            }
            if let fit = session.consensus ?? session.reading.fit {
                LabeledContent("B", value: Format.scientific(fit.b))
                LabeledContent("Fundamental", value: Format.hertz(fit.f1))
                LabeledContent("Fit residual", value: String(format: "%.2f¢", fit.residualCents))
            } else {
                Text("Play the note. A usable fit needs at least three clear partials.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
            }
            Text(session.reading.confidence < 0.2 ? "No tone yet" : "Signal \(Format.cents(session.centsFromCurve))¢ from the current curve")
                .font(.footnote)
                .foregroundStyle(Theme.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
    }

    private func partialList(_ fit: InharmonicityFit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Partials")
                .font(.headline)
            ForEach(fit.partials, id: \.n) { partial in
                let predicted = Inharmonicity.partialFrequency(f1: fit.f1, n: partial.n, b: fit.b)
                let cents = Cents.between(predicted, partial.frequency) ?? 0
                HStack {
                    Text("\(partial.n)")
                        .frame(width: 24, alignment: .leading)
                        .foregroundStyle(Theme.amber)
                    Text(Format.hertz(partial.frequency))
                    Spacer()
                    Text(Format.cents(cents) + "¢")
                        .foregroundStyle(Theme.secondary)
                }
                .font(.system(size: 13, design: .monospaced))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
    }

    private var storedList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Saved on this piano")
                .font(.headline)
            if store.active?.samples.isEmpty != false {
                Text("Nothing measured yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
            } else {
                ForEach(store.active?.samples ?? []) { sample in
                    HStack {
                        Text(NotePitch.name(midi: sample.midi))
                            .frame(width: 48, alignment: .leading)
                        Text(Format.scientific(sample.b))
                            .foregroundStyle(Theme.secondary)
                        Spacer()
                        Text(String(format: "%.2f¢", sample.residualCents))
                            .foregroundStyle(Theme.tertiary)
                        Button("Remove") {
                            store.removeSample(midi: sample.midi)
                        }
                        .font(.caption)
                    }
                    .font(.system(size: 14, design: .rounded))
                }
            }
        }
    }
}
