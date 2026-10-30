These fixtures contain generated sine waves, not user recordings. They were
encoded locally with FFmpeg and libmp3lame, with Xing and ID3v2 headers disabled.

- mono-16k-32k.mp3: 440 Hz, 3 seconds, 16 kHz mono, 32 kbit/s CBR.
- stereo-44k-128k.mp3: 660 Hz, 1 second, 44.1 kHz stereo, 128 kbit/s CBR.
- mono-8k-16k.mp3: 330 Hz, 1 second, 8 kHz mono, 16 kbit/s CBR.
- stereo-vbr.mp3: 550 Hz, 1 second, 44.1 kHz stereo, libmp3lame VBR quality 4.

The encoder adds normal MP3 startup delay and trailing padding.
