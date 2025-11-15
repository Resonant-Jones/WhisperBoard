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
            inferenceEngine.startSession(sessionId: message.sessionId)

        case .stop:
            // Final chunk will trigger completion in processAudioChunk

            break

        case .cancel:
            inferenceEngine.cancelSession()
            currentSessionId = nil
            lastProcessedChunkId = -1

        case .ping:
            // Respond with status
            updateAppStatus()

        case .resetModel:
            // Reset model state
            inferenceEngine.cancelSession()
            currentSessionId = nil
            lastProcessedChunkId = -1
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

        // Skip if already processed
        guard metadata.chunkId > lastProcessedChunkId else {
            return
        }

        // Skip if wrong session
        guard let currentSession = currentSessionId,
              currentSession == metadata.sessionId else {
            // Delete old session files
            try? FileManager.default.removeItem(at: metadataURL)
            return
        }

        // Read PCM audio data
        guard let audioBuffersPath = AppGroups.Paths.audioBuffers else {
            throw AudioProcessorError.invalidPath
        }

        let pcmURL = audioBuffersPath.appendingPathComponent(chunkMessage.pcmFileName)
        let audioData = try Data(contentsOf: pcmURL)

        print("[AudioProcessor] Processing chunk \(metadata.chunkId), \(audioData.count) bytes")

        // Send to inference engine
        inferenceEngine.processAudioChunk(audioData, metadata: metadata)

        // Update last processed chunk ID
        lastProcessedChunkId = metadata.chunkId

        // Clean up processed files
        try? FileManager.default.removeItem(at: metadataURL)
        try? FileManager.default.removeItem(at: pcmURL)
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
