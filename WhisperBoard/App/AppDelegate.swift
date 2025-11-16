//
//  AppDelegate.swift
//  WhisperBoard
//
//  Main application delegate
//  Initializes model, starts audio processor, and handles app lifecycle
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    // MARK: - Properties

    var window: UIWindow?

    private var modelLoader: ModelLoader!
    private var inferenceEngine: InferenceEngine!
    private var audioProcessor: AudioProcessor!
    private var tokenStream: TokenStream!
    private var clipboardManager: ClipboardManager!
    private var settings: Settings!

    // MARK: - Application Lifecycle

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        print("🎤 WhisperBoard Starting...")

        // Initialize App Groups shared container
        do {
            try AppGroups.initializeSharedContainer()
        } catch {
            print("❌ Failed to initialize App Groups: \(error)")
            // This is a critical error - app cannot function without shared container
            showFatalError("Failed to initialize shared storage. Please reinstall the app.")
            return false
        }

        // Load settings
        settings = Settings.shared

        // Initialize managers
        modelLoader = ModelLoader.shared
        inferenceEngine = InferenceEngine(settings: settings.settings)
        audioProcessor = AudioProcessor(inferenceEngine: inferenceEngine)
        tokenStream = TokenStream()
        clipboardManager = ClipboardManager()

        // Setup inference engine callbacks
        setupInferenceCallbacks()

        // Load Whisper model (async to avoid blocking launch)
        loadModelAsync()

        // Start monitoring for audio from keyboard extension
        audioProcessor.startMonitoring()
        audioProcessor.startStatusUpdates()

        // Start periodic cleanup
        tokenStream.startPeriodicCleanup()

        // Clean up orphaned files from previous sessions
        cleanupOrphanedFiles()

        // Create main window
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = MainViewController(
            modelLoader: modelLoader,
            inferenceEngine: inferenceEngine,
            clipboardManager: clipboardManager
        )
        window?.makeKeyAndVisible()

        print("✓ WhisperBoard Ready")

        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        print("WhisperBoard Terminating...")

        // Stop monitoring
        audioProcessor.stopMonitoring()

        // Unload model
        modelLoader.unloadModel()
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        print("⚠️ Memory Warning! Taking emergency action...")

        // Cancel any ongoing transcription
        audioProcessor.stopMonitoring()

        // Show memory warning to user
        showMemoryWarning()

        // Give system a moment to release memory
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            // Restart monitoring after memory pressure subsides
            self?.audioProcessor.startMonitoring()
        }
    }

    /// Show memory warning alert
    private func showMemoryWarning() {
        guard let rootVC = window?.rootViewController else { return }

        let alert = UIAlertController(
            title: "Low Memory",
            message: "Please close some apps to free up memory.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))

        DispatchQueue.main.async {
            rootVC.present(alert, animated: true)
        }
    }

    // MARK: - Model Loading

    /// Load Whisper model asynchronously
    private func loadModelAsync() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            print("[App] Loading Whisper model...")

            do {
                try self.modelLoader.loadModel()
                print("[App] ✓ Model loaded successfully")

                DispatchQueue.main.async {
                    // Update UI if needed
                    self.window?.rootViewController?.view.setNeedsDisplay()
                }

            } catch {
                print("[App] ❌ Failed to load model: \(error)")

                DispatchQueue.main.async {
                    self.showError("Failed to load Whisper model. Please restart the app.")
                }
            }
        }
    }

    // MARK: - Inference Callbacks

    /// Setup callbacks for inference engine
    private func setupInferenceCallbacks() {
        // Token updates (streaming)
        inferenceEngine.onTokenUpdate = { [weak self] tokenUpdate in
            self?.tokenStream.sendTokenUpdate(tokenUpdate)
        }

        // Final transcription result
        inferenceEngine.onTranscriptionComplete = { [weak self] result in
            self?.tokenStream.sendTranscriptionResult(result)

            // Also copy to clipboard if setting is enabled
            // (Could add a setting for auto-clipboard)
        }

        // Errors
        inferenceEngine.onError = { [weak self] error in
            self?.tokenStream.sendError(error)
            print("[App] Inference error: \(error.description)")
        }
    }

    // MARK: - Error Handling

    /// Show fatal error alert
    private func showFatalError(_ message: String) {
        let alert = UIAlertController(
            title: "Fatal Error",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))

        window?.rootViewController?.present(alert, animated: true)
    }

    /// Show error alert
    private func showError(_ message: String) {
        let alert = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))

        window?.rootViewController?.present(alert, animated: true)
    }

    // MARK: - Cleanup

    /// Clean up orphaned files from previous sessions
    private func cleanupOrphanedFiles() {
        DispatchQueue.global(qos: .utility).async {
            print("[App] Cleaning up orphaned files...")

            let directories = [
                AppGroups.Paths.audioBuffers,
                AppGroups.Paths.transcriptions,
                AppGroups.Paths.control
            ]

            // Delete files older than 1 hour
            let cutoff = Date().addingTimeInterval(-3600)

            for directory in directories.compactMap({ $0 }) {
                do {
                    let files = try FileManager.default.contentsOfDirectory(
                        at: directory,
                        includingPropertiesForKeys: [.contentModificationDateKey],
                        options: [.skipsHiddenFiles]
                    )

                    var deletedCount = 0
                    for file in files {
                        if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                           let modDate = attributes[.modificationDate] as? Date,
                           modDate < cutoff {
                            try? FileManager.default.removeItem(at: file)
                            deletedCount += 1
                        }
                    }

                    if deletedCount > 0 {
                        print("[App] Cleaned up \(deletedCount) orphaned files from \(directory.lastPathComponent)")
                    }
                } catch {
                    print("[App] Failed to cleanup \(directory.lastPathComponent): \(error)")
                }
            }
        }
    }
}

