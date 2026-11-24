import SwiftUI

@main
struct PinblockApp: App {
    @State private var store = TuningStore()
    @State private var session = TunerSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(session)
        }
    }
}
