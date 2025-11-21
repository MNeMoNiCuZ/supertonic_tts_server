# TTS ONNX Node.js Implementation

Node.js implementation for TTS inference. Uses ONNX Runtime to generate speech from text.

## 📰 Update News

**2025.11.19** - Added `--speed` parameter to control speech synthesis speed (default: 1.05, recommended range: 0.9-1.5).

**2025.11.19** - Added automatic text chunking for long-form inference. Long texts are split into chunks and synthesized with natural pauses.

## Requirements

- Node.js v16 or higher
- npm or yarn

## Installation

```bash
cd nodejs
npm install
```

## Basic Usage

### Example 1: Default Inference
Run inference with default settings:
```bash
npm start
```

Or:
```bash
node example_onnx.js
```

This will use:
- Voice style: `assets/voice_styles/M1.json`
- Text: "This morning, I took a walk in the park, and the sound of the birds and the breeze was so pleasant that I stopped for a long time just to listen."
- Output directory: `results/`
- Total steps: 5
- Number of generations: 4

### Example 2: Batch Inference
Process multiple voice styles and texts at once:
```bash
node example_onnx.js \
  --voice-style "assets/voice_styles/M1.json,assets/voice_styles/F1.json" \
  --text "The sun sets behind the mountains, painting the sky in shades of pink and orange.|The weather is beautiful and sunny outside. A gentle breeze makes the air feel fresh and pleasant." \
  --batch
```

This will:
- Use `--batch` flag to enable batch processing mode
- Generate speech for 2 different voice-text pairs
- Use male voice style (M1.json) for the first text
- Use female voice style (F1.json) for the second text
- Process both samples in a single batch (automatic text chunking disabled)

### Example 3: High Quality Inference
Increase denoising steps for better quality:
```bash
node example_onnx.js \
  --total-step 10 \
  --voice-style "assets/voice_styles/M1.json" \
  --text "Increasing the number of denoising steps improves the output's fidelity and overall quality."
```

This will:
- Use 10 denoising steps instead of the default 5
- Produce higher quality output at the cost of slower inference

### Example 4: Long-Form Inference
For long texts, the system automatically chunks the text into manageable segments and generates a single audio file:
```bash
node example_onnx.js \
  --voice-style "assets/voice_styles/M1.json" \
  --text "Once upon a time, in a small village nestled between rolling hills, there lived a young artist named Clara. Every morning, she would wake up before dawn to capture the first light of day. The golden rays streaming through her window inspired countless paintings. Her work was known throughout the region for its vibrant colors and emotional depth. People from far and wide came to see her gallery, and many said her paintings could tell stories that words never could."
```

This will:
- Automatically split the long text into smaller chunks (max 300 characters by default)
- Process each chunk separately while maintaining natural speech flow
- Insert brief silences (0.3 seconds) between chunks for natural pacing
- Combine all chunks into a single output audio file

**Note**: When using batch mode (`--batch`), automatic text chunking is disabled. Use non-batch mode for long-form text synthesis.

## Available Arguments

| Argument | Type | Default | Description |
|----------|------|---------|-------------|
| `--use-gpu` | flag | False | Use GPU for inference (not supported yet) |
| `--onnx-dir` | str | `assets/onnx` | Path to ONNX model directory |
| `--total-step` | int | 5 | Number of denoising steps (higher = better quality, slower) |
| `--n-test` | int | 4 | Number of times to generate each sample |
| `--voice-style` | str+ | `assets/voice_styles/M1.json` | Voice style file path(s). Separate multiple files with commas |
| `--text` | str+ | (long default text) | Text(s) to synthesize. Separate multiple texts with pipes |
| `--save-dir` | str | `results` | Output directory |
| `--batch` | flag | False | Enable batch mode (disables automatic text chunking) |

## Notes

- **Batch Processing**: The number of voice style files must match the number of texts. Use commas to separate files and pipes to separate texts
- **Long-Form Inference**: Without `--batch` flag, long texts are automatically chunked and combined into a single audio file with natural pauses
- **Quality vs Speed**: Higher `--total-step` values produce better quality but take longer
- **GPU Support**: GPU mode is not supported yet

## Architecture

- `helper.js`: Node.js port of Python's `helper.py`
  - `Preprocessor`: Audio preprocessing (STFT, Mel Spectrogram)
  - `UnicodeProcessor`: Text preprocessing
  - Utility functions (mask generation, tensor conversion, etc.)

- `example_onnx.js`: Main inference script
  - ONNX model loading
  - TTS inference pipeline execution
  - WAV file saving

- `package.json`: Node.js project configuration and dependencies

## Implementation Notes

1. **Pure Node.js WAV Processing**: Writes WAV files without external native libraries. Outputs 16-bit PCM format.

2. **Memory Efficiency**: Note that Node.js may consume significant memory when processing large arrays.

3. **Performance**: The mel spectrogram extraction (Step 1-1) is currently slower than Python's Librosa, which uses highly optimized C extensions. This bottleneck could be further improved with additional optimizations such as WASM-based FFT libraries or native addons.
