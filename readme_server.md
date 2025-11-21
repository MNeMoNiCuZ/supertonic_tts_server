# Supertonic TTS - Docker Deployment Guide

Complete guide for running Supertonic TTS as a containerized service with REST API access.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Building the Container](#building-the-container)
- [Running the Service](#running-the-service)
- [API Documentation](#api-documentation)
- [Python Client Usage](#python-client-usage)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Performance Tuning](#performance-tuning)
- [Production Deployment](#production-deployment)

## Prerequisites

### Required Software

1. **Docker** (version 20.10+)
   - Windows: [Docker Desktop for Windows](https://docs.docker.com/desktop/install/windows-install/)
   - Linux: `sudo apt-get install docker.io docker-compose`
   - macOS: [Docker Desktop for Mac](https://docs.docker.com/desktop/install/mac-install/)

2. **Docker Compose** (usually included with Docker Desktop)
   - Verify: `docker-compose --version`

3. **Git LFS** (for downloading model assets)
   - Windows: Download from [git-lfs.com](https://git-lfs.com)
   - Linux: `sudo apt-get install git-lfs`
   - macOS: `brew install git-lfs`

### Download Model Assets

The ONNX models and voice styles must be present in the `assets/` directory:

```bash
# From the supertonic directory
git lfs install
git clone https://huggingface.co/Supertone/supertonic assets
```

This downloads approximately 200MB+ of model files.

## Quick Start

Get the service running in under 2 minutes:

```bash
# 1. Navigate to the project directory
cd c:\AI\Audio\Speech\supertonic

# 2. Build and start the service
docker-compose up -d

# 3. Check service health
curl http://localhost:8765/health

# 4. Test synthesis (Windows PowerShell)
$body = @{
    text = "Hello from Supertonic!"
    total_step = 5
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:8765/synthesize" -Method Post -Body $body -ContentType "application/json"
```

## Building the Container

### Using Docker Compose (Recommended)

```bash
# Build the image
docker-compose build

# This will:
# - Use Python 3.10-slim base image
# - Install system dependencies (libsndfile1)
# - Install Python packages from requirements-server.txt
# - Copy application code and models
# - Set up non-root user for security
```

### Using Docker Directly

```bash
# Build the image
docker build -t supertonic-tts:latest .

# View image size
docker images supertonic-tts
```

Expected image size: ~1-2GB

## Running the Service

### Using Docker Compose (Recommended)

```bash
# Start the service in detached mode
docker-compose up -d

# View logs
docker-compose logs -f

# Stop the service
docker-compose down

# Restart the service
docker-compose restart
```

### Using Docker Run

```bash
# Run the container
docker run -d \
  --name supertonic-tts \
  -p 8765:8765 \
  -v "$(pwd)/results:/app/results" \
  --restart unless-stopped \
  supertonic-tts:latest

# View logs
docker logs -f supertonic-tts

# Stop the container
docker stop supertonic-tts
docker rm supertonic-tts
```

### Verify the Service

```bash
# Check container status
docker ps | grep supertonic

# Check health
curl http://localhost:8765/health

# View interactive API docs
# Open browser to: http://localhost:8765/docs
```

## API Documentation

### Base URL

```
http://localhost:8765
```

### Endpoints

#### 1. Health Check

```http
GET /health
```

**Response:**
```json
{
  "status": "healthy",
  "model_loaded": true,
  "default_voice": "M1.json",
  "available_voices": ["F1.json", "F2.json", "M1.json", "M2.json"]
}
```

#### 2. Single Text Synthesis

```http
POST /synthesize
```

**Request Body:**
```json
{
  "text": "Text to synthesize",
  "voice_style": "M1.json",
  "total_step": 5,
  "speed": 1.05
}
```

**Parameters:**
- `text` (required): Text to synthesize (string)
- `voice_style` (optional): Voice filename from `assets/voice_styles/` (default: M1.json)
- `total_step` (optional): Denoising steps, 1-20 (default: 5, higher = better quality)
- `speed` (optional): Speech speed factor, 0.5-2.0 (default: 1.05, higher = faster)

**Response:**
```json
{
  "audio_base64": "UklGRiQAAABXQVZFZm10...",
  "duration": 3.45,
  "sample_rate": 24000,
  "text": "Text to synthesize"
}
```

**cURL Example (Linux/macOS):**
```bash
curl -X POST http://localhost:8765/synthesize \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Hello, this is a test!",
    "voice_style": "F1.json",
    "total_step": 5,
    "speed": 1.0
  }' | jq -r '.audio_base64' | base64 -d > output.wav
```

**PowerShell Example (Windows):**
```powershell
$body = @{
    text = "Hello, this is a test!"
    voice_style = "F1.json"
    total_step = 5
    speed = 1.0
} | ConvertTo-Json

$response = Invoke-RestMethod -Uri "http://localhost:8765/synthesize" -Method Post -Body $body -ContentType "application/json"
[System.Convert]::FromBase64String($response.audio_base64) | Set-Content -Path output.wav -Encoding Byte
```

#### 3. Batch Synthesis

```http
POST /batch
```

**Request Body:**
```json
{
  "requests": [
    {
      "text": "First text",
      "voice_style": "M1.json",
      "total_step": 5,
      "speed": 1.05
    },
    {
      "text": "Second text",
      "voice_style": "F1.json",
      "total_step": 5,
      "speed": 1.05
    }
  ]
}
```

**Response:**
```json
{
  "results": [
    {
      "audio_base64": "UklGRiQAAABXQVZFZm10...",
      "duration": 2.3,
      "sample_rate": 24000,
      "text": "First text"
    },
    {
      "audio_base64": "UklGRiQAAABXQVZFZm10...",
      "duration": 2.5,
      "sample_rate": 24000,
      "text": "Second text"
    }
  ]
}
```

## Python Client Usage

### Installation

#### Minimal Installation (Required)

```bash
pip install requests
```

#### Full Installation (Recommended)

For audio playback and MP3 support:

```bash
# Install from requirements file
pip install -r requirements-client.txt

# Or install individually
pip install requests sounddevice soundfile pydub

# For Python 3.13+, also install audioop-lts (pydub dependency)
pip install audioop-lts
```

**For MP3 support, you also need ffmpeg:**
- **Windows**: `choco install ffmpeg` OR download from [ffmpeg.org](https://ffmpeg.org/)
- **Linux**: `sudo apt-get install ffmpeg`
- **macOS**: `brew install ffmpeg`

### Command-Line Interface

The `client.py` script can be used directly from the command line with both short and long argument forms:

#### Quick Examples

```bash
# Basic WAV output
python client.py "Hello world" -o hello.wav

# MP3 output (requires pydub + ffmpeg)
python client.py "Hello world" -o hello.mp3

# Play immediately without saving
python client.py "Listen to this" -p

# Custom voice, quality, and speed
python client.py "Test" -v F1 -q 10 -s 1.2 -o test.wav

# Check server health
python client.py --health

# Remote server
python client.py "Remote test" -u http://192.168.1.100:8765 -o out.wav
```

#### All Command-Line Arguments

| Short | Long | Description | Default |
|-------|------|-------------|---------|
| | `text` | Text to synthesize (positional) | Required |
| `-o` | `--output` | Output file path (.wav, .mp3, etc.) | Required unless `-p` |
| `-v` | `--voice` | Voice style: M1, M2, F1, F2 | M1 |
| `-q` | `--quality` | Quality steps (1-20, higher=better) | 5 |
| `-s` | `--speed` | Speech speed (0.5-2.0, higher=faster) | 1.05 |
| `-u` | `--url` | Server URL | http://localhost:8765 |
| `-p` | `--play` | Play audio immediately | false |
| | `--health` | Check server health | false |
| `-h` | `--help` | Show help message | |

#### Voice Options

| Voice | Gender | Characteristics | Best For |
|-------|--------|-----------------|----------|
| **M1** | Male | Deep, authoritative | Narration, audiobooks, professional |
| **M2** | Male | Lighter, casual | Tutorials, conversational content |
| **F1** | Female | Clear, professional | News, announcements, educational |
| **F2** | Female | Warm, expressive | Storytelling, emotional content |

**Note**: `.json` extension is optional (both `M1` and `M1.json` work)

#### Quality vs Speed Guide

| Quality (-q) | Speed | Use Case |
|--------------|-------|----------|
| 1-2 | Fastest (~0.5-1s) | Draft, real-time, testing |
| 3-5 | Fast (~1-2s) | **Production (recommended)** |
| 6-10 | Moderate (~2-4s) | High quality, presentations |
| 11-20 | Slow (~4-8s) | Studio quality, audiobooks |

#### Audio Format Support

Automatically detected from file extension:
- **WAV** (.wav) - No extra dependencies
- **MP3** (.mp3) - Requires `pydub` + `ffmpeg`
- **OGG** (.ogg) - Requires `pydub` + `ffmpeg`
- **FLAC** (.flac) - Requires `pydub` + `ffmpeg`

### Python Library Usage

#### Basic Usage

```python
from client import SupertonicClient

# Initialize client
client = SupertonicClient(base_url="http://localhost:8765")

# Check health
health = client.health()
print(health)

# Synthesize speech (WAV)
client.synthesize(
    text="Hello from Python!",
    voice_style="M1",  # .json extension optional
    save_path="output.wav"
)

# Synthesize as MP3 (requires pydub + ffmpeg)
client.synthesize(
    text="Hello from Python!",
    voice_style="F1",
    save_path="output.mp3"
)

# Close client
client.close()
```

#### Context Manager (Recommended)

```python
from client import SupertonicClient

with SupertonicClient() as client:
    client.synthesize(
        text="Using context manager",
        voice_style="F2",
        total_step=10,  # High quality
        speed=1.0,      # Normal speed
        save_path="output.wav"
    )
```

#### Batch Synthesis

```python
from client import SupertonicClient

client = SupertonicClient()

texts = [
    "First sentence",
    "Second sentence",
    "Third sentence"
]

voices = ["M1", "F1", "M2"]  # Mix different voices

client.batch_synthesize(
    texts=texts,
    voice_styles=voices,
    save_dir="batch_outputs"
)
```

#### Convenience Function

```python
from client import synthesize_text

# Quick one-liner synthesis
synthesize_text(
    text="Quick synthesis",
    save_path="quick.wav",
    voice_style="F2",
    total_step=10
)
```

### Configuration

Edit `client.py` to customize:

```python
# Temporary file directory for --play mode (line ~194)
TEMP_DIR = None  # Default: system temp
# TEMP_DIR = r"C:\Temp\TTS"  # Custom Windows path
# TEMP_DIR = "/tmp/tts"  # Custom Linux/Mac path
```

### Running Examples

```bash
# Run the comprehensive example script
python example_client.py

# Outputs will be in client_results/ directory
# Includes examples of all voices, quality levels, and speeds
```


## Configuration

### Environment Variables

Set these in `docker-compose.yml` or pass to `docker run`:

```yaml
environment:
  - PYTHONUNBUFFERED=1          # Disable output buffering
  - LOG_LEVEL=info              # Logging level (debug, info, warning, error)
```

### Port Configuration

To change the port, modify both `docker-compose.yml` and `server.py`:

**docker-compose.yml:**
```yaml
ports:
  - "9000:8765"  # Map host port 9000 to container port 8765
```

**Then access via:** `http://localhost:9000`

### Resource Limits

Add resource constraints in `docker-compose.yml`:

```yaml
deploy:
  resources:
    limits:
      cpus: '4'
      memory: 4G
    reservations:
      cpus: '2'
      memory: 2G
```

## Troubleshooting

### Container Won't Start

**Check logs:**
```bash
docker-compose logs -f
```

**Common issues:**
- Missing `assets/` directory → Download models from Hugging Face
- Port 8765 in use → Change port in docker-compose.yml
- Insufficient memory → Increase Docker memory limit

### Health Check Fails

```bash
# Enter container
docker exec -it supertonic-tts bash

# Test server directly
curl localhost:8765/health

# Check if models loaded
ls -la /app/assets/onnx/
```

### Slow Synthesis

- Reduce `total_step` (e.g., 2 instead of 10)
- Increase Docker CPU/memory allocation
- Use batch processing for multiple texts
- Consider enabling GPU support (requires code modification)

### Client Connection Errors

```python
# Test from Python
import requests
response = requests.get("http://localhost:8765/health")
print(response.status_code)  # Should be 200
```

**If connection fails:**
- Verify container is running: `docker ps`
- Check port mapping: `docker port supertonic-tts`
- Test with cURL first
- Check firewall settings

## Performance Tuning

### Inference Speed vs Quality

| total_step | Quality | Speed | Use Case |
|------------|---------|-------|----------|
| 1-2 | Low | Fastest | Real-time, draft |
| 3-5 | Good | Fast | Production, balanced |
| 6-10 | High | Moderate | High quality |
| 11-20 | Very High | Slow | Studio quality |

### Batch Processing

For multiple texts, use batch synthesis for better throughput:

```python
# Faster: Single batch call
client.batch_synthesize(texts, voices)

# Slower: Multiple individual calls
for text, voice in zip(texts, voices):
    client.synthesize(text, voice_style=voice)
```

### Network Optimization

- Run container on same machine as client (localhost)
- Use batch synthesis to reduce HTTP overhead
- Consider persistent connections (client uses session)

## Production Deployment

### Security Considerations

1. **Use HTTPS** with a reverse proxy (nginx, traefik)
2. **Add authentication** (API keys, OAuth)
3. **Rate limiting** to prevent abuse
4. **Network isolation** (internal network only if possible)

### Reverse Proxy Example (nginx)

```nginx
server {
    listen 443 ssl;
    server_name tts.example.com;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    location / {
        proxy_pass http://localhost:8765;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### Monitoring

```bash
# Container stats
docker stats supertonic-tts

# Monitor logs
docker logs -f --tail 100 supertonic-tts

# Health check endpoint
watch -n 5 curl http://localhost:8765/health
```

### Scaling

For high load, run multiple instances:

```yaml
# docker-compose.yml
services:
  supertonic-tts:
    # ... existing config ...
    deploy:
      replicas: 3  # Run 3 instances
```

Then use a load balancer (nginx, HAProxy) to distribute requests.

### Backup

Important directories to backup:
- `assets/` (if you've added custom voices)
- `results/` (if storing outputs)

### Updates

```bash
# Pull latest code
git pull

# Rebuild and restart
docker-compose down
docker-compose build
docker-compose up -d
```

## Additional Resources

- [Supertonic GitHub](https://github.com/supertone-inc/supertonic)
- [Hugging Face Models](https://huggingface.co/Supertone/supertonic)
- [Interactive Demo](https://huggingface.co/spaces/Supertone/supertonic)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Docker Documentation](https://docs.docker.com/)

## License

This Docker deployment inherits the licenses from the Supertonic project:
- Sample code: MIT License
- Model: OpenRAIL-M License

---

**Need help?** Check the [Troubleshooting](#troubleshooting) section or open an issue on GitHub.
