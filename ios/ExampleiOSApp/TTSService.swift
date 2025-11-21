import Foundation
import OnnxRuntimeBindings

final class TTSService {
    enum Voice { case male, female }

    struct Settings {
        var nTest: Int = 1
    }

    struct SynthesisResult {
        let url: URL
        let elapsedSeconds: Double
        let audioSeconds: Double
        var rtf: Double { elapsedSeconds / max(audioSeconds, 1e-6) }
    }

    private let env: ORTEnv
    private let textToSpeech: TextToSpeech
    private let bundleOnnxDir: String
    private let sampleRate: Int

    // Cached style per voice (precomputed at startup or on first use)
    private var cachedStyle: [Voice: Style] = [:]

    init() throws {
        bundleOnnxDir = try Self.locateOnnxDirInBundle()
        env = try ORTEnv(loggingLevel: .warning)
        textToSpeech = try loadTextToSpeech(bundleOnnxDir, false, env)
        sampleRate = textToSpeech.sampleRate
    }

    // Public warmup: precompute styles and run a quick generation to warm models
    func warmup(nfe: Int = 1) async {
        do { try precomputeStyle(for: .male) } catch { print("Warmup style (M) error: \(error)") }
        do { try precomputeStyle(for: .female) } catch { print("Warmup style (F) error: \(error)") }
        // Run a tiny synthesis to JIT/warm up kernels; discard file
        do {
            let res = try await synthesize(text: "Warm up", nfe: max(1, nfe), voice: .male)
            try? FileManager.default.removeItem(at: res.url)
        } catch {
            print("Warmup synth error: \(error)")
        }
    }

    func synthesize(text: String, nfe: Int, voice: Voice, settings: Settings = Settings()) async throws -> SynthesisResult {
        let tic = Date()

        // 1) Get or compute style for the selected voice
        let style = try getStyle(voice: voice)

        // 2) Synthesize via packed TextToSpeech component
        let (wav, duration) = try textToSpeech.call([text], style, nfe)
        let audioSeconds = Double(duration[0])
        let wavLenSample = min(Int(Double(sampleRate) * audioSeconds), wav.count)
        let wavOut = Array(wav[0..<wavLenSample])

        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("supertonic_tts_\(UUID().uuidString).wav")
        try writeWavFile(tmpURL.path, wavOut, sampleRate)

        let elapsed = Date().timeIntervalSince(tic)
        return SynthesisResult(url: tmpURL, elapsedSeconds: elapsed, audioSeconds: audioSeconds)
    }

    // MARK: - Style helpers
    private func precomputeStyle(for voice: Voice) throws {
        if cachedStyle[voice] != nil { return }
        let styleURL = try Self.locateVoiceStyleURL(voice: voice)
        let style = try loadVoiceStyle([styleURL.path], verbose: false)
        cachedStyle[voice] = style
    }

    private func getStyle(voice: Voice) throws -> Style {
        if let style = cachedStyle[voice] { return style }
        try precomputeStyle(for: voice)
        return cachedStyle[voice]!
    }

    // MARK: - Resource location helpers
    private static func locateOnnxDirInBundle() throws -> String {
        let bundle = Bundle.main
        let fm = FileManager.default

        func dirHasRequiredFiles(_ dir: URL) -> Bool {
            let required = [
                "tts.json",
                "duration_predictor.onnx",
                "text_encoder.onnx",
                "vector_estimator.onnx",
                "vocoder.onnx"
            ]
            return required.allSatisfy { fm.fileExists(atPath: dir.appendingPathComponent($0).path) }
        }

        var candidates: [URL] = []
        if let dir = bundle.resourceURL?.appendingPathComponent("onnx", isDirectory: true) { candidates.append(dir) }
        if let dir = bundle.resourceURL?.appendingPathComponent("assets/onnx", isDirectory: true) { candidates.append(dir) }
        if let url = bundle.url(forResource: "tts", withExtension: "json", subdirectory: "onnx") { candidates.append(url.deletingLastPathComponent()) }
        if let url = bundle.url(forResource: "tts", withExtension: "json", subdirectory: "assets/onnx") { candidates.append(url.deletingLastPathComponent()) }
        if let url = bundle.url(forResource: "tts", withExtension: "json", subdirectory: nil) { candidates.append(url.deletingLastPathComponent()) }
        if let root = bundle.resourceURL { candidates.append(root) }

        for dir in candidates {
            if dirHasRequiredFiles(dir) { return dir.path }
        }
        throw NSError(
            domain: "TTS",
            code: -100,
            userInfo: [NSLocalizedDescriptionKey: "Could not find the onnx directory in the bundle. Please make sure the onnx folder (as a folder reference) is included in Copy Bundle Resources in Xcode."]
        )
    }

    private static func locateVoiceStyleURL(voice: Voice) throws -> URL {
        // Prefer M1/F1 defaults; search common subdirectories
        let fileName = (voice == .male) ? "M1" : "F1"
        let bundle = Bundle.main
        let candidates: [URL?] = [
            bundle.url(forResource: fileName, withExtension: "json", subdirectory: "voice_styles"),
            bundle.url(forResource: fileName, withExtension: "json", subdirectory: "assets/voice_styles"),
            bundle.url(forResource: fileName, withExtension: "json", subdirectory: nil)
        ]
        for url in candidates {
            if let url = url { return url }
        }
        // Fallback: scan folders if needed
        if let folder1 = bundle.resourceURL?.appendingPathComponent("voice_styles", isDirectory: true) {
            let file = folder1.appendingPathComponent("\(fileName).json")
            if FileManager.default.fileExists(atPath: file.path) { return file }
        }
        if let folder2 = bundle.resourceURL?.appendingPathComponent("assets/voice_styles", isDirectory: true) {
            let file = folder2.appendingPathComponent("\(fileName).json")
            if FileManager.default.fileExists(atPath: file.path) { return file }
        }
        throw NSError(
            domain: "TTS",
            code: -102,
            userInfo: [NSLocalizedDescriptionKey: "Could not find the voice style JSON (\(fileName).json) in the bundle. Ensure voice_styles folder is included in Copy Bundle Resources."]
        )
    }
}
