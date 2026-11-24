import AVFoundation
import Foundation

final class AudioCapture: @unchecked Sendable {
    var onSamples: (@Sendable ([Float], Double) -> Void)?
    private let engine = AVAudioEngine()
    private var tapInstalled = false

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
            )
        } catch {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [])
        }
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.008)
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw CaptureError.noInput
        }
        if engine.isRunning {
            engine.stop()
        }
        if tapInstalled {
            input.removeTap(onBus: 0)
            tapInstalled = false
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.emit(buffer)
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()
    }

    func stop() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func emit(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frames > 0, channelCount > 0 else { return }
        var mono = [Float](repeating: 0, count: frames)
        if channelCount == 1 {
            for frame in 0..<frames {
                mono[frame] = channels[0][frame]
            }
        } else {
            for frame in 0..<frames {
                var sum = 0.0
                for channel in 0..<channelCount {
                    sum += Double(channels[channel][frame])
                }
                mono[frame] = Float(sum / Double(channelCount))
            }
        }
        onSamples?(mono, buffer.format.sampleRate)
    }

    enum CaptureError: LocalizedError {
        case noInput
        var errorDescription: String? {
            "No microphone input. Pitch detection needs a physical iPhone or iPad."
        }
    }
}
