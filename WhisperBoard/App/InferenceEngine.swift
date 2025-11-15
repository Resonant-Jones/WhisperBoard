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

                // Generate mel spectrogram
                let melSpectrogram = try self.generateMelSpectrogram(audioSamples, sampleRate: metadata.sampleRate)

                // Run Whisper inference
                let tokens = try self.runWhisperInference(melSpectrogram)

                // Decode tokens to text
                let text = try self.decodeTokens(tokens)

                // Calculate processing time
                let processingTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)

                // Send streaming update if enabled
                if self.settings.streamingEnabled {
                    let tokenUpdate = TokenUpdate(
                        tokens: tokens.map { String($0) },
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

                print("[InferenceEngine] Processed chunk \(metadata.chunkId) in \(processingTimeMs)ms")

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

    // MARK: - Mel Spectrogram

    /// Generate mel spectrogram from audio samples
    /// NOTE: This is a simplified placeholder. Production version should use whisper.cpp's mel generation
    private func generateMelSpectrogram(_ samples: [Float], sampleRate: Int) throws -> [[Float]] {
        // Whisper expects 80 mel bins and 16kHz sample rate
        let nMels = 80
        let nFFT = 400  // 25ms window at 16kHz
        let hopLength = 160  // 10ms hop

        // Calculate number of frames
        let nFrames = (samples.count - nFFT) / hopLength + 1

        // Placeholder: In production, this would call whisper.cpp's log_mel_spectrogram
        var melSpectrogram = [[Float]](repeating: [Float](repeating: 0, count: nMels), count: nFrames)

        // NOTE: Actual implementation requires whisper.cpp integration:
        // whisper_log_mel_spectrogram(samples, sampleRate, nFFT, hopLength, nMels, &melSpectrogram)

        return melSpectrogram
    }

    // MARK: - Whisper Inference

    /// Run Whisper inference on mel spectrogram
    /// NOTE: Placeholder - requires whisper.cpp integration
    private func runWhisperInference(_ melSpectrogram: [[Float]]) throws -> [Int] {
        guard let context = modelLoader.getContext() else {
            throw InferenceError.modelNotLoaded
        }

        // Placeholder for whisper.cpp inference
        // In production:
        // var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        // params.language = settings.language ?? "en"
        // params.n_threads = 4
        // params.speed_up = true
        //
        // whisper_full(context, params, melSpectrogram.flatMap { $0 }, melSpectrogram.count)
        //
        // var tokens = [Int]()
        // let n_segments = whisper_full_n_segments(context)
        // for i in 0..<n_segments {
        //     let n_tokens = whisper_full_n_tokens(context, i)
        //     for j in 0..<n_tokens {
        //         let token = whisper_full_get_token_id(context, i, j)
        //         tokens.append(Int(token))
        //     }
        // }

        // Placeholder return
        return []
    }

    /// Decode tokens to text
    /// NOTE: Placeholder - requires whisper.cpp integration
    private func decodeTokens(_ tokens: [Int]) throws -> String {
        guard let context = modelLoader.getContext() else {
            throw InferenceError.modelNotLoaded
        }

        // Placeholder for whisper.cpp token decoding
        // In production:
        // var text = ""
        // for token in tokens {
        //     if let tokenText = whisper_token_to_str(context, Int32(token)) {
        //         text += String(cString: tokenText)
        //     }
        // }
        //
        // Apply punctuation mode
        // text = applyPunctuationMode(text, mode: settings.punctuationMode)

        // Placeholder return
        return ""
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
