import PinblockCore
import SwiftUI
import UIKit

struct TunerView: View {
    @Environment(TunerSession.self) private var session
    @Environment(TuningStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Screen {
            Group {
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 20) {
                        tuner.frame(maxWidth: 640)
                        sidePanel
                    }
                    .padding(20)
                } else {
                    ScrollView {
                        tuner.padding(.horizontal, 16)
                    }
                }
            }
        }
        .onAppear { session.setMode(.tune) }
        .sensoryFeedback(.success, trigger: session.inTuneToken)
    }

    private var tuner: some View {
        VStack(spacing: 16) {
            header
            if session.permission == .denied {
                permissionCard
            }
            noteBlock
            StrobeView(
                cents: session.reading.cents,
                confidence: session.reading.confidence,
                sensitivity: session.strobeSensitivity
            )
            .frame(height: 168)
            readout
            partialPicker
            controls
            KeyboardStrip(selected: session.selectedMidi) { session.select(midi: $0) }
            if let message = session.statusMessage, session.permission != .denied {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.sharp)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("PINBLOCK")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(Theme.amber)
                Text(store.active?.name ?? "No piano")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(referenceLine)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.secondary)
                Text(store.active?.temperament.displayName ?? "Equal")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }

    private var noteBlock: some View {
        VStack(spacing: 4) {
            Text(NotePitch.name(midi: session.selectedMidi))
                .font(.system(size: 76, weight: .light, design: .rounded))
                .foregroundStyle(Theme.text)
                .minimumScaleFactor(0.6)
            Text(statusLine)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Theme.centsColor(session.reading.cents, confidence: session.reading.confidence))
            if session.overshootCents > 0.05 {
                Text("Pitch raise · tune \(Format.cents(session.overshootCents))¢ sharp of the curve")
                    .font(.caption)
                    .foregroundStyle(Theme.amber)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityPitch)
    }

    private var readout: some View {
        VStack(spacing: 6) {
            Text(session.reading.confidence < 0.2 ? "—.—" : Format.cents(session.reading.cents))
                .font(.system(size: 48, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.centsColor(session.reading.cents, confidence: session.reading.confidence))
            Text("cents")
                .font(.caption)
                .foregroundStyle(Theme.tertiary)
            HStack(spacing: 14) {
                Text(session.reading.measuredFrequency > 0 ? Format.hertz(session.reading.measuredFrequency) : "— Hz")
                Text(beatLine)
            }
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.secondary)
            levelMeter
            if session.reading.isClipping {
                Text("Signal is clipping. Move the phone back.")
                    .font(.caption)
                    .foregroundStyle(Theme.sharp)
            }
        }
    }

    private var levelMeter: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceRaised)
                Capsule()
                    .fill(session.reading.isClipping ? Theme.sharp : Theme.amber)
                    .frame(width: proxy.size.width * CGFloat(min(1, session.reading.rms * 5)))
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 48)
        .accessibilityLabel("Input level")
    }

    private var partialPicker: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach([1, 2, 3, 4, 5, 6, 8], id: \.self) { partial in
                    Button {
                        session.setPartial(partial)
                    } label: {
                        Text("\(partial)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(session.partial == partial ? Theme.amber : Theme.surface)
                            )
                            .foregroundStyle(session.partial == partial ? Color.black : Theme.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(partialCaption)
                .font(.caption)
                .foregroundStyle(Theme.tertiary)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button { session.step(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 36)
            }
            .buttonStyle(.bordered)
            .tint(Theme.secondary)

            Toggle(isOn: autoNoteBinding) {
                Text("Auto note")
                    .font(.subheadline)
            }
            .toggleStyle(.button)
            .tint(Theme.amber)

            Toggle(isOn: advanceBinding) {
                Text("Advance")
                    .font(.subheadline)
            }
            .toggleStyle(.button)
            .tint(Theme.amber)

            Button { session.step(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 36)
            }
            .buttonStyle(.bordered)
            .tint(Theme.secondary)
        }
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stretch")
                .font(.headline)
            MiniCurve(curve: store.active?.curve ?? [])
                .frame(height: 180)
            if let tuning = store.active?.tuning(midi: session.selectedMidi) {
                LabeledContent("Curve offset", value: "\(Format.cents(tuning.centsFromEqual))¢")
                LabeledContent("Fundamental", value: Format.hertz(tuning.f1))
                LabeledContent("Inharmonicity B", value: Format.scientific(tuning.b))
            }
            Text(store.active?.usesMeasuredInharmonicity == true
                 ? "Curve is from measurements on this piano."
                 : "Generic inharmonicity until you measure this piano.")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Microphone is off")
                .font(.headline)
            Text("Pinblock needs the microphone to hear the string. Nothing is recorded.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.amber)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
    }

    private var referenceLine: String {
        let pitch = store.active?.referencePitch ?? 440
        return "A4 \(String(format: "%.1f", pitch)) Hz"
    }

    private var statusLine: String {
        if session.reading.confidence < 0.2 { return "PLAY AND HOLD" }
        if !session.reading.isRefined { return "SETTLING" }
        if abs(session.reading.cents) < 0.5 { return "IN TUNE" }
        return session.reading.cents < 0 ? "FLAT" : "SHARP"
    }

    private var partialCaption: String {
        let suggested = NotePitch.suggestedPartial(midi: session.selectedMidi)
        if session.partial == suggested {
            return "Listening to partial \(session.partial)"
        }
        return "Listening to partial \(session.partial) · suggested \(suggested)"
    }

    private var beatLine: String {
        guard session.reading.confidence >= 0.2, session.reading.measuredFrequency > 0, session.reading.targetFrequency > 0 else {
            return "beat —"
        }
        let beat = abs(session.reading.measuredFrequency - session.reading.targetFrequency)
        return String(format: "beat %.2f Hz", beat)
    }

    private var accessibilityPitch: String {
        let name = NotePitch.name(midi: session.selectedMidi)
        if session.reading.confidence < 0.2 { return "\(name), no pitch yet" }
        return "\(name), \(Format.cents(session.reading.cents)) cents"
    }

    private var autoNoteBinding: Binding<Bool> {
        Binding(
            get: { session.autoNote },
            set: { session.autoNote = $0; session.persistPreferences() }
        )
    }

    private var advanceBinding: Binding<Bool> {
        Binding(
            get: { session.autoAdvanceEnabled },
            set: { session.autoAdvanceEnabled = $0; session.persistPreferences() }
        )
    }
}

struct MiniCurve: View {
    var curve: [NoteTuning]

    var body: some View {
        Canvas { context, size in
            guard curve.count > 1 else { return }
            let cents = curve.map(\.centsFromEqual)
            let minC = min(-5, cents.min() ?? -10)
            let maxC = max(5, cents.max() ?? 10)
            func point(_ index: Int) -> CGPoint {
                let x = size.width * CGFloat(index) / CGFloat(curve.count - 1)
                let yNorm = (cents[index] - minC) / (maxC - minC)
                let y = size.height * (1 - CGFloat(yNorm))
                return CGPoint(x: x, y: y)
            }
            var zero = Path()
            let zeroY = size.height * (1 - CGFloat((0 - minC) / (maxC - minC)))
            zero.move(to: CGPoint(x: 0, y: zeroY))
            zero.addLine(to: CGPoint(x: size.width, y: zeroY))
            context.stroke(zero, with: .color(Theme.tertiary), lineWidth: 1)
            var line = Path()
            line.move(to: point(0))
            for index in 1..<curve.count {
                line.addLine(to: point(index))
            }
            context.stroke(line, with: .color(Theme.amber), lineWidth: 2)
        }
    }
}