// MARK: - Main View Controller

/// Main view controller for the app
class MainViewController: UIViewController {

    // MARK: - Properties

    private let modelLoader: ModelLoader
    private let inferenceEngine: InferenceEngine
    private let clipboardManager: ClipboardManager

    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let micButton = UIButton(type: .system)
    private let transcriptionTextView = UITextView()
    private let copyButton = UIButton(type: .system)

    private var isRecording = false
    private var currentSessionId: String?

    // MARK: - Initialization

    init(modelLoader: ModelLoader, inferenceEngine: InferenceEngine, clipboardManager: ClipboardManager) {
        self.modelLoader = modelLoader
        self.inferenceEngine = inferenceEngine
        self.clipboardManager = clipboardManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        setupUI()
        updateStatus()

        // Update status periodically
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        // Title
        titleLabel.text = "🎤 WhisperBoard"
        titleLabel.font = .systemFont(ofSize: 32, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        // Status label
        statusLabel.text = "Loading model..."
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        // Mic button
        micButton.setTitle("Hold to Dictate", for: .normal)
        micButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        micButton.backgroundColor = .systemBlue
        micButton.setTitleColor(.white, for: .normal)
        micButton.layer.cornerRadius = 60
        micButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(micButton)

        // Transcription text view
        transcriptionTextView.font = .systemFont(ofSize: 16)
        transcriptionTextView.layer.borderWidth = 1
        transcriptionTextView.layer.borderColor = UIColor.separator.cgColor
        transcriptionTextView.layer.cornerRadius = 8
        transcriptionTextView.isEditable = false
        transcriptionTextView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(transcriptionTextView)

        // Copy button
        copyButton.setTitle("Copy to Clipboard", for: .normal)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.addTarget(self, action: #selector(copyButtonTapped), for: .touchUpInside)
        view.addSubview(copyButton)

        // Layout
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            micButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            micButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            micButton.widthAnchor.constraint(equalToConstant: 120),
            micButton.heightAnchor.constraint(equalToConstant: 120),

            transcriptionTextView.topAnchor.constraint(equalTo: micButton.bottomAnchor, constant: 40),
            transcriptionTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            transcriptionTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            transcriptionTextView.heightAnchor.constraint(equalToConstant: 150),

            copyButton.topAnchor.constraint(equalTo: transcriptionTextView.bottomAnchor, constant: 16),
            copyButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    // MARK: - Status Updates

    private func updateStatus() {
        let status = inferenceEngine.getStatus()

        var statusText = ""
        if status.isModelLoaded {
            statusText = "✓ Model loaded • \(status.memoryUsageMB) MB"
        } else {
            statusText = "Loading model..."
        }

        if status.isProcessing {
            statusText += " • Recording..."
        }

        statusLabel.text = statusText
    }

    // MARK: - Actions

    @objc private func copyButtonTapped() {
        guard !transcriptionTextView.text.isEmpty else { return }

        clipboardManager.copyToClipboard(transcriptionTextView.text)
        clipboardManager.showCopiedNotification(for: transcriptionTextView.text)

        // Show brief confirmation
        copyButton.setTitle("✓ Copied!", for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.copyButton.setTitle("Copy to Clipboard", for: .normal)
        }
    }
}
