import AVFAudio
import Foundation
import XCTest
@testable import MP3StreamDecoderKit

final class MP3StreamDecoderTests: XCTestCase {
    func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: name, withExtension: "mp3", subdirectory: "Fixtures"
        ))
        return try Data(contentsOf: url)
    }

    func collect(_ buffers: [AVAudioPCMBuffer], into channels: inout [[Float]]) {
        for buffer in buffers {
            XCTAssertEqual(buffer.format.commonFormat, .pcmFormatFloat32)
            XCTAssertFalse(buffer.format.isInterleaved)
            if channels.isEmpty {
                channels = Array(repeating: [], count: Int(buffer.format.channelCount))
            }
            for channel in channels.indices {
                let pointer = buffer.floatChannelData![channel]
                channels[channel].append(contentsOf: UnsafeBufferPointer(
                    start: pointer, count: Int(buffer.frameLength)
                ))
            }
        }
    }

    func decode(_ data: Data, pattern: [Int]) throws -> [[Float]] {
        let decoder = MP3StreamDecoder()
        var offset = 0
        var index = 0
        var result: [[Float]] = []
        while offset < data.count {
            let count = min(pattern[index % pattern.count], data.count - offset)
            collect(try decoder.append(data.subdata(in: offset..<(offset + count))), into: &result)
            offset += count
            index += 1
        }
        collect(try decoder.finish(), into: &result)
        return result
    }

    func collectInt16(_ buffers: [AVAudioPCMBuffer], into channels: inout [[Int16]]) {
        for buffer in buffers {
            XCTAssertEqual(buffer.format.commonFormat, .pcmFormatInt16)
            XCTAssertFalse(buffer.format.isInterleaved)
            XCTAssertNil(buffer.floatChannelData)
            guard let pointers = buffer.int16ChannelData else {
                XCTFail("Int16 output must expose int16ChannelData")
                continue
            }
            if channels.isEmpty {
                channels = Array(repeating: [], count: Int(buffer.format.channelCount))
            }
            for channel in channels.indices {
                channels[channel].append(contentsOf: UnsafeBufferPointer(
                    start: pointers[channel], count: Int(buffer.frameLength)
                ))
            }
        }
    }

    func decodeInt16(_ data: Data, pattern: [Int]) throws -> [[Int16]] {
        let decoder = MP3StreamDecoder(outputCommonFormat: .pcmFormatInt16)
        var offset = 0
        var index = 0
        var result: [[Int16]] = []
        while offset < data.count {
            let count = min(pattern[index % pattern.count], data.count - offset)
            collectInt16(try decoder.append(data.subdata(in: offset..<(offset + count))), into: &result)
            offset += count
            index += 1
        }
        collectInt16(try decoder.finish(), into: &result)
        return result
    }

    func testInt16OutputAndByteBoundaries() throws {
        let defaultDecoder = MP3StreamDecoder()
        XCTAssertEqual(defaultDecoder.outputCommonFormat, .pcmFormatFloat32)
        XCTAssertEqual(
            MP3StreamDecoder(outputCommonFormat: .pcmFormatFloat32).outputCommonFormat,
            .pcmFormatFloat32
        )
        let data = try fixture("mono-16k-32k")
        let expected = try decodeInt16(data, pattern: [data.count])
        XCTAssertEqual(expected.count, 1)
        XCTAssertEqual(expected[0].count, data.count / 144 * 576)
        XCTAssertGreaterThan(expected[0].map { abs(Int($0)) }.max() ?? 0, 100)
        for pattern in [[288], [1], [143, 1, 145], [1, 2, 3, 5, 7, 13, 287, 1_024]] {
            XCTAssertEqual(try decodeInt16(data, pattern: pattern), expected, "Pattern: \(pattern)")
        }
    }

    func testInt16MatchesSystemFileDecoder() throws {
        for name in ["mono-16k-32k", "stereo-44k-128k", "mono-8k-16k", "stereo-vbr"] {
            let url = try XCTUnwrap(Bundle.module.url(
                forResource: name, withExtension: "mp3", subdirectory: "Fixtures"
            ))
            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: false)
            var expected: [[Int16]] = []
            while file.framePosition < file.length {
                let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_096))
                let remaining = AVAudioFrameCount(min(4_096, file.length - file.framePosition))
                try file.read(into: buffer, frameCount: remaining)
                if buffer.frameLength == 0 { break }
                collectInt16([buffer], into: &expected)
            }
            let data = try Data(contentsOf: url)
            let actual = try decodeInt16(data, pattern: [288, 7, 401])
            XCTAssertEqual(actual.count, expected.count, name)
            for channel in 0..<min(actual.count, expected.count) {
                XCTAssertEqual(actual[channel].count, expected[channel].count, name)
                let maximumError = zip(actual[channel], expected[channel]).map {
                    abs(Int($0) - Int($1))
                }.max() ?? 0
                XCTAssertLessThanOrEqual(maximumError, 1, "System Int16 reference mismatch: \(name)")
            }
            XCTAssertEqual(try decodeInt16(data, pattern: [data.count]), actual, name)
        }
    }

    func testInt16ResetAndBufferLifetime() throws {
        let data = try fixture("mono-16k-32k")
        let decoder = MP3StreamDecoder(outputCommonFormat: .pcmFormatInt16)
        XCTAssertNil(decoder.outputFormat)
        let first = try decoder.append(data.prefix(288))
        XCTAssertEqual(decoder.outputFormat?.commonFormat, .pcmFormatInt16)
        XCTAssertEqual(decoder.outputFormat?.sampleRate, 16_000)
        var snapshot: [[Int16]] = []
        collectInt16(first, into: &snapshot)
        XCTAssertFalse(snapshot.isEmpty)
        _ = try decoder.append(data.dropFirst(288))
        _ = try decoder.finish()
        var after: [[Int16]] = []
        collectInt16(first, into: &after)
        XCTAssertEqual(after, snapshot)
        decoder.reset()
        XCTAssertNil(decoder.outputFormat)
        XCTAssertEqual(decoder.outputCommonFormat, .pcmFormatInt16)
        var restarted: [[Int16]] = []
        collectInt16(try decoder.append(data.prefix(288)), into: &restarted)
        XCTAssertEqual(restarted, snapshot)
    }

    func testProvidedHeader() throws {
        let header = try MP3FrameHeader(data: Data([0xFF, 0xF3, 0x48, 0xC4]))
        XCTAssertEqual(header.version, .mpeg2)
        XCTAssertEqual(header.bitRate, 32_000)
        XCTAssertEqual(header.sampleRate, 16_000)
        XCTAssertEqual(header.channelCount, 1)
        XCTAssertFalse(header.hasCRC)
        XCTAssertFalse(header.isPadded)
        XCTAssertEqual(header.frameByteCount, 144)
        XCTAssertEqual(header.samplesPerFrame, 576)
        XCTAssertEqual(header.duration, 0.036, accuracy: 1e-12)
    }

    func testRealMPEG2AudioAndReservoir() throws {
        let data = try fixture("mono-16k-32k")
        XCTAssertEqual(data.count % 144, 0)
        var reservoirFrames = 0
        for offset in stride(from: 0, to: data.count, by: 144) {
            XCTAssertEqual(data.subdata(in: offset..<(offset + 4)), Data([0xFF, 0xF3, 0x48, 0xC4]))
            if data[offset + 4] != 0 { reservoirFrames += 1 }
        }
        XCTAssertGreaterThan(reservoirFrames, 0, "Fixture must exercise inter-frame reservoir dependencies")
        let channels = try decode(data, pattern: [288])
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].count, data.count / 144 * 576)
        XCTAssertTrue(channels[0].allSatisfy(\.isFinite))
        // Exclude encoder startup and end padding when measuring tonal purity.
        let samples = Array(channels[0].dropFirst(2_000).dropLast(2_000))
        let power = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        XCTAssertGreaterThan(power / Double(samples.count), 0.001)
        let cosine = samples.enumerated().reduce(0.0) {
            $0 + Double($1.element) * cos(2 * .pi * 440 * Double($1.offset) / 16_000)
        }
        let sine = samples.enumerated().reduce(0.0) {
            $0 + Double($1.element) * sin(2 * .pi * 440 * Double($1.offset) / 16_000)
        }
        let tonePower = 2 * (cosine * cosine + sine * sine) / Double(samples.count)
        XCTAssertGreaterThan(tonePower / power, 0.98, "Decoded signal should recover the encoded 440 Hz tone")
    }

    func testArbitraryByteBoundariesMatchWholeStream() throws {
        let data = try fixture("mono-16k-32k")
        let expected = try decode(data, pattern: [data.count])
        for pattern in [[288], [1], [143, 1, 145], [1, 2, 3, 5, 7, 13, 287, 1_024]] {
            XCTAssertEqual(try decode(data, pattern: pattern), expected, "Pattern: \(pattern)")
        }
    }

    func testMatchesSystemFileDecoder() throws {
        for name in ["mono-16k-32k", "stereo-44k-128k", "mono-8k-16k", "stereo-vbr"] {
            let url = try XCTUnwrap(Bundle.module.url(
                forResource: name, withExtension: "mp3", subdirectory: "Fixtures"
            ))
            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            var expected: [[Float]] = []
            while file.framePosition < file.length {
                let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_096))
                let remaining = AVAudioFrameCount(min(4_096, file.length - file.framePosition))
                try file.read(into: buffer, frameCount: remaining)
                if buffer.frameLength == 0 { break }
                collect([buffer], into: &expected)
            }
            let actual = try decode(Data(contentsOf: url), pattern: [288])
            XCTAssertEqual(actual.count, expected.count, name)
            for channel in 0..<min(actual.count, expected.count) {
                XCTAssertEqual(actual[channel].count, expected[channel].count, name)
                let maximumError = zip(actual[channel], expected[channel]).map { abs($0 - $1) }.max() ?? 0
                XCTAssertLessThan(maximumError, 1e-6, "System reference mismatch: \(name)")
            }
        }
    }

    func testPCMEmittedBeforeEndOfStreamAndBuffersStayValid() throws {
        let data = try fixture("mono-16k-32k")
        let decoder = MP3StreamDecoder()
        let first = try decoder.append(data.prefix(288))
        let format = try XCTUnwrap(decoder.outputFormat)
        XCTAssertEqual(format.sampleRate, 16_000)
        XCTAssertEqual(format.channelCount, 1)
        var snapshot: [[Float]] = []
        collect(first, into: &snapshot)
        XCTAssertFalse(snapshot.isEmpty)
        _ = try decoder.append(data.dropFirst(288))
        var after: [[Float]] = []
        collect(first, into: &after)
        XCTAssertEqual(after, snapshot)
    }

    func testPartialFinalFrameCanBeCompleted() throws {
        let data = try fixture("mono-16k-32k")
        let decoder = MP3StreamDecoder()
        _ = try decoder.append(data.dropLast())
        XCTAssertThrowsError(try decoder.finish()) { error in
            guard case MP3StreamDecoderError.incompleteFrame(let count) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(count, 143)
        }
        _ = try decoder.append(data.suffix(1))
        _ = try decoder.finish()
        XCTAssertTrue(try decoder.finish().isEmpty)
        XCTAssertThrowsError(try decoder.append(data))
    }

    func testResetAndInvalidData() throws {
        let data = try fixture("mono-16k-32k")
        let decoder = MP3StreamDecoder()
        XCTAssertTrue(try decoder.append(Data()).isEmpty)
        XCTAssertThrowsError(try decoder.append(Data([0, 0, 0, 0])))
        XCTAssertThrowsError(try decoder.append(data))
        decoder.reset()
        XCTAssertNil(decoder.outputFormat)
        var actual: [[Float]] = []
        collect(try decoder.append(data), into: &actual)
        collect(try decoder.finish(), into: &actual)
        XCTAssertEqual(actual, try decode(data, pattern: [288]))
    }

    func testFormatChangeIsRejected() throws {
        let data = try fixture("mono-16k-32k")
        let decoder = MP3StreamDecoder()
        _ = try decoder.append(data.prefix(288))
        XCTAssertThrowsError(try decoder.append(Data([0xFF, 0xF3, 0x48, 0x04]))) { error in
            guard case MP3StreamDecoderError.formatChanged = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testMPEG1StereoPaddingAndMPEG25() throws {
        for name in ["stereo-44k-128k", "mono-8k-16k", "stereo-vbr"] {
            let data = try fixture(name)
            let expected = try decode(data, pattern: [data.count])
            XCTAssertEqual(try decode(data, pattern: [288, 7, 401]), expected)
            let header = try MP3FrameHeader(data: data)
            XCTAssertEqual(expected.count, header.channelCount)
            XCTAssertFalse(expected[0].isEmpty)
            XCTAssertGreaterThan(expected[0].reduce(0) { $0 + abs($1) }, 1)
        }
    }

    func testHeaderValidationAndPadding() throws {
        XCTAssertThrowsError(try MP3FrameHeader(data: Data([0xFF])))
        XCTAssertThrowsError(try MP3FrameHeader(data: Data([0, 0, 0, 0])))
        XCTAssertThrowsError(try MP3FrameHeader(data: Data([0xFF, 0xF3, 0x08, 0xC4])))
        let padded = try MP3FrameHeader(data: Data([0xFF, 0xF3, 0x4A, 0xC4]))
        XCTAssertEqual(padded.frameByteCount, 145)
        XCTAssertTrue(padded.isPadded)
    }
}
