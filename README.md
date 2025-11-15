# 🎤 WhisperBoard

**100% Offline Voice-to-Text Keyboard for iOS**

Local-first AI keyboard powered by Whisper-small, running entirely on-device with no cloud, no tracking, and no data collection.

[![iOS](https://img.shields.io/badge/iOS-14.0+-blue.svg)](https://www.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.5+-orange.svg)](https://swift.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Privacy](https://img.shields.io/badge/Privacy-100%25%20Offline-success.svg)]()

---

## ✨ Features

- 🔒 **100% Offline** - All processing on-device, no network required
- 🎯 **Privacy-First** - No data collection, analytics, or tracking
- ⚡ **Fast** - Real-time transcription with <350ms first-token latency
- 🧠 **Accurate** - Whisper-small Q5_1 model for high-quality transcription
- 📱 **Native iOS** - Custom keyboard extension + standalone app
- 🌍 **Multilingual** - Supports all languages Whisper supports
- 💾 **Memory-Safe** - Optimized for iPhone RAM constraints (350-400 MB peak)
- 🎨 **Simple UI** - One-button dictation: hold to speak, release to insert

---

## 🚀 Quick Start

### For Users

1. **Download** WhisperBoard from the App Store (coming soon)
2. **Enable** the keyboard in Settings → General → Keyboard → Keyboards
3. **Grant** microphone permission and "Allow Full Access"
4. **Use** by switching to WhisperBoard keyboard and holding the mic button

### For Developers

See [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md) for complete setup guide.

**Quick build:**

```bash
# Clone repository
git clone https://github.com/your-org/WhisperBoard.git
cd WhisperBoard

# Integrate whisper.cpp (see BUILD_INSTRUCTIONS.md)
# Download model
# Open in Xcode and build
```

---

## 🏗️ Architecture

WhisperBoard uses a **two-process architecture** to work within iOS memory constraints:

```
┌─────────────────────────┐        ┌──────────────────────────┐
│  Keyboard Extension     │◄──────►│      Main App            │
│  (80-150 MB RAM)        │  IPC   │      (1GB+ RAM)          │
├─────────────────────────┤        ├──────────────────────────┤
│ • Audio Capture (16kHz) │───────►│ • Whisper-small (Q5_1)   │
│ • UI & Display          │        │ • Mel Spectrogram        │
│ • Text Insertion        │◄───────│ • Inference Engine       │
└─────────────────────────┘        └──────────────────────────┘
         ▲                                    │
         │         App Groups Container       │
         └────────────────────────────────────┘
                  (Shared Storage)
```

**Key Components:**

- **Keyboard Extension**: Lightweight UI, captures audio, displays transcription
- **Main App**: Loads Whisper model, runs inference, streams results back
- **IPC Layer**: App Groups + file-based communication for audio chunks and tokens

---

## 📊 Performance

Expected latency on different devices (Whisper-small Q5_1):

| Device | Chip | First Token | Streaming Latency | Peak RAM |
|--------|------|-------------|-------------------|----------|
| iPhone 11 | A13 | ~420ms | 500-900ms | 380 MB |
| iPhone 12 | A14 | ~380ms | 450-750ms | 350 MB |
| iPhone 13 | A15 | ~300ms | 350-600ms | 330 MB |
| iPhone 14 | A16 | ~280ms | 330-550ms | 330 MB |
| iPhone 15 | A17 | ~240ms | 300-500ms | 330 MB |

**Model Sizes:**

| Variant | Model Size | Peak RAM | Accuracy | Speed |
|---------|-----------|----------|----------|-------|
| small Q4_0 | 120 MB | 330 MB | Good | Fastest |
| **small Q5_1** | **150 MB** | **380 MB** | **Better** | **Recommended** |
| small Q8_0 | 280 MB | 500 MB | Best | Slower |
| tiny Q5_1 | 80 MB | 200 MB | Fair | Very Fast |

---

## 🛠️ Technology Stack

- **Language**: Swift 5.5+
- **ML Framework**: [whisper.cpp](https://github.com/ggerganov/whisper.cpp) (C++ with Metal acceleration)
- **Audio**: AVFoundation (16kHz mono PCM)
- **IPC**: App Groups + NSFileCoordinator
- **Frameworks**: Accelerate, Metal, MetalKit
- **Minimum iOS**: 14.0
- **Minimum Device**: iPhone 11 (A13) recommended

---

## 📁 Project Structure

```
WhisperBoard/
├── WhisperBoard/
│   ├── App/                    # Main app modules
│   │   ├── AppDelegate.swift
│   │   ├── ModelLoader.swift
│   │   ├── InferenceEngine.swift
│   │   ├── AudioProcessor.swift
│   │   ├── TokenStream.swift
│   │   ├── ClipboardManager.swift
│   │   └── Settings.swift
│   ├── KeyboardExtension/      # Keyboard extension
│   │   ├── KeyboardViewController.swift
│   │   ├── AudioCapture.swift
│   │   ├── TranscriptionDisplay.swift
│   │   └── IPCPipe.swift
│   ├── Shared/                 # Shared utilities
│   │   ├── AppGroups.swift
│   │   └── MessageTypes.swift
│   ├── Whisper/                # whisper.cpp integration
│   └── Resources/              # Models and assets
├── docs/
│   └── WhisperBoard_Design_Document.md
├── BUILD_INSTRUCTIONS.md
└── README.md
```

---

## 🔐 Privacy & Security

WhisperBoard is designed with **privacy as the top priority**:

✅ **No Network Access**
- No network entitlements in app or keyboard extension
- Impossible to send data even if code was compromised

✅ **No Data Collection**
- No analytics, telemetry, or logging
- No user tracking of any kind

✅ **Ephemeral Processing**
- Audio is processed in memory only
- No recordings saved to disk
- Transcription text is ephemeral

✅ **On-Device ML**
- All inference runs locally
- No cloud APIs or servers
- Whisper model bundled with app

✅ **Open Source**
- Full source code available for audit
- Community-driven development

---

## 🎯 Use Cases

- **Accessibility**: Voice input for users who prefer or need dictation
- **Privacy-Conscious Users**: No cloud transcription services
- **Offline Environments**: Works without internet (airplane, remote areas)
- **Secure Environments**: No data leaving device
- **Multilingual Users**: Supports 99+ languages via Whisper

---

## 🗺️ Roadmap

### v1.0 (Initial Release)
- [x] Core offline transcription
- [x] Custom keyboard extension
- [x] Whisper-small Q5_1 integration
- [x] Real-time streaming
- [x] Clipboard fallback
- [x] Basic settings

### v1.1 (Planned)
- [ ] Voice Activity Detection (VAD)
- [ ] Punctuation mode toggle
- [ ] Language selection UI
- [ ] Model variant switching
- [ ] Improved error handling
- [ ] Performance optimizations

### v1.2+ (Future)
- [ ] Custom vocabulary/corrections
- [ ] Keyboard themes
- [ ] Advanced settings
- [ ] iPad support with larger models
- [ ] CoreML model option

---

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

**Areas for contribution:**
- Performance optimization
- UI/UX improvements
- Additional language support
- Bug fixes
- Documentation
- Testing on different devices

---

## 📖 Documentation

- [Design Document](docs/WhisperBoard_Design_Document.md) - Complete architecture and design decisions
- [Build Instructions](BUILD_INSTRUCTIONS.md) - How to build and run WhisperBoard
- [Whisper Integration](WhisperBoard/Whisper/WHISPER_INTEGRATION.md) - Integrating whisper.cpp

---

## 🙏 Acknowledgments

WhisperBoard is built on the shoulders of giants:

- **[whisper.cpp](https://github.com/ggerganov/whisper.cpp)** by Georgi Gerganov - Efficient C++ implementation of Whisper
- **[OpenAI Whisper](https://github.com/openai/whisper)** - Original Whisper model and research
- **iOS Development Community** - Countless tutorials and examples

---

## 📄 License

MIT License - See [LICENSE](LICENSE) file for details.

---

## 💬 Support

- **Issues**: Report bugs or request features via [GitHub Issues](https://github.com/your-org/WhisperBoard/issues)
- **Discussions**: Join the conversation in [GitHub Discussions](https://github.com/your-org/WhisperBoard/discussions)
- **Build Help**: See [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md)

---

## 🌟 Star History

If you find WhisperBoard useful, please give it a star! ⭐

---

**Built with ❤️ for privacy-conscious iOS users**

*WhisperBoard: Your voice, your device, your privacy.*
