//
//  InferenceEngine.swift
//  WhisperBoard
//
//  Core inference engine for Whisper model
//  Handles streaming audio → mel → tokens → text pipeline
//

import Foundation
import Accelerate

/// Inference engine for running Whisper transcription
class InferenceEngine {

    // MARK: - Properties

    private let modelLoader: ModelLoader
    private let inferenceQueue = DispatchQueue(label: "com.whisperboard.inference", qos: .userInitiated)
    private var currentSessionId: String?
    private var isProcessing = false

    /// Callback for streaming token updates
    var onTokenUpdate: ((TokenUpdate) -> Void)?

    /// Callback for final transcription result
    var onTranscriptionComplete: ((TranscriptionResult) -> Void)?

    /// Callback for errors
    var onError: ((ErrorMessage) -> Void)?

    /// Settings
    private var settings: WhisperBoardSettings

    // MARK: - Initialization

    init(modelLoader: ModelLoader = .shared, settings: WhisperBoardSettings = .default) {
        self.modelLoader = modelLoader
        self.settings = settings
    }

    // MARK: - Transcription

    /// Start transcription for a new session
    /// - Parameter sessionId: Unique session identifier
    func startSession(sessionId: String) {
        inferenceQueue.async { [weak self] in
            guard let self = self else { return }

            if self.isProcessing {
                print("[InferenceEngine] Warning: Starting new session while processing")
                self.cancelSession()
            }

            self.currentSessionId = sessionId
            self.isProcessing = true

            print("[InferenceEngine] Started session: \(sessionId)")
        }
    }

