//
//  KeyboardViewController.swift
//  WhisperBoard Keyboard Extension
//
//  Main keyboard extension view controller
//  Manages UI, audio capture, and communication with main app
//

import UIKit

class KeyboardViewController: UIInputViewController {

    // MARK: - Properties

    private var audioCapture: AudioCapture!
    private var ipcPipe: IPCPipe!
    private var transcriptionDisplay: TranscriptionDisplay!

    private let micButton = UIButton(type: .custom)
    private let transcriptionLabel = UILabel()
    private let statusIndicator = UIView()

    private var isRecording = false
    private var currentSessionId: String?

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Setup components
        setupComponents()

        // Setup UI
        setupKeyboardUI()

        // Check if main app is available
        checkMainAppStatus()
    }

    // MARK: - Component Setup

    private func setupComponents() {
        // Initialize audio capture
        audioCapture = AudioCapture()
        audioCapture.onAudioChunk = { [weak self] audioData, metadata in
            self?.handleAudioChunk(audioData, metadata: metadata)
        }
        audioCapture.onError = { [weak self] error in
            self?.handleAudioError(error)
        }

        // Initialize IPC pipe
        ipcPipe = IPCPipe()
        ipcPipe.onTranscriptionUpdate = { [weak self] result in
            self?.handleTranscriptionUpdate(result)
        }
        ipcPipe.onError = { [weak self] error in
            self?.handleIPCError(error)
        }

        // Initialize transcription display
        transcriptionDisplay = TranscriptionDisplay()

        // Start monitoring for transcription updates
        ipcPipe.startMonitoring()
    }

    // MARK: - UI Setup

    private func setupKeyboardUI() {
        view.backgroundColor = .systemGray6

        // Status indicator (top-left corner)
        statusIndicator.backgroundColor = .systemGray
        statusIndicator.layer.cornerRadius = 4
        statusIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusIndicator)

        // Transcription label (shows real-time transcription)
        transcriptionLabel.text = ""
        transcriptionLabel.font = .systemFont(ofSize: 14)
        transcriptionLabel.textAlignment = .center
        transcriptionLabel.numberOfLines = 2
        transcriptionLabel.textColor = .label
        transcriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(transcriptionLabel)

        // Mic button (large central button)
        micButton.setTitle("🎤", for: .normal)
        micButton.titleLabel?.font = .systemFont(ofSize: 44)
        micButton.backgroundColor = .systemBlue
        micButton.layer.cornerRadius = 40
        micButton.translatesAutoresizingMaskIntoConstraints = false

        // Add long-press gesture
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(micButtonPressed(_:)))
        longPress.minimumPressDuration = 0.1
        micButton.addGestureRecognizer(longPress)

        view.addSubview(micButton)

        // Layout
        NSLayoutConstraint.activate([
            statusIndicator.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            statusIndicator.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            statusIndicator.widthAnchor.constraint(equalToConstant: 8),
            statusIndicator.heightAnchor.constraint(equalToConstant: 8),

            transcriptionLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            transcriptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            transcriptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            micButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            micButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            micButton.widthAnchor.constraint(equalToConstant: 80),
            micButton.heightAnchor.constraint(equalToConstant: 80)
        ])

        // Set keyboard height
        let heightConstraint = NSLayoutConstraint(
            item: view!,
            attribute: .height,
            relatedBy: .equal,
            toItem: nil,
            attribute: .notAnAttribute,
            multiplier: 1.0,
            constant: 180
        )
        heightConstraint.priority = .required
        view.addConstraint(heightConstraint)
    }

    // MARK: - Mic Button Actions

    @objc private func micButtonPressed(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            startRecording()
        case .ended, .cancelled, .failed:
            stopRecording()
        default:
            break
        }
    }

    // MARK: - Recording Control

    private func startRecording() {
        guard !isRecording else { return }

        // Generate new session ID
        currentSessionId = UUID().uuidString

        guard let sessionId = currentSessionId else { return }

        print("[Keyboard] Starting recording session: \(sessionId)")

        // Update UI
        isRecording = true
        micButton.backgroundColor = .systemRed
        transcriptionLabel.text = "Listening..."
        statusIndicator.backgroundColor = .systemRed

        // Send START control signal to main app
        ipcPipe.sendControlSignal(.start, sessionId: sessionId)

        // Start audio capture
        do {
            try audioCapture.startRecording(sessionId: sessionId)
        } catch {
            handleAudioError(error)
            stopRecording()
        }

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private func stopRecording() {
        guard isRecording else { return }

        print("[Keyboard] Stopping recording")

        // Update UI
        isRecording = false
        micButton.backgroundColor = .systemBlue
        statusIndicator.backgroundColor = .systemGray

        // Stop audio capture
        audioCapture.stopRecording()

        // Send STOP control signal to main app
        if let sessionId = currentSessionId {
            ipcPipe.sendControlSignal(.stop, sessionId: sessionId)
        }

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    // MARK: - Audio Chunk Handling

    private func handleAudioChunk(_ audioData: Data, metadata: AudioChunkMetadata) {
        // Send audio chunk to main app via IPC
        do {
            try ipcPipe.sendAudioChunk(audioData, metadata: metadata)
        } catch {
            print("[Keyboard] Failed to send audio chunk: \(error)")
        }
    }

    private func handleAudioError(_ error: Error) {
        print("[Keyboard] Audio error: \(error)")

        transcriptionLabel.text = "⚠️ Microphone error"
        transcriptionLabel.textColor = .systemRed

        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.transcriptionLabel.text = ""
            self.transcriptionLabel.textColor = .label
        }
    }

    // MARK: - Transcription Updates

    private func handleTranscriptionUpdate(_ result: TranscriptionResult) {
        print("[Keyboard] Received transcription: \"\(result.text)\"")

        // Update display
        transcriptionLabel.text = result.text
        transcriptionLabel.textColor = .label

        // If final result, insert into text field
        if result.isFinal {
            insertTranscriptionIntoTextField(result.text)

            // Clear label after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.transcriptionLabel.text = ""
            }
        }
    }

    private func insertTranscriptionIntoTextField(_ text: String) {
        // Insert text into the current text field
        if let proxy = textDocumentProxy as UITextDocumentProxy? {
            proxy.insertText(text)

            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }

    private func handleIPCError(_ error: ErrorMessage) {
        print("[Keyboard] IPC error: \(error.description)")

        transcriptionLabel.text = "⚠️ Connection error"
        transcriptionLabel.textColor = .systemOrange

        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.transcriptionLabel.text = ""
            self.transcriptionLabel.textColor = .label
        }
    }

    // MARK: - App Status

    private func checkMainAppStatus() {
        ipcPipe.checkAppStatus { [weak self] status in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if status.isModelLoaded {
                    self.statusIndicator.backgroundColor = .systemGreen
                } else {
                    self.statusIndicator.backgroundColor = .systemOrange
                }
            }
        }

        // Check periodically
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkMainAppStatus()
        }
    }

    // MARK: - Memory Management

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()

        print("[Keyboard] ⚠️ Memory warning")

        // Cancel any ongoing recording
        if isRecording {
            stopRecording()
        }
    }
}
