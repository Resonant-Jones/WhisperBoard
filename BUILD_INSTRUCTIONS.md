# WhisperBoard - Build Instructions

Complete guide to building and running WhisperBoard on iOS.

---

## 📋 Prerequisites

### Required Software

- **macOS** 12.0 or later
- **Xcode** 14.0 or later
- **iOS Device** running iOS 14.0+ (Physical device required - simulator not supported)
- **Apple Developer Account** (free or paid)

### Required Knowledge

- Basic Xcode usage
- iOS development fundamentals
- Understanding of code signing and provisioning profiles

---

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/WhisperBoard.git
cd WhisperBoard
```

### 2. Integrate whisper.cpp

WhisperBoard requires whisper.cpp for on-device inference. Follow the [Whisper Integration Guide](WhisperBoard/Whisper/WHISPER_INTEGRATION.md) to:

1. Download whisper.cpp source files
2. Add to Xcode project
3. Download Whisper model (small-Q5_1)
4. Configure build settings

**Quick integration:**

```bash
# Download whisper.cpp
git clone https://github.com/ggerganov/whisper.cpp.git temp_whisper

# Copy required files to project
mkdir -p WhisperBoard/Whisper/whisper-src
cp temp_whisper/whisper.{h,cpp} WhisperBoard/Whisper/whisper-src/
cp temp_whisper/ggml*.{h,c,cpp,m,metal} WhisperBoard/Whisper/whisper-src/

# Download model
curl -L -o WhisperBoard/Resources/ggml-small-q5_1.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin

