import Charts
import Foundation
import PinblockCore
import SwiftUI

struct CurveView: View {
    @Environment(TuningStore.self) private var store
    @State private var showB = false

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(store.active?.name ?? "Curve")
                        .font(.title2.weight(.semibold))
                    Text(caption)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                    Picker("Plot", selection: $showB) {
                        Text("Cents").tag(false)
                        Text("Inharmonicity").tag(true)
                    }
                    .pickerStyle(.segmented)
                    chart
                        .frame(height: 280)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
                    if let active = store.active {
                        summary(active)
                    }
                }
                .padding(16)
            }
        }
    }

    private var caption: String {
        if store.active?.usesMeasuredInharmonicity == true {
            return "Cents from equal temperament at this piano’s reference pitch. Stretch and the chosen temperament are both in the line."
        }
        return "This is the generic grand model. Measure a handful of notes and the line becomes this piano’s curve."
    }

    @ViewBuilder
    private var chart: some View {
        if let curve = store.active?.curve, !curve.isEmpty {
            Chart {
                if showB {
                    ForEach(curve) { note in
                        LineMark(
                            x: .value("Note", note.midi),
                            y: .value("log B", log10B(note.b))
                        )
                        .foregroundStyle(Theme.amber)
                    }
                } else {
                    ForEach(curve) { note in
                        LineMark(
                            x: .value("Note", note.midi),
                            y: .value("Cents", note.centsFromEqual)
                        )
                        .foregroundStyle(Theme.amber)
                    }
                    RuleMark(y: .value("Equal", 0))
                        .foregroundStyle(Theme.tertiary)
                }
                ForEach(store.active?.samples ?? []) { sample in
                    PointMark(
                        x: .value("Note", sample.midi),
                        y: .value("Value", sampleY(sample))
                    )
                    .foregroundStyle(Theme.green)
                    .symbolSize(60)
                }
            }
            .chartXScale(domain: 21...108)
            .chartXAxis {
                AxisMarks(values: [21, 33, 45, 57, 69, 81, 93, 105, 108]) { value in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel {
                        if let midi = value.as(Int.self) {
                            Text(NotePitch.name(midi: midi))
                                .font(.caption2)
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(showB ? String(format: "%.1f", number) : String(format: "%.0f", number))
                                .font(.caption2)
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
        } else {
            Text("No curve yet.")
                .foregroundStyle(Theme.secondary)
        }
    }

    private func sampleY(_ sample: InharmonicitySample) -> Double {
        if showB { return log10B(sample.b) }
        return store.active?.tuning(midi: sample.midi)?.centsFromEqual ?? 0
    }

    private func log10B(_ value: Double) -> Double {
        log(max(value, 1e-8)) / log(10)
    }

    private func summary(_ piano: PianoDocument) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(piano.octavePreset.title) · \(piano.temperament.displayName)")
                .font(.subheadline.weight(.semibold))
            Text("A0 \(Format.cents(piano.tuning(midi: 21)?.centsFromEqual ?? 0))¢    A4 \(Format.cents(piano.tuning(midi: 69)?.centsFromEqual ?? 0))¢    C8 \(Format.cents(piano.tuning(midi: 108)?.centsFromEqual ?? 0))¢")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.secondary)
            Text(showB ? "Vertical axis is log10 of B. Green dots are measured notes." : "Green dots are notes you measured. The zero line is equal temperament.")
                .font(.footnote)
                .foregroundStyle(Theme.tertiary)
        }
    }
}
