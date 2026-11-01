# 验证记录

- 编译器：Apple Swift 6.4，使用 Swift 6 语言模式；Package 最低工具版本为 Swift 6.0。
- iOS（2026-11-01 更新）：最低版本保持 iOS 15.1。新增构造函数输出类型参数后，以 `arm64-apple-ios15.1-simulator` 和 `arm64-apple-ios15.1` 为目标，均重新通过完整源码模块编译和 WAV 示例类型检查。
- macOS：13 项 XCTest 全部通过，包含本次新增的 Int16 输出、Int16 系统文件解码对照、Int16 reset 与缓冲区生命周期测试。
- `FF F3 48 C4` 测试素材：由 FFmpeg/libmp3lame 生成的 16 kHz / 32 kbps / mono 音频，86 个 144 字节帧，包含非零 `main_data_begin`，实际使用跨帧 bit reservoir。
- 一次输入完整音频、每次 288 字节、每次 1 字节和不规则分包，PCM 逐样本完全一致。
- MPEG-1 stereo、MPEG-2 mono、MPEG-2.5 mono、VBR 的流式 PCM 均与系统 AVAudioFile 完整文件解码结果一致（测试容差小于 1e-6）。
- 上述完整文件对照也覆盖 Int16 输出，容许最多 1 个 Int16 量化单位的差异；Int16 的不同分包输出逐样本完全一致，并验证 `int16ChannelData` 可用、`floatChannelData` 为 nil。
- `MP3StreamDecoder()` 仍默认 Float32；显式选择 `.pcmFormatInt16` 后，reset 保留所选格式。WAV 示例的写入处理格式匹配实际 PCM buffer。
- 其他覆盖：padding、无效头、free-format 拒绝、实时输出、缓冲区生命周期、尾部残帧补齐、结束后拒绝输入、格式改变和 reset。

音频运行测试在可访问系统音频编解码服务的 macOS 环境执行。尚未运行 iPhone 真机测试，也未获得外设的实际音频负载；因此不能据此确认设备是否附带协议头、序号或其他非 MP3 字节。
