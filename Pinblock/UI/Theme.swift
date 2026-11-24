import SwiftUI

enum Theme {
    static let background = Color(red: 0.043, green: 0.047, blue: 0.055)
    static let surface = Color(red: 0.09, green: 0.10, blue: 0.12)
    static let surfaceRaised = Color(red: 0.13, green: 0.145, blue: 0.17)
    static let amber = Color(red: 0.96, green: 0.76, blue: 0.42)
    static let amberDim = Color(red: 0.55, green: 0.42, blue: 0.22)
    static let green = Color(red: 0.49, green: 1.0, blue: 0.70)
    static let flat = Color(red: 0.45, green: 0.75, blue: 1.0)
    static let sharp = Color(red: 1.0, green: 0.55, blue: 0.38)
    static let text = Color.white
    static let secondary = Color.white.opacity(0.62)
    static let tertiary = Color.white.opacity(0.38)
    static let stroke = Color.white.opacity(0.08)

    static func centsColor(_ cents: Double, confidence: Double) -> Color {
        guard confidence >= 0.2 else { return tertiary }
        let magnitude = abs(cents)
        if magnitude < 0.5 { return green }
        if magnitude < 4 { return amber }
        return cents < 0 ? flat : sharp
    }
}

enum Format {
    static func cents(_ value: Double) -> String {
        String(format: "%+.1f", value)
    }

    static func hertz(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1f Hz", value)
        }
        return String(format: "%.2f Hz", value)
    }

    static func scientific(_ value: Double) -> String {
        String(format: "%.2e", value)
    }
}

struct Screen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.background.ignoresSafeArea())
    }
}
