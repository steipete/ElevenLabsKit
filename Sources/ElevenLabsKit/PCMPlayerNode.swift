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

    var isPlaying: Bool { self.node.isPlaying }

    func attach(to engine: AVAudioEngine) {
        engine.attach(self.node)
    }

    func connect(to engine: AVAudioEngine, format: AVAudioFormat) {
        engine.connect(self.node, to: engine.mainMixerNode, format: format)
    }

    func scheduleBuffer(_ buffer: AVAudioPCMBuffer) async {
        await self.node.scheduleBuffer(buffer)
    }

    func play() {
        self.node.play()
    }

    func stop() {
        self.node.stop()
    }

    func currentTimeSeconds() -> Double? {
        guard let nodeTime = self.node.lastRenderTime,
              let playerTime = self.node.playerTime(forNodeTime: nodeTime)
        else { return nil }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }
}
