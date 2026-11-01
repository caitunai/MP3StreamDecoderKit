import AudioToolbox
import AVFAudio
import Foundation

extension MP3StreamDecoder {
    internal func configure(for header: MP3FrameHeader) throws {
        guard let format = AVAudioFormat(
            commonFormat: outputCommonFormat, sampleRate: Double(header.sampleRate),
            channels: AVAudioChannelCount(header.channelCount), interleaved: false
        ) else {
            throw MP3StreamDecoderError.allocationFailed
        }
        var source = header.makeInputDescription()
        var destination = format.streamDescription.pointee
        var created: AudioConverterRef?
        let status = AudioConverterNew(&source, &destination, &created)
        guard status == noErr, let created else {
            throw MP3StreamDecoderError.audioToolbox(operation: "AudioConverterNew", status: status)
        }
        converter = created
        outputFormat = format
        streamHeader = header
        input.channelCount = UInt32(header.channelCount)
        input.samplesPerFrame = UInt32(header.samplesPerFrame)
        MP3StreamDecoder.logger.debug("MP3 stream: \(header.sampleRate) Hz, \(header.channelCount) channel(s), initial bit rate \(header.bitRate)")
    }

    internal func drain() throws -> [AVAudioPCMBuffer] {
        guard let converter, let outputFormat else { return [] }
        var result: [AVAudioPCMBuffer] = []
        defer { input.discardConsumedPackets() }
        while true {
            let capacity: AVAudioFrameCount = 4_096
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
                throw MP3StreamDecoderError.allocationFailed
            }
            output.frameLength = capacity
            var outputPackets = UInt32(capacity)
            let status = AudioConverterFillComplexBuffer(
                converter, MP3DecoderInput.callback,
                Unmanaged.passUnretained(input).toOpaque(), &outputPackets,
                output.mutableAudioBufferList, nil
            )
            guard status == noErr || status == MP3DecoderInput.needMoreData else {
                throw MP3StreamDecoderError.audioToolbox(
                    operation: "AudioConverterFillComplexBuffer", status: status
                )
            }
            if outputPackets > 0 {
                output.frameLength = AVAudioFrameCount(outputPackets)
                result.append(output)
            }
            if status == MP3DecoderInput.needMoreData || outputPackets == 0 { break }
        }
        return result
    }
}
