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

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode message to JSON"
        case .decodingFailed:
            return "Failed to decode message from JSON"
        case .invalidData:
            return "Invalid message data"
        }
    }
}
