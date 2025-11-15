//
//  WhisperBoard-Bridging-Header.h
//  WhisperBoard
//
//  Bridging header for whisper.cpp C++ integration
//  This header exposes whisper.cpp C/C++ functions to Swift
//
//  Usage:
//  1. Add whisper.cpp source files to Xcode project
//  2. Set this file as "Objective-C Bridging Header" in Build Settings
//  3. Link against Accelerate framework for DSP operations
//

#ifndef WhisperBoard_Bridging_Header_h
#define WhisperBoard_Bridging_Header_h

// Include whisper.cpp header
// NOTE: You need to add whisper.cpp source to your project
// Download from: https://github.com/ggerganov/whisper.cpp
//
// Required files:
// - whisper.h
// - whisper.cpp
// - ggml.h
// - ggml.c
// - ggml-alloc.h
// - ggml-alloc.c
// - ggml-backend.h
// - ggml-backend.c
//
// Uncomment when whisper.cpp is added:
// #import "whisper.h"

// For now, we'll define placeholder types
// Remove these when whisper.cpp is integrated
typedef struct whisper_context whisper_context;
typedef struct whisper_full_params whisper_full_params;

#endif /* WhisperBoard_Bridging_Header_h */
