//
//  AudioProcessor.swift
//  WhisperBoard
//
//  Handles audio data from keyboard extension and coordinates with InferenceEngine
//  Monitors App Groups shared container for incoming audio chunks
//

import Foundation
import Combine

/// Processes audio chunks from keyboard extension and feeds them to inference engine
class AudioProcessor {

    // MARK: - Properties

    private let inferenceEngine: InferenceEngine
    private var audioMonitorTimer: Timer?
    private var lastProcessedChunkId = -1
    private var currentSessionId: String?
    private let processingQueue = DispatchQueue(label: "com.whisperboard.audioprocessor", qos: .userInitiated)

    /// Chunk sequencing buffer for out-of-order chunks
    private var chunkBuffer: [Int: (data: Data, metadata: AudioChunkMetadata, url: URL, pcmURL: URL)] = [:]
    private let maxBufferSize = 10  // Maximum chunks to buffer before dropping

    /// Polling interval for checking new audio chunks (in seconds)
    private let pollingInterval: TimeInterval = 0.05  // 50ms for low latency

    // MARK: - Initialization

    init(inferenceEngine: InferenceEngine = InferenceEngine()) {
        self.inferenceEngine = inferenceEngine
    }

    // MARK: - Audio Monitoring

    /// Start monitoring for audio chunks from keyboard extension
    func startMonitoring() {
        stopMonitoring()  // Stop any existing monitoring

        print("[AudioProcessor] Started monitoring for audio chunks")

        // Create timer for polling App Groups container
        audioMonitorTimer = Timer.scheduledTimer(
            withTimeInterval: pollingInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkForNewAudioChunks()
        }

        // Also monitor control signals
        monitorControlSignals()
    }

    /// Stop monitoring for audio chunks
    func stopMonitoring() {
        audioMonitorTimer?.invalidate()
        audioMonitorTimer = nil

        print("[AudioProcessor] Stopped monitoring")
    }

    // MARK: - Control Signal Monitoring