    /// Process audio chunk and generate transcription
    /// - Parameters:
    ///   - audioData: PCM audio data (16-bit or float32)
    ///   - metadata: Audio chunk metadata
    func processAudioChunk(_ audioData: Data, metadata: AudioChunkMetadata) {
        inferenceQueue.async { [weak self] in
            guard let self = self else { return }

            guard self.isProcessing,
                  let sessionId = self.currentSessionId,
                  sessionId == metadata.sessionId else {
                print("[InferenceEngine] Ignoring chunk for inactive session")
                return
            }

            let startTime = Date()

            do {
                // Convert audio data to Float array
                let audioSamples = try self.convertToFloatSamples(audioData, format: metadata.format)

                // Run Whisper inference (whisper.cpp handles mel spectrogram internally)
                let text = try self.runWhisperInference(audioSamples)

                // Extract tokens for streaming if needed
                var tokens: [String] = []
                if self.settings.streamingEnabled, let context = self.modelLoader.getContext() {
                    tokens = self.extractTokens(from: context)
                }

                // Calculate processing time
                let processingTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)

                // Send streaming update if enabled
                if self.settings.streamingEnabled && !tokens.isEmpty {
                    let tokenUpdate = TokenUpdate(
                        tokens: tokens,
                        text: text,
                        sessionId: sessionId
                    )
                    self.onTokenUpdate?(tokenUpdate)
                }

                // If this is the last chunk, send final result
                if metadata.isLastChunk {
                    let result = TranscriptionResult(
                        text: text,
                        isFinal: true,
                        sessionId: sessionId,
                        processingTimeMs: processingTimeMs,
                        confidence: nil
                    )
                    self.onTranscriptionComplete?(result)
                    self.isProcessing = false
                    self.currentSessionId = nil
                }

                print("[InferenceEngine] Processed chunk \(metadata.chunkId) in \(processingTimeMs)ms: \"\(text)\"")

            } catch {
                let errorMsg = ErrorMessage(
                    errorType: .inferenceFailed,
                    description: error.localizedDescription,
                    sessionId: sessionId,
                    isRecoverable: true
                )
                self.onError?(errorMsg)
                print("[InferenceEngine] Error processing chunk: \(error)")
            }
        }
    }

    /// Cancel the current transcription session
    func cancelSession() {
        inferenceQueue.async { [weak self] in
            guard let self = self else { return }

            if let sessionId = self.currentSessionId {
                print("[InferenceEngine] Cancelled session: \(sessionId)")
            }

            self.isProcessing = false
            self.currentSessionId = nil
        }
    }

    /// Update settings
    func updateSettings(_ newSettings: WhisperBoardSettings) {
        inferenceQueue.async { [weak self] in
            self?.settings = newSettings
            print("[InferenceEngine] Settings updated")
        }
    }

    // MARK: - Audio Processing

    /// Convert audio data to Float samples
    private func convertToFloatSamples(_ data: Data, format: AudioChunkMetadata.AudioFormat) throws -> [Float] {
        switch format {
        case .pcm16:
            return try convertPCM16ToFloat(data)
        case .float32:
            return try convertDataToFloatArray(data)
        }
    }

    /// Convert 16-bit PCM to Float array [-1.0, 1.0]
    private func convertPCM16ToFloat(_ data: Data) throws -> [Float] {
        let sampleCount = data.count / 2
        var floatSamples = [Float](repeating: 0, count: sampleCount)

        data.withUnsafeBytes { rawBuffer in
            guard let int16Buffer = rawBuffer.baseAddress?.assumingMemoryBound(to: Int16.self) else {
                return
            }

            for i in 0..<sampleCount {
                floatSamples[i] = Float(int16Buffer[i]) / 32768.0
            }
        }

        return floatSamples
    }

    /// Convert Data to Float array
    private func convertDataToFloatArray(_ data: Data) throws -> [Float] {
        let sampleCount = data.count / 4
        var floatSamples = [Float](repeating: 0, count: sampleCount)

        data.withUnsafeBytes { rawBuffer in
            guard let floatBuffer = rawBuffer.baseAddress?.assumingMemoryBound(to: Float.self) else {
                return
            }

            for i in 0..<sampleCount {
                floatSamples[i] = floatBuffer[i]
            }
        }

        return floatSamples
    }

    // MARK: - Whisper Inference

    /// Run Whisper inference directly on audio samples
    /// whisper.cpp handles mel spectrogram generation internally
    private func runWhisperInference(_ samples: [Float]) throws -> String {
        guard let context = modelLoader.getContext() else {
            throw InferenceError.modelNotLoaded
        }

        // Setup inference parameters
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = 4
        params.translate = false
        params.single_segment = false
        params.print_progress = false
        params.print_special = false
        params.print_realtime = false
        params.print_timestamps = false
        params.token_timestamps = settings.streamingEnabled
        params.speed_up = true  // Enable speed optimization
        params.suppress_blank = true
        params.suppress_non_speech_tokens = true

        // Set language (nil = auto-detect)
        if let language = settings.language {
            params.language = language.withCString { strdup($0) }
            params.detect_language = false
        } else {
            params.language = "en".withCString { strdup($0) }  // Default to English
            params.detect_language = false
        }

        // Run inference
        var samplesCopy = samples  // Make mutable copy
        let result = whisper_full(context, params, &samplesCopy, Int32(samples.count))

        // Free allocated language string
        if let langPtr = params.language {
            free(UnsafeMutableRawPointer(mutating: langPtr))
        }

        if result != 0 {
            throw InferenceError.inferenceFailed
        }

        // Extract transcription text from all segments
        var fullText = ""
        let nSegments = whisper_full_n_segments(context)

        for i in 0..<nSegments {
            if let segmentText = whisper_full_get_segment_text(context, Int32(i)) {
                let text = String(cString: segmentText)
                fullText += text
            }
        }

        // Apply punctuation mode if needed
        fullText = applyPunctuationMode(fullText, mode: settings.punctuationMode)

        return fullText.trimmingCharacters(in: .whitespaces)
    }

    /// Extract tokens from whisper context (for streaming)
    private func extractTokens(from context: UnsafeMutablePointer<whisper_context>) -> [String] {
        var tokens: [String] = []

        let nSegments = whisper_full_n_segments(context)
        for i in 0..<nSegments {
            let nTokens = whisper_full_n_tokens(context, Int32(i))
            for j in 0..<nTokens {
                if let tokenText = whisper_full_get_token_text(context, Int32(i), Int32(j)) {
                    tokens.append(String(cString: tokenText))
                }
            }
        }

        return tokens
    }

    /// Apply punctuation mode to text
    private func applyPunctuationMode(_ text: String, mode: WhisperBoardSettings.PunctuationMode) -> String {
        switch mode {
        case .auto:
            return text  // Whisper handles punctuation
        case .none:
            return removePunctuation(text)
        case .sentence:
            return capitalizeSentences(removePunctuation(text))
        }
    }

    private func removePunctuation(_ text: String) -> String {
        return text.components(separatedBy: CharacterSet.punctuationCharacters).joined(separator: " ")
    }

    private func capitalizeSentences(_ text: String) -> String {
        return text.capitalized
    }

    // MARK: - Status

    /// Get current processing status
    func getStatus() -> AppStatus {
        return inferenceQueue.sync {
            AppStatus(
                isModelLoaded: modelLoader.isLoaded,
                isProcessing: isProcessing,
                currentSessionId: currentSessionId,
                modelVariant: "small-q5_1",
                memoryUsageMB: modelLoader.estimatedMemoryUsageMB
            )
        }
    }
}

// MARK: - Errors

enum InferenceError: LocalizedError {
    case modelNotLoaded
    case invalidAudioFormat
    case melGenerationFailed
    case inferenceFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Whisper model not loaded"
        case .invalidAudioFormat:
            return "Invalid audio format"
        case .melGenerationFailed:
            return "Failed to generate mel spectrogram"
        case .inferenceFailed:
            return "Whisper inference failed"
        case .decodingFailed:
            return "Failed to decode tokens to text"
        }
    }
}
