//
//  ModelLoader.swift
//  WhisperBoard
//
//  Handles loading and lifecycle management of Whisper-small Q5_1 model
//  Implements memory-safe model warming and context reuse
//

import Foundation

/// Model loader responsible for initializing Whisper model and managing its lifecycle
class ModelLoader {

    // MARK: - Properties

    private var whisperContext: OpaquePointer?
    private var isModelLoaded = false
    private let modelQueue = DispatchQueue(label: "com.whisperboard.modelloader", qos: .userInitiated)

    /// Singleton instance
    static let shared = ModelLoader()

    /// Model configuration
    struct ModelConfig {
        let modelPath: String
        let variant: ModelVariant
        let useGPU: Bool
        let numThreads: Int

        static var `default`: ModelConfig {
            ModelConfig(
                modelPath: "",  // Will be set from bundle
                variant: .smallQ5_1,
                useGPU: true,
                numThreads: 4
            )
        }
    }

    enum ModelVariant: String {
        case smallQ5_1 = "ggml-small-q5_1"
        case smallQ4 = "ggml-small-q4_0"
        case smallQ8 = "ggml-small-q8_0"
        case tinyQ5 = "ggml-tiny-q5_1"  // Fallback for low-memory devices

        var expectedMemoryMB: Int {
            switch self {
            case .smallQ5_1: return 150
            case .smallQ4: return 120
            case .smallQ8: return 280
            case .tinyQ5: return 80
            }
        }

        var expectedPeakMemoryMB: Int {
            switch self {
            case .smallQ5_1: return 380
            case .smallQ4: return 330
            case .smallQ8: return 500
            case .tinyQ5: return 200
            }
        }
    }

    // MARK: - Initialization

    private init() {
        // Private initializer for singleton
    }

    // MARK: - Model Loading

    /// Load the Whisper model from bundle
    /// - Parameter config: Model configuration (uses default if nil)
    /// - Throws: ModelLoaderError if loading fails
    func loadModel(config: ModelConfig? = nil) throws {
        try modelQueue.sync {
            // If already loaded, skip
            if isModelLoaded {
                print("[ModelLoader] Model already loaded")
                return
            }

            let modelConfig = config ?? ModelConfig.default
            let modelPath = try getModelPath(for: modelConfig.variant)

            print("[ModelLoader] Loading model from: \(modelPath)")
            print("[ModelLoader] Expected memory: \(modelConfig.variant.expectedMemoryMB) MB")
            print("[ModelLoader] Peak memory: \(modelConfig.variant.expectedPeakMemoryMB) MB")

            // Initialize Whisper context
            // NOTE: This is a placeholder. Actual whisper.cpp integration requires C++ bridging
            // whisperContext = whisper_init_from_file_with_params(modelPath, whisper_context_default_params())

            guard whisperContext != nil else {
                throw ModelLoaderError.modelLoadFailed("Failed to initialize Whisper context")
            }

            isModelLoaded = true
            print("[ModelLoader] ✓ Model loaded successfully")

            // Warm up the model with a dummy inference
            try warmupModel()
        }
    }

    /// Warm up the model with a dummy inference to reduce cold-start latency
    private func warmupModel() throws {
        print("[ModelLoader] Warming up model...")

        // Create a silent audio buffer (1 second of silence at 16kHz)
        let sampleRate = 16000
        let duration = 1.0
        let numSamples = Int(Double(sampleRate) * duration)
        var silentBuffer = [Float](repeating: 0.0, count: numSamples)

        // Run a dummy inference
        // NOTE: Placeholder - actual implementation requires whisper.cpp integration
        // whisper_full(whisperContext, whisper_full_default_params(), &silentBuffer, Int32(numSamples))

        print("[ModelLoader] ✓ Model warmed up")
    }

    /// Get the model file path from app bundle
    private func getModelPath(for variant: ModelVariant) throws -> String {
        // Check main bundle first
        if let modelPath = Bundle.main.path(forResource: variant.rawValue, ofType: "bin") {
            return modelPath
        }

        // Check app group shared container (for models downloaded after installation)
        if let sharedPath = AppGroups.containerURL?
            .appendingPathComponent("Models")
            .appendingPathComponent("\(variant.rawValue).bin").path,
           FileManager.default.fileExists(atPath: sharedPath) {
            return sharedPath
        }

        throw ModelLoaderError.modelNotFound(variant.rawValue)
    }

    // MARK: - Model Unloading

    /// Unload the model and free memory
    func unloadModel() {
        modelQueue.sync {
            guard isModelLoaded, let context = whisperContext else {
                return
            }

            print("[ModelLoader] Unloading model...")

            // Free Whisper context
            // whisper_free(context)

            whisperContext = nil
            isModelLoaded = false

            print("[ModelLoader] ✓ Model unloaded")
        }
    }

    // MARK: - Model Info

    /// Check if model is currently loaded
    var isLoaded: Bool {
        return modelQueue.sync { isModelLoaded }
    }

    /// Get current memory usage estimate in MB
    var estimatedMemoryUsageMB: Int {
        return modelQueue.sync {
            guard isModelLoaded else { return 0 }

            // Get actual memory usage using task_info
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

            let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }

            if kerr == KERN_SUCCESS {
                let usedMB = Int(info.resident_size / 1024 / 1024)
                return usedMB
            }

            return 0
        }
    }

    /// Get the Whisper context (for inference engine)
    func getContext() -> OpaquePointer? {
        return modelQueue.sync { whisperContext }
    }
}

// MARK: - Errors

enum ModelLoaderError: LocalizedError {
    case modelNotFound(String)
    case modelLoadFailed(String)
    case memoryPressure

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let variant):
            return "Model file not found: \(variant)"
        case .modelLoadFailed(let reason):
            return "Failed to load model: \(reason)"
        case .memoryPressure:
            return "Insufficient memory to load model"
        }
    }
}

// MARK: - Whisper.cpp Placeholder Types
// These will be replaced with actual whisper.cpp bridging header imports

typealias OpaquePointer = UnsafeMutableRawPointer
