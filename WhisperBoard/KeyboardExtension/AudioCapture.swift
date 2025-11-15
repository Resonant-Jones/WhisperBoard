//
//  AudioCapture.swift
//  WhisperBoard Keyboard Extension
//
//  Handles audio capture in keyboard extension
//  Records 16kHz mono PCM audio and chunks it for streaming
//

import Foundation
import AVFoundation

/// Audio capture for keyboard extension
class AudioCapture {

    // MARK: - Properties

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var currentSessionId: String?
    private var chunkCounter = 0
    private var isRecording = false

    /// Audio format (16kHz mono PCM)
    private let targetSampleRate: Double = 16000
    private let channelCount: AVAudioChannelCount = 1

    /// Chunk size in milliseconds (from settings, default 200ms)
    private var chunkSizeMs: Int = 200

    /// Callbacks
    var onAudioChunk: ((Data, AudioChunkMetadata) -> Void)?
    var onError: ((Error) -> Void)?

    // MARK: - Recording Control

    /// Start recording audio
    /// - Parameter sessionId: Session identifier for this recording
    func startRecording(sessionId: String) throws {
        guard !isRecording else {
            throw AudioCaptureError.alreadyRecording
        }

        print("[AudioCapture] Starting recording for session: \(sessionId)")

        currentSessionId = sessionId
        chunkCounter = 0

        // Request microphone permission
        let permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        switch permissionStatus {
        case .authorized:
            try setupAudioEngine()
        case .notDetermined:
            // Request permission
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted {
                    try? self?.setupAudioEngine()
                } else {
                    self?.onError?(AudioCaptureError.permissionDenied)
                }
            }
        case .denied, .restricted:
            throw AudioCaptureError.permissionDenied
        @unknown default:
            throw AudioCaptureError.permissionDenied
        }
    }

    /// Stop recording audio
    func stopRecording() {
        guard isRecording else { return }

        print("[AudioCapture] Stopping recording")

        // Stop audio engine
        audioEngine?.stop()
        inputNode?.removeTap(onBus: 0)

        audioEngine = nil
        inputNode = nil
        isRecording = false
        currentSessionId = nil
        chunkCounter = 0
    }

    // MARK: - Audio Engine Setup

    /// Setup AVAudioEngine for recording
    private func setupAudioEngine() throws {
        // Create audio engine
        audioEngine = AVAudioEngine()

        guard let audioEngine = audioEngine else {
            throw AudioCaptureError.engineSetupFailed
        }

        inputNode = audioEngine.inputNode

        guard let inputNode = inputNode else {
            throw AudioCaptureError.noInputNode
        }

        // Get input format
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create target format (16kHz mono)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatConversionFailed
        }

        // Create format converter if needed
        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        guard converter != nil else {
            throw AudioCaptureError.formatConversionFailed
        }

        // Calculate buffer size for chunk duration
        let bufferSize = AVAudioFrameCount(targetSampleRate * Double(chunkSizeMs) / 1000.0)

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer, converter: converter!, targetFormat: targetFormat)
        }

        // Prepare and start audio engine
        audioEngine.prepare()

        try audioEngine.start()

        isRecording = true

        print("[AudioCapture] ✓ Audio engine started")
    }

    // MARK: - Audio Processing

    /// Process audio buffer and convert to target format
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        guard let sessionId = currentSessionId else { return }

        // Create output buffer
        let capacity = AVAudioFrameCount(
            Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate
        )

        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return
        }

        var error: NSError?

        // Convert audio format
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            onError?(error)
            return
        }

        // Convert to Data (Float32 PCM)
        guard let channelData = convertedBuffer.floatChannelData?[0] else {
            return
        }

        let frameLength = Int(convertedBuffer.frameLength)
        let audioData = Data(bytes: channelData, count: frameLength * MemoryLayout<Float>.size)

        // Create metadata
        let metadata = AudioChunkMetadata(
            chunkId: chunkCounter,
            sampleRate: Int(targetSampleRate),
            channels: Int(channelCount),
            format: .float32,
            duration: Double(frameLength) / targetSampleRate,
            timestamp: Date(),
            sessionId: sessionId,
            isLastChunk: false  // Will be set to true when stopping
        )

        // Send chunk via callback
        onAudioChunk?(audioData, metadata)

        chunkCounter += 1
    }

    // MARK: - Settings

    /// Update chunk size (call before recording)
    func setChunkSize(_ sizeMs: Int) {
        chunkSizeMs = sizeMs
    }
}

// MARK: - Errors

enum AudioCaptureError: LocalizedError {
    case alreadyRecording
    case permissionDenied
    case engineSetupFailed
    case noInputNode
    case formatConversionFailed

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Already recording audio"
        case .permissionDenied:
            return "Microphone permission denied. Please enable in Settings."
        case .engineSetupFailed:
            return "Failed to setup audio engine"
        case .noInputNode:
            return "No audio input node available"
        case .formatConversionFailed:
            return "Failed to convert audio format"
        }
    }
}
