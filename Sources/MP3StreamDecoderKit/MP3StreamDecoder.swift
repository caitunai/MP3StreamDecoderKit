import AudioToolbox
import AVFAudio
import Foundation
import OSLog

/// Incrementally decodes raw MP3 frame bytes into non-interleaved PCM.
///
/// Retain one decoder per continuous stream. Access all methods and properties
/// from the same serial execution context. Input must contain only ordered MP3
/// frame bytes; remove transport headers before appending. ID3 tags and automatic
/// recovery from missing or corrupt bytes are outside this decoder's contract.
public final class MP3StreamDecoder {
    /// The selected PCM sample type, preserved when the decoder is reset.
    public let outputCommonFormat: AVAudioCommonFormat
    /// The PCM output format, available after the first complete MP3 frame.
    public internal(set) var outputFormat: AVAudioFormat?
    /// The first compressed frame's header; later bit rates may vary.
    public internal(set) var streamHeader: MP3FrameHeader?

    internal static let logger = Logger(subsystem: "MP3StreamDecoderKit", category: "Decoder")
    internal var converter: AudioConverterRef?
    internal var input = MP3DecoderInput()
    internal var bufferedBytes = Data()
    internal var failure: MP3StreamDecoderError?
    internal var finished = false

    /// Creates an empty decoder without assuming an input sample rate or bit rate.
    ///
    /// - Parameter outputCommonFormat: The output sample type. Use
    ///   `.pcmFormatInt16` for `int16ChannelData` or `.pcmFormatFloat32` for
    ///   `floatChannelData`. The default preserves the original Float32 behavior.
    /// - Precondition: Only `.pcmFormatInt16` and `.pcmFormatFloat32` are supported.
    public init(outputCommonFormat: AVAudioCommonFormat = .pcmFormatFloat32) {
        precondition(
            outputCommonFormat == .pcmFormatInt16 || outputCommonFormat == .pcmFormatFloat32,
            "Only pcmFormatInt16 and pcmFormatFloat32 are supported."
        )
        self.outputCommonFormat = outputCommonFormat
    }

    deinit {
        if let converter { AudioConverterDispose(converter) }
    }

    /// Appends any number of bytes from the same continuous MP3 stream.
    ///
    /// Partial frames are retained for the next call. Empty output is normal
    /// while collecting a frame or satisfying the codec's buffering needs.
    /// Returned buffers own their PCM storage and remain valid after later calls.
    ///
    /// - Parameter bytes: Consecutive raw MP3 bytes, including each frame header.
    /// - Returns: Zero or more PCM buffers, in playback order.
    /// - Throws: A framing or conversion error. After such a failure, reset the
    ///   decoder before supplying data for a new stream.
    public func append(_ bytes: Data) throws -> [AVAudioPCMBuffer] {
        if let failure { throw failure }
        guard !finished else { throw MP3StreamDecoderError.alreadyFinished }
        guard !bytes.isEmpty else { return [] }
        do {
            bufferedBytes.append(bytes)
            var offset = 0
            var frames: [Data] = []
            while bufferedBytes.count - offset >= 4 {
                let header = try bufferedBytes.withUnsafeBytes { raw in
                    try MP3FrameHeader.parse(UnsafeRawBufferPointer(rebasing: raw[offset...]))
                }
                if let streamHeader, !streamHeader.isCompatible(with: header) {
                    throw MP3StreamDecoderError.formatChanged
                }
                guard bufferedBytes.count - offset >= header.frameByteCount else { break }
                if converter == nil { try configure(for: header) }
                frames.append(bufferedBytes.subdata(in: offset..<(offset + header.frameByteCount)))
                offset += header.frameByteCount
            }
            if offset > 0 { bufferedBytes = Data(bufferedBytes.dropFirst(offset)) }
            guard !frames.isEmpty else { return [] }
            input.enqueue(frames)
            return try drain()
        } catch let error as MP3StreamDecoderError {
            failure = error
            MP3StreamDecoder.logger.error("MP3 decoding failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Signals the actual end of the stream and drains the converter's output.
    ///
    /// Do not call this method between BLE notifications. It marks the stream
    /// finished, so further input requires `reset()`.
    ///
    /// - Returns: Any remaining PCM buffers.
    /// - Throws: `MP3StreamDecoderError.incompleteFrame` for trailing partial
    ///   data, or a conversion error. After an incomplete-frame error, missing
    ///   bytes may still be appended before calling this method again.
    public func finish() throws -> [AVAudioPCMBuffer] {
        if let failure { throw failure }
        guard !finished else { return [] }
        guard bufferedBytes.isEmpty else {
            throw MP3StreamDecoderError.incompleteFrame(remainingBytes: bufferedBytes.count)
        }
        input.endOfStream = true
        do {
            let buffers = try drain()
            finished = true
            return buffers
        } catch let error as MP3StreamDecoderError {
            failure = error
            throw error
        }
    }

    /// Discards compressed data, PCM codec state, and the current stream format.
    ///
    /// Call this method before a new recording or after a transport discontinuity.
    /// Resuming midstream may still lose audio until MP3 reservoir data recovers.
    /// The selected `outputCommonFormat` is retained.
    public func reset() {
        if let converter { AudioConverterDispose(converter) }
        converter = nil
        input = MP3DecoderInput()
        bufferedBytes.removeAll(keepingCapacity: true)
        outputFormat = nil
        streamHeader = nil
        failure = nil
        finished = false
    }
}
