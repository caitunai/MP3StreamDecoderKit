# MP3StreamDecoderKit

独立的 Swift 6 音频流解码包，最低支持 iOS 15.1 / macOS 13，不依赖当前杰理项目或第三方解码库。

## 输入与输出

- 输入：按原始顺序到达的 MPEG Layer III 帧字节，保留每帧的 4 字节 MP3 头。
- 输出：`[AVAudioPCMBuffer]`，Float32、非交错，采样率和声道数从帧头获取。
- 支持 MPEG-1 / MPEG-2 / MPEG-2.5，包含 padding 和可变码率；不支持 free-format MP3。
- 支持一次 288 字节、一个字节或其他分包方式；不完整帧自动留到下次调用。
- 持续复用一个 `AudioConverter`，保留 MP3 bit reservoir 等跨帧状态。
- 本包只解码，不配置 `AVAudioSession`、音频播放或 BLE 连接。

## `FF F3 48 C4` 对应的参数

| 参数 | 结果 |
| --- | --- |
| MPEG 版本 | MPEG-2 Layer III |
| 采样率 | 16,000 Hz |
| 码率 | 32,000 bit/s |
| 声道数 | 1 |
| CRC | 无 |
| Padding | 无 |
| 压缩帧长度 | 144 字节，已包含 4 字节头 |
| 每帧 PCM 采样数 | 每声道 576 |
| 每帧时长 | 36 ms |

MPEG-2 Layer III 的压缩帧长度为 `floor(72 × bitRate / sampleRate) + padding`。
因此这里是 `72 × 32000 / 16000 = 144` 字节，288 字节是两帧、名义时长 72 ms。
这需要确认 288 字节全部是 MP3 数据，且开头与帧边界对齐；实现本身不依赖 BLE 包与帧对齐。

## 集成

将本目录作为本地 Swift Package 添加到 Xcode，并给 App target 添加 `MP3StreamDecoderKit` 产品；也可以把 `Sources/MP3StreamDecoderKit/` 下全部 Swift 文件加入 App target。

`Package.swift` 通过 `.iOS("15.1")` 声明最低系统版本。App target 的 iOS Deployment Target 可设置为 `15.1`；Swift 工具版本和语言模式仍为 Swift 6，无需降低。解码源码使用的系统 API 无需为 iOS 15.1 增加替代实现。

```swift
import AVFAudio
import Foundation
import MP3StreamDecoderKit

// 为同一个连续音频流保留同一个实例。
let decoder = MP3StreamDecoder()

// 每次收到 BLE 音频负载时调用；payload 可以是 288 字节或任意长度。
let buffers = try decoder.append(payload)

for buffer in buffers {
    let sampleRate = buffer.format.sampleRate
    let sampleCount = Int(buffer.frameLength)
    if let samples = buffer.floatChannelData?[0] {
        // 对当前设备，samples[0..<sampleCount] 是 16 kHz 单声道 PCM。
        // 在这里计算 RMS、绘制声波、播放，或者写入 AVAudioFile。
        // samples 指针的生命周期依附于 buffer；需要长期保存时保留 buffer 或复制数据。
        _ = (samples, sampleRate, sampleCount)
    }
}

// 仅在音频流真正结束、最后一包已经到达时调用。
let tailBuffers = try decoder.finish()
// 使用与上面相同的逻辑处理 tailBuffers。

// 新录音开始，或发生数据不连续后，需要重新建立状态。
decoder.reset()
```

以上为调用片段，`payload` 由 BLE 接收方提供。完整的 WAV 写入示例在 `Examples/MP3ToWAVExample.swift`。

## 生命周期与错误

所有方法和属性都应从同一个串行执行上下文访问。此类型没有声明 `Sendable`；Swift 6 中可以让一个 actor 或 `@MainActor` 对象独占该实例，避免跨执行上下文共享可变解码状态。

`append` 返回空数组不代表出错，可能正在等待完整帧或更多解码输入。输出缓冲区数量和采样数不保证与单次 BLE 包一一对应。已经返回的 PCM buffer 不会在下一次调用时被覆盖。

`finish()` 才会向转换器发送真正的 EOF；两次 BLE 通知之间暂时没有数据时，内部使用独立的“暂缺输入”状态，不会把它当成 EOF。输出包含编码器延迟和尾部填充；原始帧流没有提供用于精确裁剪的 gapless 元数据。

输入必须是纯 MP3 帧流。ID3 标签、BLE 协议头、序号、校验字段等应由上层剥离，不能把整段通信报文直接交给解码器。需要先确认实际负载的 MP3 起始位置。

本实现不会静默扫描并跳过坏数据。遇到无效头、格式改变或转换错误时抛错，并保持失败状态，直到调用 `reset()`。码率、padding、CRC 标记可以变化；MPEG 版本、采样率和声道数改变时需要开始新的解码会话。丢字节或丢包后应由上层检测并重置；中途恢复仍可能缺少 MP3 bit reservoir 内容，不能保证第一帧立即恢复正常音频。

若 `finish()` 检测到残帧，会抛出 `incompleteFrame`，此时可以继续补齐缺失字节，再调用 `finish()`。成功结束后，`finish()` 可重复调用；新输入需要先 `reset()`。

## 验证

```sh
swift test
```

测试素材由 FFmpeg/libmp3lame 生成，包含与所提供帧头一致的 16 kHz / 32 kbps / mono MP3，以及 MPEG-1 stereo、MPEG-2.5 和 VBR。

测试覆盖帧参数解析、真实跨帧 reservoir、288 字节 / 单字节 / 不规则分包的一致性、实时输出、输出内存生命周期、残帧补齐、重置和格式改变。另将流式输出与系统完整文件解码结果进行比较。

系统 AudioConverter 的运行测试需要允许访问系统音频编解码服务。受限的工具沙箱可能使系统自带的 `afconvert` 同样返回 `fmt?`，这种环境无法完成运行时解码验证。

## 参考

- [Apple AudioConverterFillComplexBuffer](https://developer.apple.com/documentation/audiotoolbox/audioconverterfillcomplexbuffer(_:_:_:_:_:_:))
- [Apple: Encoding and decoding audio](https://developer.apple.com/documentation/audiotoolbox/encoding-and-decoding-audio)
- [RFC 5219: MP3 帧结构与 main_data_begin](https://www.rfc-editor.org/rfc/rfc5219.html#section-3)

