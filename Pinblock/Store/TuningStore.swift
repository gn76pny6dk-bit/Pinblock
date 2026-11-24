import Foundation
import Observation
import PinblockCore

@MainActor
@Observable
final class TuningStore {
    private(set) var pianos: [PianoDocument] = []
    var activeID: UUID?
    var lastError: String?

    var active: PianoDocument? {
        pianos.first { $0.id == activeID } ?? pianos.first
    }

    func load() {
        let directory = Self.directory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = PinblockJSON.decoder()
        var loaded: [PianoDocument] = []
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let document = try? decoder.decode(PianoDocument.self, from: data) else { continue }
            loaded.append(document)
        }
        loaded.sort { $0.updatedAt > $1.updatedAt }
        if loaded.isEmpty {
            let fresh = PianoDocument.makeNew(name: "My piano")
            loaded = [fresh]
            write(fresh)
        }
        pianos = loaded
        if let stored = UserDefaults.standard.string(forKey: Self.activeKey),
           let id = UUID(uuidString: stored),
           loaded.contains(where: { $0.id == id }) {
            activeID = id
        } else {
            activeID = loaded[0].id
        }
    }

    func updateActive(_ body: (inout PianoDocument) -> Void) {
        guard let current = active, let index = pianos.firstIndex(where: { $0.id == current.id }) else { return }
        body(&pianos[index])
        save(pianos[index])
    }

    func activate(_ id: UUID) {
        guard pianos.contains(where: { $0.id == id }) else { return }
        activeID = id
        UserDefaults.standard.set(id.uuidString, forKey: Self.activeKey)
    }

    func create(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let document = PianoDocument.makeNew(name: trimmed.isEmpty ? "Untitled piano" : trimmed)
        pianos.insert(document, at: 0)
        write(document)
        activate(document.id)
    }

    func duplicate(_ id: UUID) {
        guard var copy = pianos.first(where: { $0.id == id }) else { return }
        copy.id = UUID()
        copy.name = copy.name + " copy"
        copy.createdAt = Date()
        copy.updatedAt = copy.createdAt
        pianos.insert(copy, at: 0)
        write(copy)
        activate(copy.id)
    }

    func delete(_ id: UUID) {
        pianos.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: fileURL(id))
        if pianos.isEmpty {
            create(name: "My piano")
            return
        }
        if activeID == id {
            activate(pianos[0].id)
        }
    }

    func upsertSample(_ sample: InharmonicitySample) {
        updateActive { piano in
            piano.samples.removeAll { $0.midi == sample.midi }
            piano.samples.append(sample)
            piano.samples.sort { $0.midi < $1.midi }
            piano.recalculate()
        }
    }

    func removeSample(midi: Int) {
        updateActive { piano in
            piano.samples.removeAll { $0.midi == midi }
            piano.recalculate()
        }
    }

    func importFile(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            var document = try PinblockJSON.decoder().decode(PianoDocument.self, from: data)
            if pianos.contains(where: { $0.id == document.id }) {
                document.id = UUID()
            }
            document.recalculate()
            pianos.insert(document, at: 0)
            write(document)
            activate(document.id)
            lastError = nil
        } catch {
            lastError = "Could not read that tuning file."
        }
    }

    func fileURL(_ id: UUID) -> URL {
        Self.directory().appendingPathComponent("\(id.uuidString).json")
    }

    private func save(_ document: PianoDocument) {
        write(document)
        if activeID == nil { activeID = document.id }
    }

    private func write(_ document: PianoDocument) {
        do {
            let data = try PinblockJSON.encoder().encode(document)
            try data.write(to: fileURL(document.id), options: .atomic)
        } catch {
            lastError = "Could not save this piano on the device."
        }
    }

    private static func directory() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Pianos", isDirectory: true)
    }

    private static let activeKey = "pinblock.activePiano"
}
