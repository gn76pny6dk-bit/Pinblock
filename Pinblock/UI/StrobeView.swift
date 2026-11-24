import SwiftUI

struct StrobeView: View {
    var cents: Double
    var confidence: Double
    var sensitivity: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            StrobeBands(
                cents: cents,
                confidence: confidence,
                sensitivity: sensitivity,
                date: timeline.date
            )
        }
        .accessibilityHidden(true)
    }
}

private struct StrobeBands: View {
    var cents: Double
    var confidence: Double
    var sensitivity: Double
    var date: Date
    @State private var phases = [0.0, 0.0, 0.0]
    @State private var lastDate: Date?

    private let titles = ["COARSE", "MID", "FINE"]
    private let multipliers = [1.0, 5.0, 25.0]

    var body: some View {
        Canvas { context, size in
            let active = confidence >= 0.22
            let color = Theme.centsColor(cents, confidence: confidence)
            let rowHeight = size.height / 3
            for row in 0..<3 {
                let rect = CGRect(x: 0, y: CGFloat(row) * rowHeight, width: size.width, height: rowHeight)
                let background = Path(rect.insetBy(dx: 0, dy: 3))
                context.fill(background, with: .color(Theme.surface))
                let period: CGFloat = row == 2 ? 18 : 26
                let shift = CGFloat(phases[row] - phases[row].rounded(.down)) * period
                let barWidth = period * 0.46
                var x = -period + shift
                let band = active ? color.opacity(row == 2 ? 0.95 : 0.72) : Theme.amberDim.opacity(0.35)
                while x < size.width + period {
                    let bar = CGRect(
                        x: x,
                        y: rect.minY + 8,
                        width: barWidth,
                        height: rect.height - 16
                    )
                    context.fill(Path(roundedRect: bar, cornerRadius: 2), with: .color(band))
                    x += period
                }
                context.draw(
                    Text(titles[row])
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55)),
                    at: CGPoint(x: 28, y: rect.midY),
                    anchor: .center
                )
            }
        }
        .onChange(of: date) { _, newDate in
            let dt = min(0.05, lastDate.map { newDate.timeIntervalSince($0) } ?? 0)
            lastDate = newDate
            let active = confidence >= 0.22
            for index in 0..<3 {
                let raw = active ? cents * sensitivity * multipliers[index] * 0.22 : 0
                let capped = min(3.2, max(-3.2, raw))
                phases[index] += capped * dt
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.stroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct KeyboardStrip: View {
    var selected: Int
    var onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(NotePitch.lowestMidi...NotePitch.highestMidi, id: \.self) { midi in
                        let isSelected = midi == selected
                        let black = NotePitch.isBlackKey(midi: midi)
                        Button {
                            onSelect(midi)
                        } label: {
                            Text(NotePitch.name(midi: midi))
                                .font(.system(size: isSelected ? 13 : 11, weight: isSelected ? .bold : .medium, design: .rounded))
                                .foregroundStyle(isSelected ? Color.black : (black ? Theme.secondary : Theme.text))
                                .frame(width: isSelected ? 52 : 40, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isSelected ? Theme.amber : (black ? Theme.surface : Theme.surfaceRaised))
                                )
                        }
                        .buttonStyle(.plain)
                        .id(midi)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .onAppear {
                proxy.scrollTo(selected, anchor: .center)
            }
            .onChange(of: selected) { _, midi in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(midi, anchor: .center)
                }
            }
        }
    }
}
