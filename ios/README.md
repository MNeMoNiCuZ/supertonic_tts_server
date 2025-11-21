# Supertonic iOS Example App

A minimal iOS demo that runs Supertonic (ONNX Runtime) on-device. The app shows:
- Multiline text input
- NFE (denoising steps) slider
- Voice toggle (M/F)
- Generate & Play buttons
- RTF display (Elapsed / Audio seconds)

All ONNX models/configs are reused from `Supertonic/assets/onnx`, and voice style JSON files from `Supertonic/assets/voice_styles`.

## Prerequisites
- macOS 13+, Xcode 15+
- Swift 5.9+
- iOS 15+ device (recommended)
- Homebrew, XcodeGen

Install tools (if needed):
```bash
brew install xcodegen
```

## Quick Start (zero-click in Xcode)
0) Prepare assets next to the iOS target (one-time)
```bash
cd ios/ExampleiOSApp
mkdir -p onnx voice_styles
rsync -a ../../assets/onnx/ onnx/
rsync -a ../../assets/voice_styles/ voice_styles/
```

1) Generate the Xcode project with XcodeGen
```bash
xcodegen generate
open ExampleiOSApp.xcodeproj
```

2) Open in Xcode and select your iPhone as the run destination
- Targets → ExampleiOSApp → Signing & Capabilities: Select your Team
- iOS Deployment Target: 15.0+

3) Build & Run on device
- Type text → adjust NFE/Voice → Tap Generate → Audio plays automatically
- An RTF line shows like: `RTF 0.30x · 3.04s / 10.11s`

## What's included (generated project)
- SwiftUI app files: `App.swift`, `ContentView.swift`, `TTSViewModel.swift`, `AudioPlayer.swift`
- Runtime wrapper: `TTSService.swift` (includes TTS inference logic)
- Resources (local, vendored in `ios/ExampleiOSApp/onnx` and `ios/ExampleiOSApp/voice_styles` after step 0)

These references are defined in `project.yml` and added to the app bundle by XcodeGen.

## App Controls
- **Text**: Multiline `TextEditor`
- **NFE**: Denoising steps (default 5)
- **Voice**: M1/M2/F1/F2 voice style selector (4 pre-extracted styles)
- **Generate**: Runs end-to-end synthesis
- **Play/Stop**: Controls playback of the last output
- **RTF**: Shows Elapsed / Audio seconds for quick performance intuition