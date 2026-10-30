/// Identifies the MPEG audio version used by a Layer III stream.
public enum MP3Version: Sendable {
    /// MPEG-1 Layer III, with 1,152 PCM frames per compressed frame.
    case mpeg1
    /// MPEG-2 Layer III, with 576 PCM frames per compressed frame.
    case mpeg2
    /// MPEG-2.5 Layer III, with 576 PCM frames per compressed frame.
    case mpeg25
}
