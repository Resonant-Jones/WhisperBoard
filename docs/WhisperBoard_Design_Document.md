# **WhisperBoard — iOS Offline Voice Keyboard**

**Design Document (v1.0)**
**Author:** Chris Castillo
**License:** MIT (suggested)
**Price:** $1 on the App Store (covers development labor; no data collection; no backend)

---

# 1. **Overview**

**WhisperBoard** is a fully offline, privacy-first voice-to-text keyboard for iOS built on **Whisper-small (quantized)** running locally on-device.
It works as both:

1. A **custom keyboard extension** for low-latency dictation
2. A **standalone app** that performs full offline transcription and pipes results back to the keyboard or clipboard

WhisperBoard is designed to be:

* **100% offline**
* **Fast enough for real-time dictation**
* **Safe from iOS memory pressure kills**
* **Easy to maintain**
* **Open-source so others can improve it**

There is no logging, analytics, telemetry, or remote servers.
If an update is needed, it is delivered through the App Store.

---

# 2. **Goals & Constraints**

## Primary Goals

* Reliable fully offline dictation.
* Whisper-small inference on iPhone without RAM crashes.
* Simple UI: one button → hold to dictate.
* Zero data collection.

## Non-Goals

* Not aiming for cloud-level accuracy.
* No background continuous listening.
* No user tracking or analytics.
* No complex language packs (only Whisper’s built-in multilingual capability).

## iOS Constraints

* **Keyboard extensions get ~80–150 MB RAM.**
  Whisper-small cannot run inside an extension directly.

* **Main app can access more RAM**, often > 1 GB.

Thus WhisperBoard uses a **two-process architecture**:

* Extension: UI, audio capture, sending PCM.
* App: Model inference.

---

# 3. **Architecture Summary**

WhisperBoard uses a split architecture to survive iOS RAM management.

### **Keyboard Extension**

* Lightweight UI
* Captures raw PCM audio
* Streams audio frames to main app
* Receives text output back
* Displays real-time transcription

### **Main App**

* Loads Whisper-small (quantized GGUF)
* Performs mel spectrogram + inference
* Streams partial tokens back
* Handles punctuation modes
* Provides clipboard fallback transcription

### **Communication Layer**

* Uses **NSFileCoordinator + App Groups** or **XPC** for secure data transfer
* PCM → main app
* Tokens → keyboard extension

---

# 4. **Model Selection**

### **Chosen Model:**

**Whisper-small (quantized, GGUF format)**

Options:

| Variant        | Size           | Peak RAM      | Notes                                     |
| -------------- | -------------- | ------------- | ----------------------------------------- |
| small (FP16)   | ~480MB         | ~900MB        | Impossible on keyboard; risky even in app |
| small Q8       | ~280MB         | ~500MB        | Heavy for older iPhones                   |
| **small Q5_1** | **~135–150MB** | **350–400MB** | Optimal balance                           |
| small Q4_K_M   | ~120MB         | ~330MB        | Fastest; slight accuracy hit              |

### **Recommendation:**

**Whisper-small Q5_1** for best accuracy under iOS constraints.

### **Expected RAM Usage (main app)**

| Device               | Peak RAM Load | Safe? |
| -------------------- | ------------- | ----- |
| iPhone XR / 11 (A12) | ~380MB        | Yes   |
| iPhone 12 (A14)      | ~350MB        | Yes   |
| iPhone 13–15         | 330–350MB     | Yes   |
| iPhone SE (2020)     | 375MB         | Yes   |
| iPhone 8 & older     | Not supported |       |

---

# 5. **Memory Budget & iOS Constraints**

### Keyboard extension RAM:

* 80–150MB
  Whisper-small cannot load here.
  **Solution:** extension streams audio → app.

### Main app RAM:

* ≥ 1GB available
  Safe for Whisper-small Q5_1.

### Memory Survival Techniques

* Pre-allocate mel buffers
* Avoid dynamic allocation inside audio loop
* Reuse model context across requests
* Use streaming inference (small audio chunks)
* Warm-load model on app open
* Apply VAD or manual start/stop to avoid continuous inference
* Pin memory pages (as available via C++ or Accelerate)

---

# 6. **Two-Process Architecture (Keyboard ↔ App)**

### Why this is required

iOS kills keyboard extensions for even small spikes in memory.
Running Whisper-small inside the extension is impossible.

### Architecture Diagram

```
+------------------------+        +-----------------------------+
|  Keyboard Extension    | <----> |      Main App (Whisper)     |
+------------------------+        +-----------------------------+
| UI: Mic Button         |        | Loads whispered-small Q5_1  |
| Audio Capture (PCM)    | ---->  | Mel Spectrogram Generator   |
| App Groups Shared Pipe |        | Streaming Whisper Inference |
| Real-time Text Display | <----  | Token Stream Output         |
+------------------------+        +-----------------------------+
```

