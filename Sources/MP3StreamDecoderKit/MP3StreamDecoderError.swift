import Foundation

/// Describes a framing, lifecycle, or Core Audio decoding failure.
public enum MP3StreamDecoderError: Error, LocalizedError {
    /// Fewer than four bytes were provided to the header parser.
    case insufficientHeader
    /// The next bytes do not form a supported MPEG Layer III header.
    case invalidFrameHeader
    /// Free-format MP3 requires frame-length discovery and is unsupported.
    case unsupportedFreeBitrate
    /// The MPEG version, sample rate, or channel count changed midstream.
    case formatChanged
    /// A Core Audio operation returned an error status.
    case audioToolbox(operation: String, status: Int32)
    /// A PCM output buffer could not be allocated.
    case allocationFailed
    /// End of stream was requested while a partial frame remained.
    case incompleteFrame(remainingBytes: Int)
    /// More input was supplied after the stream had finished.
    case alreadyFinished

    /// A human-readable explanation of the failure.
    public var errorDescription: String? {
        switch self {
        case .insufficientHeader:
            return "An MP3 header requires at least four bytes."
        case .invalidFrameHeader:
            return "The input does not start with a valid supported MP3 frame."
        case .unsupportedFreeBitrate:
            return "Free-format MP3 is unsupported."
        case .formatChanged:
            return "The MP3 stream format changed. Reset the decoder before starting a new stream."
        case let .audioToolbox(operation, status):
            return "\(operation) failed with OSStatus \(status)."
        case .allocationFailed:
            return "A PCM output buffer could not be allocated."
        case let .incompleteFrame(remainingBytes):
            return "The stream ends with \(remainingBytes) bytes of an incomplete MP3 frame."
        case .alreadyFinished:
            return "The decoder has finished. Reset it before appending more data."
        }
    }
}
