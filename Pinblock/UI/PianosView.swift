import PinblockCore
import SwiftUI
import UniformTypeIdentifiers

struct PianosView: View {
    @Environment(TuningStore.self) private var store
    @State private var creating = false
    @State private var newName = ""
    @State private var importing = false
    @State private var pendingDelete: PianoDocument?

    var body: some View {
        Screen {
            List {
                Section {
                    ForEach(store.pianos) { piano in
                        Button {
                            store.activate(piano.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(piano.name)
                                        .font(.headline)
                                        .foregroundStyle(Theme.text)
                                    Text(subtitle(piano))
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondary)
                                }
                                Spacer()
                                if piano.id == store.active?.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.amber)
                                }
                            }
                        }
                        .listRowBackground(Theme.surface)
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                pendingDelete = piano
                            }
                            Button("Duplicate") { store.duplicate(piano.id) }
                                .tint(Theme.amberDim)
                        }
                    }
                } footer: {
                    Text("Each piano keeps its own reference pitch, temperament, measurements, and stretch curve. Files live on this device.")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Pianos")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    importing = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newName = ""
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New piano", isPresented: $creating) {
            TextField("Name", text: $newName)
            Button("Add") { store.create(name: newName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A new file starts from the generic inharmonicity curve.")
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.name ?? "this piano")?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDelete { store.delete(pendingDelete.id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case let .success(url) = result {
                store.importFile(url)
            }
        }
        .alert("Import failed", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
    }

    private func subtitle(_ piano: PianoDocument) -> String {
        let samples = piano.samples.count
        let sampleText = samples == 1 ? "1 measurement" : "\(samples) measurements"
        return "A4 \(String(format: "%.1f", piano.referencePitch)) Hz · \(piano.temperament.displayName) · \(sampleText)"
    }
}
