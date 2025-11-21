import Foundation
import AVFoundation

@MainActor
final class TTSViewModel: ObservableObject {
    @Published var text: String = "This morning, I took a walk in the park, and the sound of the birds and the breeze was so pleasant that I stopped for a long time just to listen."
    @Published var nfe: Double = 5
    @Published var voice: TTSService.Voice = .male
    @Published var isGenerating: Bool = false
    @Published var isPlaying: Bool = false
    @Published var errorMessage: String?
    @Published var audioURL: URL?

    @Published var elapsedSeconds: Double?
    @Published var audioSeconds: Double?

    private var service: TTSService?
    private var player = AudioPlayer()

    var rtfText: String? {
        guard let e = elapsedSeconds, let a = audioSeconds, a > 0 else { return nil }
        let rtf = e / a
        return String(format: "RTF %.2fx · %.2fs / %.2fs", rtf, e, a)
    }

    func startup() {
        do {
            service = try TTSService()
            Task { await self.service?.warmup(nfe: 5) }
        } catch {
            errorMessage = "Failed to init TTS: \(error.localizedDescription)"
        }
    }

    func generate() {
        guard let service = service else { return }
        isGenerating = true
        errorMessage = nil
        audioURL = nil
        elapsedSeconds = nil
        audioSeconds = nil
        Task {
            do {
                let result = try await service.synthesize(text: text, nfe: Int(nfe), voice: voice)
                await MainActor.run {
                    self.audioURL = result.url
                    self.elapsedSeconds = result.elapsedSeconds
                    self.audioSeconds = result.audioSeconds
                    self.isGenerating = false
                }
                self.play(url: result.url)
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isGenerating = false
                }
            }
        }
    }

    func togglePlay() {
        if isPlaying {
            player.stop()
            isPlaying = false
        } else if let url = audioURL {
            play(url: url)
        }
    }

    private func play(url: URL) {
        player.play(url: url) { [weak self] in
            DispatchQueue.main.async { self?.isPlaying = false }
        }
        isPlaying = true
    }
}
