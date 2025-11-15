# Whisper.cpp Integration Guide

This document explains how to integrate **whisper.cpp** into the WhisperBoard iOS project.

## Overview

WhisperBoard uses [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for on-device speech-to-text transcription. This guide will help you add whisper.cpp to your Xcode project.

---

## Step 1: Download whisper.cpp

```bash
# Clone whisper.cpp repository
git clone https://github.com/ggerganov/whisper.cpp.git

# Or download as ZIP from GitHub
```

---

## Step 2: Add Source Files to Xcode

Add the following files from `whisper.cpp` to your Xcode project:

### Core Files (Required)
- `whisper.h`
- `whisper.cpp`
- `ggml.h`
- `ggml.c`
- `ggml-alloc.h`
- `ggml-alloc.c`
- `ggml-backend.h`
- `ggml-backend.c`
- `ggml-impl.h`
- `ggml-quants.h`
- `ggml-quants.c`

### Metal Support (Recommended for iOS)
- `ggml-metal.h`
- `ggml-metal.m`
- `ggml-metal.metal` (shader file)

**Steps:**
1. Drag these files into your Xcode project under `WhisperBoard/Whisper/`
2. When prompted, ensure "Copy items if needed" is checked
3. Add to both "WhisperBoard" target (not the keyboard extension)

---

## Step 3: Configure Build Settings

### 1. Set Bridging Header

In Xcode Build Settings for **WhisperBoard** target:
- Search for "Objective-C Bridging Header"
- Set to: `WhisperBoard/Whisper/WhisperBoard-Bridging-Header.h`

### 2. Enable C++17

- Search for "C++ Language Dialect"
- Set to: `GNU++17` or `C++17`

### 3. Add Compiler Flags

In "Other C Flags" and "Other C++ Flags", add:
```
-DGGML_USE_ACCELERATE
-DGGML_USE_METAL
-O3
-ffast-math
```

### 4. Link Frameworks

In "Link Binary With Libraries", add:
- `Accelerate.framework` (for DSP)
- `Metal.framework` (for GPU acceleration)
- `MetalKit.framework`
- `CoreML.framework` (optional)

---

## Step 4: Download Whisper Model

### Option A: Download Pre-quantized Models

```bash
# Download whisper-small Q5_1 (recommended)
curl -O https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin

# Or download other variants:
# - ggml-small-q4_0.bin (smaller, faster)
# - ggml-small-q8_0.bin (larger, more accurate)
# - ggml-tiny-q5_1.bin (fallback for old devices)
```

### Option B: Convert Models Yourself

```bash
# Install dependencies
pip install -r whisper.cpp/requirements.txt

# Download base model
python whisper.cpp/models/download-ggml-model.py small

# Quantize to Q5_1
./whisper.cpp/quantize models/ggml-small.bin models/ggml-small-q5_1.bin q5_1
```

### Add Model to Xcode Project

1. Add `ggml-small-q5_1.bin` to `WhisperBoard/Resources/`
2. In Xcode, select the model file
3. In File Inspector, check "WhisperBoard" target membership
4. **Important:** Model should NOT be added to keyboard extension target (too large)

---

## Step 5: Update ModelLoader.swift

Uncomment the whisper.cpp integration code in `ModelLoader.swift`:

```swift
// Replace placeholder with actual whisper.cpp calls:
import Foundation

// After bridging header is set up, these types will be available:
// - whisper_context
// - whisper_full_params
// - whisper_init_from_file()
// - whisper_full()
// - whisper_free()

// Update loadModel() function:
func loadModel(config: ModelConfig? = nil) throws {
    // ...

    // Initialize Whisper context (uncomment after integration)
    whisperContext = whisper_init_from_file(modelPath)

    guard whisperContext != nil else {
        throw ModelLoaderError.modelLoadFailed("Failed to initialize Whisper context")
    }

    // ...
}
```

---

## Step 6: Update InferenceEngine.swift

Implement actual Whisper inference:

```swift
private func runWhisperInference(_ melSpectrogram: [[Float]]) throws -> [Int] {
    guard let context = modelLoader.getContext() else {
        throw InferenceError.modelNotLoaded
    }

    // Configure inference parameters
    var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
    params.language = settings.language ?? "en"
    params.n_threads = 4
    params.speed_up = true
    params.single_segment = false
    params.print_realtime = false
    params.print_progress = false

    // Flatten mel spectrogram
    let flatMel = melSpectrogram.flatMap { $0 }

    // Run inference
    let result = whisper_full(context, params, flatMel, Int32(melSpectrogram.count))

    guard result == 0 else {
        throw InferenceError.inferenceFailed
    }

    // Extract tokens
    var tokens = [Int]()
    let n_segments = whisper_full_n_segments(context)

    for i in 0..<n_segments {
        let n_tokens = whisper_full_n_tokens(context, i)
        for j in 0..<n_tokens {
            let token = whisper_full_get_token_id(context, i, j)
            tokens.append(Int(token))
        }
    }

    return tokens
}
```

---

## Step 7: Test Integration

1. Build the project (⌘B)
2. Fix any compilation errors
3. Run on a physical device (not simulator - Metal required)
4. Check console for:
   - `[ModelLoader] ✓ Model loaded successfully`
   - Memory usage should be ~150-380 MB for small-Q5_1

---

## Troubleshooting

### Build Errors

**Error: "whisper.h file not found"**
- Check bridging header path in Build Settings
- Ensure whisper.h is in the project

**Error: "Undefined symbols for architecture arm64"**
- Ensure Accelerate.framework is linked
- Check C++ Language Dialect is set to C++17

**Error: "Use of undeclared identifier 'whisper_context'"**
- Uncomment `#import "whisper.h"` in bridging header
- Clean build folder (⇧⌘K)

### Runtime Errors

**Crash on model load:**
- Check model file is bundled with app
- Verify model file is not corrupted
- Check available device memory

**High memory usage:**
- Use smaller quantization (Q4_0 instead of Q5_1)
- Consider using tiny model for older devices

---

## Memory Optimization

To reduce peak memory usage:

1. **Use Q4_0 quantization** (120 MB vs 150 MB)
2. **Enable Metal acceleration** (offloads to GPU)
3. **Stream audio in smaller chunks** (reduce buffer size)
4. **Warm model on app launch** (prevents cold-start allocation spike)

---

## Performance Benchmarks

Expected latency on iPhone (small-Q5_1):

| Device | First Token | Streaming |
|--------|-------------|-----------|
| iPhone 11 (A13) | ~420ms | 500-900ms |
| iPhone 12 (A14) | ~380ms | 450-750ms |
| iPhone 13 (A15) | ~300ms | 350-600ms |
| iPhone 14 (A16) | ~280ms | 330-550ms |
| iPhone 15 (A17) | ~240ms | 300-500ms |

---

## Additional Resources

- [whisper.cpp GitHub](https://github.com/ggerganov/whisper.cpp)
- [whisper.cpp iOS Examples](https://github.com/ggerganov/whisper.cpp/tree/master/examples/whisper.objc)
- [GGML Documentation](https://github.com/ggerganov/ggml)
- [Whisper Model Cards](https://huggingface.co/ggerganov/whisper.cpp)

---

## Next Steps

After integration is complete:

1. Test on multiple devices (iPhone 11, 12, 13, etc.)
2. Benchmark latency and memory usage
3. Optimize chunk size for best streaming performance
4. Add error recovery for memory pressure
5. Implement model hot-swapping for different quantizations

---

**Questions?** Check the whisper.cpp issues or discussions on GitHub.
