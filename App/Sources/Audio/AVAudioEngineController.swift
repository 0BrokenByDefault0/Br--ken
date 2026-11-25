import AVFoundation
import SoundEngine

/// An `AVAudioEngine` whose only source is a `Renderer`, created at the hardware sample rate.
/// After a media-services reset, build a new controller (which brings a new `Renderer`).
final class AVAudioEngineController: AudioEngineControlling {
    let renderer: Renderer
    private let engine: AVAudioEngine
    private let source: AVAudioSourceNode

    init() {
        let engine = AVAudioEngine()
        let hardwareRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = hardwareRate > 0 ? hardwareRate : 48_000
        let renderer = Renderer(sampleRate: sampleRate)
        // Stereo, non-interleaved Float32: one buffer per channel, as `Renderer.render` writes.
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                   channels: 2, interleaved: false)!
        let source = AVAudioEngineController.makeSourceNode(format: format, renderer: renderer)
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        self.engine = engine
        self.renderer = renderer
        self.source = source
    }

    var isRunning: Bool { engine.isRunning }

    func start() throws {
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.stop()
    }

    /// Built outside any actor: the block runs on the real-time audio thread and must not allocate,
    /// lock, or hop actors.
    private static func makeSourceNode(format: AVAudioFormat, renderer: Renderer) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { isSilence, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
            else {
                // Unexpected layout: output silence rather than whatever the buffers held.
                for buffer in buffers {
                    if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
                }
                isSilence.pointee = true
                return noErr
            }
            // Never write past the buffers, whatever frameCount says.
            let capacity = Int(min(buffers[0].mDataByteSize, buffers[1].mDataByteSize)) / MemoryLayout<Float>.size
            renderer.render(frames: min(Int(frameCount), capacity), left: left, right: right)
            return noErr
        }
    }
}