# Cleanup
rm -rf temp_whisper
```

### 3. Open in Xcode

```bash
open WhisperBoard.xcodeproj
```

### 4. Configure Code Signing

#### Update Bundle Identifiers

Change the bundle identifiers to your own:

1. Select **WhisperBoard** target
2. In **Signing & Capabilities** tab:
   - Change Bundle Identifier from `com.whisperboard.app` to `com.yourname.whisperboard`
3. Select **WhisperBoard Keyboard** target
4. Change Bundle Identifier to `com.yourname.whisperboard.keyboard`

#### Update App Groups

1. For **WhisperBoard** target:
   - Go to **Signing & Capabilities**
   - Under **App Groups**, click the `+` button
   - Add: `group.com.yourname.whisperboard`
   - Remove the old `group.com.whisperboard.app`

2. For **WhisperBoard Keyboard** target:
   - Repeat the same process

3. Update code references:
   - Open `WhisperBoard/Shared/AppGroups.swift`
   - Change `identifier = "group.com.whisperboard.app"` to your App Group ID

#### Sign with Your Team

1. Select both targets (WhisperBoard and WhisperBoard Keyboard)
2. In **Signing & Capabilities**:
   - Team: Select your team
   - Automatically manage signing: ✓ (checked)

### 5. Build and Run

1. Select a physical iOS device (not simulator)
2. Press **⌘R** to build and run
3. Wait for model to load (check console for "✓ Model loaded")

---

## 🔧 Detailed Setup

### Project Structure

```
WhisperBoard/
├── WhisperBoard/
│   ├── App/                      # Main app modules
│   │   ├── AppDelegate.swift     # App lifecycle
│   │   ├── ModelLoader.swift     # Whisper model loading
│   │   ├── InferenceEngine.swift # Transcription engine
│   │   ├── AudioProcessor.swift  # Audio chunk processing
│   │   ├── TokenStream.swift     # IPC token streaming
│   │   ├── ClipboardManager.swift# Clipboard operations
│   │   └── Settings.swift        # Settings management
│   ├── KeyboardExtension/        # Keyboard extension
│   │   ├── KeyboardViewController.swift  # Main keyboard UI
│   │   ├── AudioCapture.swift    # Microphone capture
│   │   ├── TranscriptionDisplay.swift # UI updates
│   │   └── IPCPipe.swift         # IPC with main app
│   ├── Shared/                   # Shared between app & extension
│   │   ├── AppGroups.swift       # App Groups utilities
│   │   └── MessageTypes.swift    # IPC message types
│   ├── Whisper/                  # Whisper.cpp integration
│   │   ├── WhisperBoard-Bridging-Header.h
│   │   ├── WHISPER_INTEGRATION.md
│   │   └── whisper-src/          # Add whisper.cpp files here
│   └── Resources/                # Models and assets
│       └── ggml-small-q5_1.bin   # Whisper model (add manually)
├── docs/
│   └── WhisperBoard_Design_Document.md
└── BUILD_INSTRUCTIONS.md         # This file
```

### Build Settings

#### WhisperBoard Target (Main App)

| Setting | Value |
|---------|-------|
| Deployment Target | iOS 14.0 |
| Architectures | arm64 |
| C++ Language Dialect | GNU++17 |
| Other C Flags | `-DGGML_USE_ACCELERATE -DGGML_USE_METAL -O3` |
| Bridging Header | `WhisperBoard/Whisper/WhisperBoard-Bridging-Header.h` |

**Linked Frameworks:**
- Accelerate.framework
- Metal.framework
- MetalKit.framework
- AVFoundation.framework
- UIKit.framework

#### WhisperBoard Keyboard Target (Extension)

| Setting | Value |
|---------|-------|
| Deployment Target | iOS 14.0 |
| Architectures | arm64 |
| Extension Point | com.apple.ui-services.custom-keyboard |

**Linked Frameworks:**
- AVFoundation.framework
- UIKit.framework

---

## 🎮 Using WhisperBoard

### Enable the Keyboard

After installing:

1. Go to **Settings** → **General** → **Keyboard** → **Keyboards**
2. Tap **Add New Keyboard**
3. Select **WhisperBoard Keyboard**
4. Tap **WhisperBoard Keyboard** again
5. Enable **Allow Full Access** (required for microphone)

### Using Dictation

1. Open any app with text input (Notes, Messages, etc.)
2. Tap the keyboard switcher (globe icon) until WhisperBoard appears
3. **Hold** the microphone button
4. Speak your text
5. **Release** when done
6. Text will be inserted automatically

### Using the Main App

The main app provides:
- Standalone dictation (copy to clipboard)
- Settings configuration
- Model status and memory usage

---

## 🐛 Troubleshooting

### Build Errors

#### "whisper.h file not found"

**Cause:** Bridging header path is incorrect or whisper.cpp not added

**Fix:**
1. Verify whisper.cpp files are in `WhisperBoard/Whisper/whisper-src/`
2. Check Build Settings → "Objective-C Bridging Header" is set correctly
3. Clean build folder (⇧⌘K) and rebuild

#### "Undefined symbols for architecture arm64"

**Cause:** Missing frameworks or incomplete whisper.cpp integration

**Fix:**
1. Add Accelerate.framework to "Link Binary With Libraries"
2. Add Metal.framework
3. Verify all whisper.cpp source files are added to WhisperBoard target

#### "Code Sign Error"

**Cause:** Bundle identifier or App Group mismatch

**Fix:**
1. Use unique bundle identifiers
2. Ensure App Groups match between:
   - Entitlements files
   - Info.plist
   - AppGroups.swift code
3. Re-sign with your team

### Runtime Issues

#### Model Not Loading

**Symptoms:**
- Console shows "Model file not found"
- Status shows "Loading model..." forever

**Fix:**
1. Verify `ggml-small-q5_1.bin` is in `WhisperBoard/Resources/`
2. Check file is added to WhisperBoard target (not keyboard extension)
3. File size should be ~150 MB

#### Keyboard Not Appearing

**Symptoms:**
- Keyboard doesn't show in Settings → Keyboards

**Fix:**
1. Rebuild and reinstall app
2. Check keyboard extension target is being built
3. Verify Info.plist for keyboard extension is correct

#### Microphone Not Working

**Symptoms:**
- "Microphone error" message in keyboard
- No audio captured

**Fix:**
1. Go to Settings → Privacy → Microphone
2. Enable for WhisperBoard
3. In keyboard settings, enable "Allow Full Access"

#### App Crashes on Launch

**Symptoms:**
- App crashes immediately or during model load

**Fix:**
1. Check device has enough free storage (model is ~150 MB)
2. Test on newer device (iPhone 11 or later recommended)
3. Try smaller model (tiny-Q5_1) for old devices
4. Check console for memory pressure warnings

#### High Memory Usage

**Symptoms:**
- App crashes with "Memory pressure" warnings
- Device performance degrades

**Fix:**
1. Use Q4_0 quantization instead of Q5_1 (120 MB vs 150 MB)
2. Reduce chunk size in settings
3. Test on device with more RAM (3GB+)

---

## 🧪 Testing

### Unit Tests

Currently, WhisperBoard focuses on integration testing on real devices.

To add unit tests:
1. Create test target in Xcode
2. Add tests for:
   - Audio format conversion
   - IPC message serialization
   - App Groups file operations

### Manual Testing Checklist

- [ ] Model loads successfully on app launch
- [ ] Keyboard appears in Settings → Keyboards
- [ ] Microphone permission granted
- [ ] "Allow Full Access" enabled
- [ ] Keyboard shows up when tapped
- [ ] Hold-to-record works
- [ ] Transcription appears in real-time
- [ ] Text inserts into text field correctly
- [ ] Works in multiple apps (Notes, Messages, Safari)
- [ ] Memory usage stays under 400 MB
- [ ] No crashes during extended use
- [ ] Clipboard fallback works in restricted apps

### Performance Testing

Run on devices:
- iPhone 11 (A13) - minimum recommended
- iPhone 12 (A14)
- iPhone 13/14/15 (A15/A16/A17)

Measure:
- Cold start time (app launch to model ready)
- First token latency (press to first transcription)
- Streaming latency (ongoing transcription delay)
- Peak memory usage during inference

Expected results:
- Cold start: < 1.5 seconds
- First token: < 350 ms (A15+), < 450 ms (A14), < 500 ms (A13)
- Streaming: 300-800 ms delay
- Peak memory: 350-400 MB

---

## 📦 Distribution

### TestFlight

1. Archive the app (Product → Archive)
2. Distribute to App Store Connect
3. Add to TestFlight
4. Invite testers

### App Store

1. Complete App Review Information:
   - Privacy policy (not required if truly offline)
   - Description emphasizing offline/privacy
   - Screenshots showing keyboard in use

2. Important notes for review:
   - Emphasize 100% offline operation
   - No data collection
   - Microphone is only for transcription
   - All processing on-device

3. Pricing: $1.00 (as per design doc)

4. Submit for review

---

## 🔐 Privacy Compliance

WhisperBoard is designed to be **100% offline** and privacy-first:

- ✅ No network access (no network entitlements)
- ✅ No analytics or telemetry
- ✅ No cloud APIs
- ✅ No data collection
- ✅ Audio is ephemeral (not stored)
- ✅ All processing on-device

**App Store Privacy Labels:**
- Data Not Collected: ✓

---

## 🤝 Contributing

To contribute to WhisperBoard:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test on real devices
5. Submit a pull request

Areas for contribution:
- Performance optimization
- Additional language support
- UI/UX improvements
- Bug fixes
- Documentation

---

## 📄 License

MIT License - See LICENSE file for details

---

## 🆘 Support

For issues or questions:

1. Check [Troubleshooting](#troubleshooting) section
2. Review [Whisper Integration Guide](WhisperBoard/Whisper/WHISPER_INTEGRATION.md)
3. Check whisper.cpp documentation
4. Open an issue on GitHub

---

## 🙏 Acknowledgments

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) by Georgi Gerganov
- [OpenAI Whisper](https://github.com/openai/whisper) team
- iOS development community

---

**Happy Building! 🎤**
