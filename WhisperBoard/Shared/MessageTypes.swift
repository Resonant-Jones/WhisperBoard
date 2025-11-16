//
//  MessageTypes.swift
//  WhisperBoard
//
//  Defines message types and data structures for IPC between keyboard extension and main app
//  All types are Codable for JSON serialization
//

import Foundation

// MARK: - Control Messages

/// Control signals sent from keyboard extension to main app
enum ControlSignal: String, Codable {
    case start          // Start recording and transcription
    case stop           // Stop recording and finalize transcription
    case cancel         // Cancel current transcription
    case ping           // Check if main app is alive
    case resetModel     // Reset model state (after error)
}

/// Control message wrapper
struct ControlMessage: Codable {
    let signal: ControlSignal
    let timestamp: Date
    let sessionId: String  // Unique session identifier

    init(signal: ControlSignal, sessionId: String = UUID().uuidString) {
        self.signal = signal
        self.timestamp = Date()
        self.sessionId = sessionId
    }
}

// MARK: - Audio Data Messages

/// Audio chunk metadata
struct AudioChunkMetadata: Codable {
    let chunkId: Int
    let sampleRate: Int
    let channels: Int
    let format: AudioFormat
    let duration: TimeInterval
    let timestamp: Date
    let sessionId: String
    let isLastChunk: Bool

    enum AudioFormat: String, Codable {
        case pcm16      // 16-bit PCM
        case float32    // 32-bit float PCM
    }
}

/// Audio chunk message (metadata only, actual PCM data is in separate file)
struct AudioChunkMessage: Codable {
    let metadata: AudioChunkMetadata
    let pcmFileName: String  // Name of PCM file in shared container

    init(metadata: AudioChunkMetadata, pcmFileName: String) {
        self.metadata = metadata
        self.pcmFileName = pcmFileName
    }
}

// MARK: - Transcription Messages

/// Transcription result from main app to keyboard extension
struct TranscriptionResult: Codable {
    let text: String
    let isFinal: Bool           // Is this the final result?
    let confidence: Double?     // Optional confidence score (0-1)
    let timestamp: Date
    let sessionId: String
    let processingTimeMs: Int   // Time taken for inference

    init(text: String, isFinal: Bool, sessionId: String, processingTimeMs: Int, confidence: Double? = nil) {
        self.text = text
        self.isFinal = isFinal
        self.confidence = confidence
        self.timestamp = Date()
        self.sessionId = sessionId
        self.processingTimeMs = processingTimeMs
    }
}

/// Streaming token update (for real-time display)
struct TokenUpdate: Codable {
    let tokens: [String]
    let text: String            // Decoded text so far
    let sessionId: String
    let timestamp: Date

    init(tokens: [String], text: String, sessionId: String) {
        self.tokens = tokens
        self.text = text
        self.sessionId = sessionId
        self.timestamp = Date()
    }
}

// MARK: - Status Messages

/// App status (for keyboard extension to check if app is ready)
struct AppStatus: Codable {
    let isModelLoaded: Bool
    let isProcessing: Bool
    let currentSessionId: String?
    let modelVariant: String
    let memoryUsageMB: Int
    let lastUpdateTime: Date

    init(isModelLoaded: Bool, isProcessing: Bool, currentSessionId: String?, modelVariant: String, memoryUsageMB: Int) {
        self.isModelLoaded = isModelLoaded
        self.isProcessing = isProcessing
        self.currentSessionId = currentSessionId
        self.modelVariant = modelVariant
        self.memoryUsageMB = memoryUsageMB
        self.lastUpdateTime = Date()
    }
}

/// Error message from main app to keyboard extension
struct ErrorMessage: Codable {
    let errorType: ErrorType
    let description: String
    let sessionId: String?
    let timestamp: Date
    let isRecoverable: Bool

    enum ErrorType: String, Codable {
        case modelLoadFailed
        case audioProcessingFailed
        case inferenceFailed
        case memoryPressure
        case invalidAudioFormat
        case timeout
        case unknown
    }

    init(errorType: ErrorType, description: String, sessionId: String?, isRecoverable: Bool) {
        self.errorType = errorType
        self.description = description
        self.sessionId = sessionId
        self.timestamp = Date()
        self.isRecoverable = isRecoverable
    }
}

// MARK: - Settings Messages

/// Shared settings between app and keyboard extension
struct WhisperBoardSettings: Codable {
    var punctuationMode: PunctuationMode
    var language: String?           // nil = auto-detect
    var enableVAD: Bool
    var vadThreshold: Float
    var streamingEnabled: Bool
    var chunkSizeMs: Int           // Audio chunk size in milliseconds
    var maxRecordingDurationSec: Int

    enum PunctuationMode: String, Codable {
        case auto           // Let Whisper add punctuation
        case none           // Raw transcription without punctuation
        case sentence       // Capitalize sentences only
    }

    static var `default`: WhisperBoardSettings {
        WhisperBoardSettings(
            punctuationMode: .auto,
            language: nil,
            enableVAD: false,
            vadThreshold: 0.3,
            streamingEnabled: true,
            chunkSizeMs: 200,
            maxRecordingDurationSec: 60
        )
    }
}

// MARK: - Helper Extensions

