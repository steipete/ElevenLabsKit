@preconcurrency import AVFoundation

@MainActor
protocol PCMPlayerNodeing: AnyObject {
    var isPlaying: Bool { get }
    func attach(to engine: AVAudioEngine)
    func connect(to engine: AVAudioEngine, format: AVAudioFormat)
    func scheduleBuffer(_ buffer: AVAudioPCMBuffer) async
    func play()
    func stop()
    func currentTimeSeconds() -> Double?
}

@MainActor
final class AVAudioPlayerNodeAdapter: PCMPlayerNodeing {
    private let node: AVAudioPlayerNode

    init(node: AVAudioPlayerNode = AVAudioPlayerNode()) {
        self.node = node
    }

    var isPlaying: Bool { node.isPlaying }

    func attach(to engine: AVAudioEngine) {
        engine.attach(node)
    }

    func connect(to engine: AVAudioEngine, format: AVAudioFormat) {
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    func scheduleBuffer(_ buffer: AVAudioPCMBuffer) async {
        await node.scheduleBuffer(buffer)
    }

    func play() {
        node.play()
    }

    func stop() {
        node.stop()
    }

    func currentTimeSeconds() -> Double? {
        guard let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime)
        else { return nil }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }
}