Communication Options:

* **App Groups + shared file pipe** (simplest, Apple-approved)
* **XPC** (more complex; not required for v1)

---

# 7. **Audio Capture Pipeline (Extension Side)**

### Steps

1. Keyboard listens for long-press on microphone key.
2. Begins recording with **AVAudioEngine** at:

   * 16 kHz
   * 16-bit linear PCM
   * Mono
3. Buffers audio in ~100–200ms chunks.
4. Writes PCM to App Groups shared pipe.
5. Notifies the main app a new chunk is ready.
6. If app is not open, app is automatically woken via BGTasks or silent activation.
7. Text is streamed back.

---

# 8. **Streaming Inference Pipeline (Main App)**

### Steps

1. Model warmed at launch.
2. When PCM arrives:

   * Convert to mel spectrogram incrementally
   * Push mel frames into Whisper.cpp stream
   * Extract tokens (partial + final)
3. Convert tokens to text with punctuation settings.
4. Stream text back to extension.

### Chunking Strategy

* 200–300ms audio chunks
* Sliding window of ~1.5s
* Reduces latency and memory use

### Latency Targets

* Cold start: < 1.5s
* First token: < 350ms
* Ongoing transcription: 200–800ms delay

---

# 9. **Text Processing & Punctuation Modes**

### Modes

* **Auto punctuation**
* **No punctuation (raw)**
* **Sentence mode**
* **“Smart Correct Last 5 Seconds”** (optional later)

Implementation:
Use Whisper’s built-in token classification; no post-processing ML required.

---

# 10. **Latency Benchmarks (Estimated)**

| Device          | First Token | Streaming Latency |
| --------------- | ----------- | ----------------- |
| iPhone 11 (A13) | ~420ms      | 500–900ms         |
| iPhone 12 (A14) | ~380ms      | 450–750ms         |
| iPhone 13 (A15) | ~300ms      | 350–600ms         |
| iPhone 14 (A16) | ~280ms      | 330–550ms         |
| iPhone 15 (A17) | ~240ms      | 300–500ms         |

---

# 11. **Swift Module Structure**

```
/WhisperBoard
  /App
    AppDelegate.swift
    ModelLoader.swift
    InferenceEngine.swift
    AudioProcessor.swift
    TokenStream.swift
    ClipboardManager.swift
    Settings.swift
    WhisperModel/ (GGUF assets)
  /KeyboardExtension
    KeyboardView.swift
    AudioCapture.swift
    TranscriptionDisplay.swift
    IPCPipe.swift
  /Shared
    AppGroups.swift
    MessageTypes.swift
```

---

# 12. **Data Flow Diagram**

```
Keyboard Extension
   ↓ (PCM chunk)
App Groups Shared Container
   ↓
Main App
   ↓ Whisper Inference
Tokens/Text
   ↑
Keyboard Extension
   ↑ (fill text field)
UI
```

---

# 13. **Security & Privacy Guarantees**

* **All processing is on-device.**
* No servers, no cloud APIs.
* No analytics or logs.
* No file uploads.
* No storage of audio.
* Transcription is ephemeral: only the final text persists.
* Complies with Apple’s keyboard extension privacy rules.

---

# 14. **App Store Compliance Notes**

To avoid rejection:

### What WhisperBoard **must not** do:

* Background listening
* Continuous audio capture
* Logging of keystrokes
* Asking for unnecessary permissions

### What WhisperBoard **can** safely do:

* Request microphone access
* Use App Groups for communication
* Launch app when needed for inference
* Allow transcription-only mode in-app
* Charge $1 as a paid app

No server involvement means **no privacy policy complexity**.

---

# 15. **Fallback Modes**

### 1. Whisper-to-Clipboard

For apps that block custom keyboards from accessing full text fields:

* User presses mic
* Dictates
* WhisperBoard writes transcription to clipboard
* User taps “Paste”

### 2. In-App Dictation Overlay

The main app provides a large mic button.
User dictates here, and text can be:

* Copied to clipboard
* Shared
* Inserted into the keyboard when active

---

# 16. **Testing Strategy**

### Unit Tests

* Audio buffer correctness
* Mel spectrogram math
* Token decoding
* IPC reliability

### Integration Tests

* Keyboard → App communication
* Latency measurements

### Manual QA

* Try dictation in iMessage, Notes, Safari, Gmail
* Stress test rapid start/stop cycles
* Test on low battery mode
* Test poor mic audio (fan noise, wind)

---

# 17. **Future Enhancements**

* On-device punctuation model (optional)
* Tiny-sized model fallback mode
* Model hot-swapping via settings
* Offline language selection UI
* Adaptive VAD
* Audio gain normalization
* More advanced keyboard layouts

