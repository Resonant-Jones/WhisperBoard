//
//  WhisperBoardConfig.swift
//  WhisperBoard
//
//  Centralized configuration for all constants and magic numbers
//

import Foundation
import AVFoundation
import CoreGraphics

/// Centralized configuration for WhisperBoard
struct WhisperBoardConfig {

    // MARK: - Audio Configuration

    struct Audio {
        /// Sample rate for audio capture (Whisper requires 16kHz)
        static let sampleRate: Double = 16000.0

        /// Number of audio channels (mono)
        static let channelCount: AVAudioChannelCount = 1

        /// Audio chunk size in milliseconds
        static let chunkSizeMs: Int = 200

        /// Maximum recording duration in seconds
        static let maxRecordingDurationSeconds: Int = 60

        /// Audio buffer size (in samples)
        static let bufferSize: Int = 3200  // 200ms at 16kHz

        /// Maximum audio data size per chunk (10MB safety limit)
        static let maxChunkSizeBytes: Int = 10_000_000
    }

    // MARK: - IPC Configuration

    struct IPC {
        /// Polling interval for checking new audio chunks (50ms)
        static let pollingIntervalSeconds: TimeInterval = 0.05

        /// Polling interval for transcription updates in keyboard (100ms)
        static let keyboardPollingIntervalSeconds: TimeInterval = 0.1

        /// Maximum chunk buffer size before dropping oldest
        static let maxChunkBufferSize = 10

        /// File cleanup age for old transcriptions (60 seconds)
        static let fileCleanupAgeSeconds: TimeInterval = 60

        /// Maximum time drift allowed for timestamps (5 minutes)
        static let maxTimestampDriftSeconds: TimeInterval = 300

        /// Status update interval (1 second)
        static let statusUpdateIntervalSeconds: TimeInterval = 1.0
    }

    // MARK: - UI Configuration

    struct UI {
        /// Keyboard extension height (compact)
        static let keyboardHeightCompact: CGFloat = 180

        /// Keyboard extension height (iPad)
        static let keyboardHeightPad: CGFloat = 220

        /// Transcription timeout duration (10 seconds)
        static let transcriptionTimeoutSeconds: TimeInterval = 10.0

        /// Mic button size
        static let micButtonSize: CGFloat = 80

        /// Mic button corner radius
        static let micButtonCornerRadius: CGFloat = 40

        /// Transcription label fadeout delay (1.5 seconds)
        static let transcriptionFadeoutDelay: TimeInterval = 1.5

        /// Error message display duration (3 seconds)
        static let errorMessageDuration: TimeInterval = 3.0
    }

    // MARK: - Inference Configuration

    struct Inference {
        /// Number of threads for Whisper inference
        static let numThreads: Int = 4

        /// Default language code (English)
        static let defaultLanguage = "en"

        /// Maximum text length for transcription results
        static let maxTextLength = 10_000

        /// Maximum processing time allowed (60 seconds)
        static let maxProcessingTimeMs = 60_000
    }

    // MARK: - Memory Configuration

    struct Memory {
        /// Expected model memory for small-Q5_1 (MB)
        static let expectedModelMemoryMB = 150

        /// Expected peak memory usage (MB)
        static let expectedPeakMemoryMB = 380

        /// Memory warning threshold (MB)
        static let memoryWarningThresholdMB = 450
    }

    // MARK: - File Management

    struct Files {
        /// Log file rotation size (5MB)
        static let logRotationSizeBytes: Int64 = 5_000_000

        /// Log archive retention period (7 days)
        static let logRetentionDays = 7

        /// Cleanup cutoff for orphaned files (1 hour)
        static let orphanedFileCutoffSeconds: TimeInterval = 3600

        /// Periodic cleanup interval for token stream (60 seconds)
        static let tokenCleanupIntervalSeconds: TimeInterval = 60

        /// Token file cleanup age (5 minutes)
        static let tokenCleanupAgeSeconds: TimeInterval = 300
    }

    // MARK: - Validation Limits

    struct Validation {
        /// Minimum chunk size (ms)
        static let minChunkSizeMs = 50

        /// Maximum chunk size (ms)
        static let maxChunkSizeMs = 1000

        /// Minimum recording duration (seconds)
        static let minRecordingDurationSeconds = 1

        /// Maximum recording duration (seconds)
        static let maxRecordingDurationSeconds = 300

        /// Maximum session ID length
        static let maxSessionIdLength = 100

        /// Audio data size tolerance (10%)
        static let audioSizeTolerancePercent = 0.1
    }

    // MARK: - Network/Retry Configuration

    struct Retry {
        /// Maximum retry attempts for transient failures
        static let maxRetries = 3

        /// Initial retry delay (seconds)
        static let initialRetryDelaySeconds: TimeInterval = 0.5

        /// Retry backoff multiplier
        static let retryBackoffMultiplier: Double = 2.0
    }
}
