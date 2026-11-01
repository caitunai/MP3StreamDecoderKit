import AudioToolbox
import AVFAudio
import Foundation
import MP3StreamDecoderKit

/// Shows how a single actor can own decoding state and write BLE audio to WAV.
///
/// Callers must pass pure, ordered MP3 payloads. This example deliberately does
/// not own a BLE connection or configure an audio playback session.
@MainActor
final class MP3ToWAVExample {
    private let decoder: MP3StreamDecoder
    private let outputURL: URL
    private var outputFile: AVAudioFile?

    /// Creates a session whose destination should have a `.wav` extension.
    ///
    /// - Parameters:
    ///   - outputURL: The destination WAV URL.
    ///   - outputCommonFormat: The decoder's Int16 or Float32 sample type.
    init(outputURL: URL, outputCommonFormat: AVAudioCommonFormat = .pcmFormatFloat32) {
        self.outputURL = outputURL
        decoder = MP3StreamDecoder(outputCommonFormat: outputCommonFormat)
    }

    /// Decodes one BLE payload and writes any PCM output to the destination.
    func receive(_ payload: Data) throws {
        try write(decoder.append(payload))
    }

    /// Drains and closes the recording after all BLE audio has arrived.
    func finish() throws {
        try write(decoder.finish())
        outputFile = nil
    }

    private func write(_ buffers: [AVAudioPCMBuffer]) throws {
        for buffer in buffers {
            if outputFile == nil {
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: buffer.format.sampleRate,
                    AVNumberOfChannelsKey: Int(buffer.format.channelCount),
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
                outputFile = try AVAudioFile(
                    forWriting: outputURL, settings: settings,
                    commonFormat: buffer.format.commonFormat, interleaved: false
                )
            }
            try outputFile?.write(from: buffer)
        }
    }
}
