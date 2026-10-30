import AudioToolbox
import Foundation

// Owns all pointers exposed to the C input callback. In particular, the last
// supplied packet stays alive until the callback is invoked again.
internal final class MP3DecoderInput {
    internal static let needMoreData: OSStatus = 0x6E64_6174 // 'ndat'
    internal var packets: [NSData] = []
    internal var nextPacket = 0
    internal var endOfStream = false
    internal var channelCount: UInt32 = 1
    internal var samplesPerFrame: UInt32 = 576
    internal var lastSuppliedPacket: NSData?
    internal let description: UnsafeMutablePointer<AudioStreamPacketDescription>

    internal init() {
        description = .allocate(capacity: 1)
        description.initialize(to: AudioStreamPacketDescription())
    }

    deinit {
        description.deinitialize(count: 1)
        description.deallocate()
    }

    internal func enqueue(_ frames: [Data]) {
        packets.append(contentsOf: frames.map { $0 as NSData })
    }

    internal func discardConsumedPackets() {
        if nextPacket > 0 {
            packets.removeFirst(nextPacket)
            nextPacket = 0
        }
    }

    internal static let callback: AudioConverterComplexInputDataProc = {
        _, packetCount, buffers, packetDescriptions, userData in
        guard let userData else {
            packetCount.pointee = 0
            return kAudio_ParamError
        }
        let input = Unmanaged<MP3DecoderInput>.fromOpaque(userData).takeUnretainedValue()
        input.lastSuppliedPacket = nil

        guard input.nextPacket < input.packets.count else {
            packetCount.pointee = 0
            buffers.pointee.mNumberBuffers = 1
            buffers.pointee.mBuffers = AudioBuffer(
                mNumberChannels: input.channelCount, mDataByteSize: 0, mData: nil
            )
            packetDescriptions?.pointee = nil
            return input.endOfStream ? noErr : MP3DecoderInput.needMoreData
        }

        let packet = input.packets[input.nextPacket]
        input.nextPacket += 1
        input.lastSuppliedPacket = packet
        input.description.pointee = AudioStreamPacketDescription(
            mStartOffset: 0, mVariableFramesInPacket: input.samplesPerFrame,
            mDataByteSize: UInt32(packet.length)
        )
        packetCount.pointee = 1
        buffers.pointee.mNumberBuffers = 1
        buffers.pointee.mBuffers = AudioBuffer(
            mNumberChannels: input.channelCount, mDataByteSize: UInt32(packet.length),
            mData: UnsafeMutableRawPointer(mutating: packet.bytes)
        )
        packetDescriptions?.pointee = input.description
        return noErr
    }
}
