import AudioToolbox
import Foundation

/// Describes the format and size encoded in a four-byte MP3 frame header.
public struct MP3FrameHeader: Sendable {
    /// The MPEG audio version.
    public let version: MP3Version
    /// The compressed bit rate in bits per second.
    public let bitRate: Int
    /// The sample rate in hertz.
    public let sampleRate: Int
    /// The number of audio channels.
    public let channelCount: Int
    /// Whether a two-byte CRC follows the header.
    public let hasCRC: Bool
    /// Whether the compressed frame contains a padding byte.
    public let isPadded: Bool
    /// The full compressed frame size, including header, CRC, and padding.
    public let frameByteCount: Int
    /// The number of decoded PCM frames per channel before codec delay handling.
    public let samplesPerFrame: Int
    /// The nominal audio duration of one compressed frame, in seconds.
    public var duration: TimeInterval {
        Double(samplesPerFrame) / Double(sampleRate)
    }

    /// Parses the first four bytes without requiring a complete compressed frame.
    ///
    /// - Parameter data: Bytes beginning with an MPEG Layer III frame header.
    /// - Throws: `MP3StreamDecoderError` if the header is incomplete or unsupported.
    public init(data: Data) throws {
        self = try data.withUnsafeBytes { try MP3FrameHeader.parse($0) }
    }

    internal init(
        version: MP3Version, bitRate: Int, sampleRate: Int, channelCount: Int,
        hasCRC: Bool, isPadded: Bool, frameByteCount: Int, samplesPerFrame: Int
    ) {
        self.version = version
        self.bitRate = bitRate
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.hasCRC = hasCRC
        self.isPadded = isPadded
        self.frameByteCount = frameByteCount
        self.samplesPerFrame = samplesPerFrame
    }

    internal static func parse(_ bytes: UnsafeRawBufferPointer) throws -> MP3FrameHeader {
        guard bytes.count >= 4 else { throw MP3StreamDecoderError.insufficientHeader }
        let word = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16)
            | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
        let versionBits = (word >> 19) & 3
        let layerBits = (word >> 17) & 3
        let rateIndex = Int((word >> 10) & 3)
        let bitRateIndex = Int((word >> 12) & 15)
        guard word & 0xFFE0_0000 == 0xFFE0_0000,
              versionBits != 1, layerBits == 1,
              rateIndex != 3, bitRateIndex != 15,
              word & 3 != 2 else {
            throw MP3StreamDecoderError.invalidFrameHeader
        }
        guard bitRateIndex != 0 else { throw MP3StreamDecoderError.unsupportedFreeBitrate }

        let version: MP3Version
        let divisor: Int
        switch versionBits {
        case 3: version = .mpeg1; divisor = 1
        case 2: version = .mpeg2; divisor = 2
        default: version = .mpeg25; divisor = 4
        }
        let rates = version == .mpeg1
            ? [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
            : [8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]
        let bitRate = rates[bitRateIndex - 1] * 1_000
        let sampleRate = [44_100, 48_000, 32_000][rateIndex] / divisor
        let padded = (word >> 9) & 1 != 0
        let frameByteCount = (version == .mpeg1 ? 144 : 72) * bitRate / sampleRate
            + (padded ? 1 : 0)
        return MP3FrameHeader(
            version: version, bitRate: bitRate, sampleRate: sampleRate,
            channelCount: (word >> 6) & 3 == 3 ? 1 : 2,
            hasCRC: (word >> 16) & 1 == 0, isPadded: padded,
            frameByteCount: frameByteCount,
            samplesPerFrame: version == .mpeg1 ? 1_152 : 576
        )
    }

    internal func isCompatible(with other: MP3FrameHeader) -> Bool {
        version == other.version && sampleRate == other.sampleRate
            && channelCount == other.channelCount
    }

    internal func makeInputDescription() -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: Double(sampleRate), mFormatID: kAudioFormatMPEGLayer3,
            mFormatFlags: 0, mBytesPerPacket: 0,
            mFramesPerPacket: UInt32(samplesPerFrame), mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(channelCount), mBitsPerChannel: 0, mReserved: 0
        )
    }
}