extension Encodable {
    /// Encode to JSON Data
    func toJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Encode to JSON String
    func toJSONString() throws -> String {
        let data = try toJSONData()
        guard let string = String(data: data, encoding: .utf8) else {
            throw MessageError.encodingFailed
        }
        return string
    }
}

extension Data {
    /// Decode from JSON Data
    func decode<T: Decodable>(as type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: self)
    }
}

extension String {
    /// Decode from JSON String
    func decode<T: Decodable>(as type: T.Type) throws -> T {
        guard let data = self.data(using: .utf8) else {
            throw MessageError.decodingFailed
        }
        return try data.decode(as: type)
    }
}

// MARK: - Message Errors

enum MessageError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case invalidData
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode message to JSON"
        case .decodingFailed:
            return "Failed to decode message from JSON"
        case .invalidData:
            return "Invalid message data"
        case .validationFailed(let reason):
            return "Validation failed: \(reason)"
        }
    }
}

// MARK: - Input Validation

/// Validation protocol for IPC messages
protocol Validatable {
    func validate() throws
}

extension AudioChunkMetadata: Validatable {
    func validate() throws {
        // Validate chunk ID
        guard chunkId >= 0 else {
            throw MessageError.validationFailed("Invalid chunkId: \(chunkId)")
        }

        // Validate sample rate (must be 16kHz for Whisper)
        guard sampleRate == 16000 else {
            throw MessageError.validationFailed("Invalid sample rate: \(sampleRate). Expected 16000 Hz")
        }

        // Validate channels (must be mono)
        guard channels == 1 else {
            throw MessageError.validationFailed("Invalid channels: \(channels). Expected 1 (mono)")
        }

        // Validate duration (0-10 seconds per chunk)
        guard duration > 0 && duration <= 10.0 else {
            throw MessageError.validationFailed("Invalid duration: \(duration). Must be 0-10 seconds")
        }

        // Validate session ID format (UUID)
        guard !sessionId.isEmpty && sessionId.count <= 100 else {
            throw MessageError.validationFailed("Invalid sessionId format")
        }

        // Validate timestamp (not too far in past/future)
        let now = Date()
        let timeDiff = abs(timestamp.timeIntervalSince(now))
        guard timeDiff < 300 else {  // 5 minutes max time drift
            throw MessageError.validationFailed("Invalid timestamp: \(timeDiff)s drift")
        }
    }
}

extension TranscriptionResult: Validatable {
    func validate() throws {
        // Validate text length (max 10,000 characters)
        guard text.count <= 10_000 else {
            throw MessageError.validationFailed("Text too long: \(text.count) characters")
        }

        // Validate confidence score if present
        if let confidence = confidence {
            guard confidence >= 0.0 && confidence <= 1.0 else {
                throw MessageError.validationFailed("Invalid confidence: \(confidence)")
            }
        }

        // Validate processing time (max 60 seconds)
        guard processingTimeMs >= 0 && processingTimeMs <= 60_000 else {
            throw MessageError.validationFailed("Invalid processing time: \(processingTimeMs)ms")
        }

        // Validate session ID
        guard !sessionId.isEmpty && sessionId.count <= 100 else {
            throw MessageError.validationFailed("Invalid sessionId")
        }
    }
}

extension WhisperBoardSettings: Validatable {
    func validate() throws {
        // Validate VAD threshold (0-1)
        guard vadThreshold >= 0.0 && vadThreshold <= 1.0 else {
            throw MessageError.validationFailed("Invalid VAD threshold: \(vadThreshold)")
        }

        // Validate chunk size (50-1000ms)
        guard chunkSizeMs >= 50 && chunkSizeMs <= 1000 else {
            throw MessageError.validationFailed("Invalid chunk size: \(chunkSizeMs)ms")
        }

        // Validate max recording duration (1-300 seconds)
        guard maxRecordingDurationSec >= 1 && maxRecordingDurationSec <= 300 else {
            throw MessageError.validationFailed("Invalid max duration: \(maxRecordingDurationSec)s")
        }

        // Validate language code if set
        if let language = language {
            guard language.count == 2 || language.isEmpty else {
                throw MessageError.validationFailed("Invalid language code: \(language)")
            }
        }
    }
}

/// Validate audio data size
func validateAudioDataSize(_ data: Data, metadata: AudioChunkMetadata) throws {
    // Calculate expected size
    let expectedSamples = Int(metadata.duration * Double(metadata.sampleRate))
    let bytesPerSample: Int

    switch metadata.format {
    case .pcm16:
        bytesPerSample = 2  // 16-bit = 2 bytes
    case .float32:
        bytesPerSample = 4  // 32-bit = 4 bytes
    }

    let expectedSize = expectedSamples * bytesPerSample * metadata.channels
    let actualSize = data.count

    // Allow 10% tolerance for rounding
    let tolerance = Int(Double(expectedSize) * 0.1)
    guard abs(actualSize - expectedSize) <= tolerance else {
        throw MessageError.validationFailed(
            "Audio data size mismatch. Expected ~\(expectedSize) bytes, got \(actualSize) bytes"
        )
    }

    // Maximum 10MB per chunk (safety limit)
    guard actualSize <= 10_000_000 else {
        throw MessageError.validationFailed("Audio data too large: \(actualSize) bytes")
    }
}