    /// Monitor control signals from keyboard extension
    private func monitorControlSignals() {
        processingQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                // Check for control signal file
                if AppGroups.fileExists(AppGroups.Files.controlSignal, in: AppGroups.Paths.control) {
                    let data = try AppGroups.readData(
                        from: AppGroups.Files.controlSignal,
                        in: AppGroups.Paths.control
                    )

                    let controlMsg = try data.decode(as: ControlMessage.self)

                    // Handle control signal
                    self.handleControlSignal(controlMsg)

                    // Delete control signal file after processing
                    try AppGroups.deleteFile(AppGroups.Files.controlSignal, in: AppGroups.Paths.control)
                }
            } catch {
                // Silently ignore errors (file might not exist yet)
            }
        }
    }

    /// Handle incoming control signal
    private func handleControlSignal(_ message: ControlMessage) {
        print("[AudioProcessor] Received control signal: \(message.signal)")

        switch message.signal {
        case .start:
            currentSessionId = message.sessionId
            lastProcessedChunkId = -1
            chunkBuffer.removeAll()  // Clear buffer for new session
            inferenceEngine.startSession(sessionId: message.sessionId)

        case .stop:
            // Final chunk will trigger completion in processAudioChunk
            break

        case .cancel:
            inferenceEngine.cancelSession()
            cleanupSession(currentSessionId)
            currentSessionId = nil
            lastProcessedChunkId = -1
            chunkBuffer.removeAll()

        case .ping:
            // Respond with status
            updateAppStatus()

        case .resetModel:
            // Reset model state
            inferenceEngine.cancelSession()
            cleanupSession(currentSessionId)
            currentSessionId = nil
            lastProcessedChunkId = -1
            chunkBuffer.removeAll()
        }
    }

    // MARK: - Audio Chunk Processing

    /// Check for new audio chunks in App Groups container
    private func checkForNewAudioChunks() {
        processingQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                // Look for audio chunk metadata files
                guard let audioBuffersPath = AppGroups.Paths.audioBuffers else { return }

                let fileManager = FileManager.default
                let files = try fileManager.contentsOfDirectory(
                    at: audioBuffersPath,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )

                // Find metadata files (JSON)
                let metadataFiles = files
                    .filter { $0.pathExtension == "json" }
                    .sorted { url1, url2 in
                        let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                        let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                        return date1 < date2
                    }

                // Process each metadata file
                for metadataFile in metadataFiles {
                    try self.processAudioChunkFile(metadataFile)
                }

            } catch {
                // Silently ignore errors during polling
            }
        }
    }

    /// Process a single audio chunk metadata file
    private func processAudioChunkFile(_ metadataURL: URL) throws {
        // Read metadata
        let metadataData = try Data(contentsOf: metadataURL)
        let chunkMessage = try metadataData.decode(as: AudioChunkMessage.self)
        let metadata = chunkMessage.metadata

        // Validate metadata
        do {
            try metadata.validate()
        } catch {
            Logger.error(error, context: "Invalid metadata for chunk \(metadata.chunkId)", category: "AudioProcessor")
            throw error
        }

        // Skip if already processed
        guard metadata.chunkId > lastProcessedChunkId else {
            // Already processed, clean up
            try? FileManager.default.removeItem(at: metadataURL)
            if let audioBuffersPath = AppGroups.Paths.audioBuffers {
                let pcmURL = audioBuffersPath.appendingPathComponent(chunkMessage.pcmFileName)
                try? FileManager.default.removeItem(at: pcmURL)
            }
            return
        }

        // Skip if wrong session
        guard let currentSession = currentSessionId,
              currentSession == metadata.sessionId else {
            // Delete old session files
            try? FileManager.default.removeItem(at: metadataURL)
            if let audioBuffersPath = AppGroups.Paths.audioBuffers {
                let pcmURL = audioBuffersPath.appendingPathComponent(chunkMessage.pcmFileName)
                try? FileManager.default.removeItem(at: pcmURL)
            }
            return
        }

        // Read PCM audio data
        guard let audioBuffersPath = AppGroups.Paths.audioBuffers else {
            throw AudioProcessorError.invalidPath
        }

        let pcmURL = audioBuffersPath.appendingPathComponent(chunkMessage.pcmFileName)
        let audioData = try Data(contentsOf: pcmURL)

        // Validate audio data size
        do {
            try validateAudioDataSize(audioData, metadata: metadata)
        } catch {
            Logger.error(error, context: "Invalid audio data for chunk \(metadata.chunkId)", category: "AudioProcessor")
            throw error
        }

        // Check if this is the next expected chunk
        if metadata.chunkId == lastProcessedChunkId + 1 {
            // Process immediately - this is the next in sequence
            processChunk(audioData, metadata: metadata)
            lastProcessedChunkId = metadata.chunkId

            // Clean up files
            try? FileManager.default.removeItem(at: metadataURL)
            try? FileManager.default.removeItem(at: pcmURL)

            // Process any buffered chunks that are now in sequence
            processBufferedChunks()

        } else {
            // Out of order - buffer it
            print("[AudioProcessor] ⚠️ Chunk \(metadata.chunkId) arrived out of order (expected \(lastProcessedChunkId + 1)), buffering")

            // Check buffer size limit
            if chunkBuffer.count >= maxBufferSize {
                print("[AudioProcessor] ⚠️ Chunk buffer overflow (\(chunkBuffer.count) chunks), dropping oldest")
                // Find and remove oldest chunk
                if let oldestId = chunkBuffer.keys.min() {
                    if let oldChunk = chunkBuffer.removeValue(forKey: oldestId) {
                        try? FileManager.default.removeItem(at: oldChunk.url)
                        try? FileManager.default.removeItem(at: oldChunk.pcmURL)
                    }
                }
            }

            // Buffer this chunk
            chunkBuffer[metadata.chunkId] = (audioData, metadata, metadataURL, pcmURL)
        }
    }

    /// Process a chunk and send to inference engine
    private func processChunk(_ audioData: Data, metadata: AudioChunkMetadata) {
        print("[AudioProcessor] Processing chunk \(metadata.chunkId), \(audioData.count) bytes")
        inferenceEngine.processAudioChunk(audioData, metadata: metadata)
    }

    /// Process any buffered chunks that are now in sequence
    private func processBufferedChunks() {
        var nextChunkId = lastProcessedChunkId + 1

        // Keep processing chunks as long as we have the next one in sequence
        while let bufferedChunk = chunkBuffer.removeValue(forKey: nextChunkId) {
            print("[AudioProcessor] Processing buffered chunk \(nextChunkId)")

            processChunk(bufferedChunk.data, metadata: bufferedChunk.metadata)
            lastProcessedChunkId = nextChunkId

            // Clean up files
            try? FileManager.default.removeItem(at: bufferedChunk.url)
            try? FileManager.default.removeItem(at: bufferedChunk.pcmURL)

            nextChunkId += 1
        }
    }

    // MARK: - Status Updates

    /// Update app status in shared container
    private func updateAppStatus() {
        processingQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                let status = self.inferenceEngine.getStatus()
                let statusData = try status.toJSONData()

                try AppGroups.writeData(
                    statusData,
                    to: AppGroups.Files.statusFile,
                    in: AppGroups.Paths.control
                )

            } catch {
                print("[AudioProcessor] Failed to update status: \(error)")
            }
        }
    }

    /// Periodically update app status
    func startStatusUpdates() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateAppStatus()
        }
    }

    // MARK: - Session Cleanup

    /// Clean up all files for a session
    private func cleanupSession(_ sessionId: String?) {
        guard let sessionId = sessionId else { return }

        processingQueue.async {
            print("[AudioProcessor] Cleaning up session: \(sessionId)")

            // Clear chunk buffer
            self.chunkBuffer.removeAll()

            // Clean up audio buffers directory
            if let audioBuffersPath = AppGroups.Paths.audioBuffers {
                do {
                    let files = try FileManager.default.contentsOfDirectory(
                        at: audioBuffersPath,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    )

                    for file in files where file.lastPathComponent.contains(sessionId) {
                        try? FileManager.default.removeItem(at: file)
                    }
                } catch {
                    print("[AudioProcessor] Failed to cleanup session files: \(error)")
                }
            }

            // Clean up transcriptions directory
            if let transcriptionsPath = AppGroups.Paths.transcriptions {
                do {
                    let files = try FileManager.default.contentsOfDirectory(
                        at: transcriptionsPath,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    )

                    for file in files where file.lastPathComponent.contains(sessionId) {
                        try? FileManager.default.removeItem(at: file)
                    }
                } catch {
                    print("[AudioProcessor] Failed to cleanup transcription files: \(error)")
                }
            }
        }
    }
}

// MARK: - Errors

enum AudioProcessorError: LocalizedError {
    case invalidPath
    case fileNotFound
    case processingFailed

    var errorDescription: String? {
        switch self {
        case .invalidPath:
            return "Invalid App Groups path"
        case .fileNotFound:
            return "Audio chunk file not found"
        case .processingFailed:
            return "Failed to process audio chunk"
        }
    }
}
