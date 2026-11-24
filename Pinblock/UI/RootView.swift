import SwiftUI

struct RootView: View {
    @Environment(TunerSession.self) private var session
    @Environment(TuningStore.self) private var store

    var body: some View {
        TabView {
            NavigationStack {
                TunerView()
            }
            .tabItem { Label("Tune", systemImage: "tuningfork") }

            NavigationStack {
                MeasureView()
            }
            .tabItem { Label("Measure", systemImage: "waveform") }

            NavigationStack {
                CurveView()
            }
            .tabItem { Label("Curve", systemImage: "chart.xyaxis.line") }

            NavigationStack {
                PianosView()
            }
            .tabItem { Label("Pianos", systemImage: "music.note.list") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.amber)
        .preferredColorScheme(.dark)
        .task {
            if store.pianos.isEmpty {
                store.load()
            }
            session.use(piano: store.active)
            await session.prepare()
        }
        .onChange(of: store.active) { _, piano in
            session.use(piano: piano)
        }
    }
}
