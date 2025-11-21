"""
FastAPI Server for Supertonic TTS
Provides REST API endpoints for text-to-speech synthesis
"""

import base64
import io
import os
import sys
from typing import Optional, List
import logging

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import soundfile as sf
import numpy as np

# Add py directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'py'))
from helper import load_text_to_speech, load_voice_style

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="Supertonic TTS API",
    description="Lightning-fast, on-device text-to-speech synthesis",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global variables for models
text_to_speech = None
default_voice_style = None

# Pydantic models for request/response
class SynthesisRequest(BaseModel):
    text: str = Field(..., description="Text to synthesize", min_length=1)
    voice_style: Optional[str] = Field(
        None,
        description="Path to voice style JSON file (relative to assets/voice_styles/)"
    )
    total_step: int = Field(5, ge=1, le=20, description="Number of denoising steps")
    speed: float = Field(1.05, ge=0.5, le=2.0, description="Speech speed factor")


class BatchSynthesisRequest(BaseModel):
    requests: List[SynthesisRequest] = Field(..., description="List of synthesis requests")


class SynthesisResponse(BaseModel):
    audio_base64: str = Field(..., description="Base64-encoded WAV audio")
    duration: float = Field(..., description="Audio duration in seconds")
    sample_rate: int = Field(..., description="Audio sample rate")
    text: str = Field(..., description="Original text")


class BatchSynthesisResponse(BaseModel):
    results: List[SynthesisResponse]


class HealthResponse(BaseModel):
    status: str
    model_loaded: bool
    default_voice: str
    available_voices: List[str]


@app.on_event("startup")
async def startup_event():
    """Load models on startup"""
    global text_to_speech, default_voice_style
    
    logger.info("Loading TTS models...")
    try:
        onnx_dir = "assets/onnx"
        text_to_speech = load_text_to_speech(onnx_dir, use_gpu=False)
        logger.info("TTS models loaded successfully")
        
        # Load default voice style
        default_voice_path = "assets/voice_styles/M1.json"
        default_voice_style = load_voice_style([default_voice_path], verbose=False)
        logger.info(f"Default voice style loaded: {default_voice_path}")
        
    except Exception as e:
        logger.error(f"Failed to load models: {e}")
        raise


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint"""
    voice_dir = "assets/voice_styles"
    available_voices = []
    
    if os.path.exists(voice_dir):
        available_voices = [
            f for f in os.listdir(voice_dir) 
            if f.endswith('.json')
        ]
    
    return HealthResponse(
        status="healthy" if text_to_speech is not None else "unhealthy",
        model_loaded=text_to_speech is not None,
        default_voice="M1.json",
        available_voices=sorted(available_voices)
    )


@app.post("/synthesize", response_model=SynthesisResponse)
async def synthesize(request: SynthesisRequest):
    """
    Synthesize speech from text
    
    Parameters:
    - text: Text to synthesize
    - voice_style: Optional voice style file (e.g., "M1.json", "F2.json")
    - total_step: Number of denoising steps (higher = better quality, slower)
    - speed: Speech speed factor (higher = faster)
    
    Returns:
    - Base64-encoded WAV audio file
    """
    if text_to_speech is None:
        raise HTTPException(status_code=503, detail="TTS model not loaded")
    
    try:
        # Load voice style
        if request.voice_style:
            voice_path = os.path.join("assets/voice_styles", request.voice_style)
            if not os.path.exists(voice_path):
                raise HTTPException(
                    status_code=404,
                    detail=f"Voice style not found: {request.voice_style}"
                )
            voice_style = load_voice_style([voice_path], verbose=False)
        else:
            voice_style = default_voice_style
        
        # Synthesize
        logger.info(f"Synthesizing: '{request.text[:50]}...' (step={request.total_step}, speed={request.speed})")
        wav, duration = text_to_speech(
            request.text,
            voice_style,
            request.total_step,
            request.speed
        )
        
        # Trim to actual duration
        sample_rate = text_to_speech.sample_rate
        wav_trimmed = wav[0, :int(sample_rate * duration[0].item())]
        
        # Convert to WAV bytes
        wav_buffer = io.BytesIO()
        sf.write(wav_buffer, wav_trimmed, sample_rate, format='WAV')
        wav_bytes = wav_buffer.getvalue()
        
        # Encode to base64
        audio_base64 = base64.b64encode(wav_bytes).decode('utf-8')
        
        logger.info(f"Synthesis completed: {duration[0].item():.2f}s audio generated")
        
        return SynthesisResponse(
            audio_base64=audio_base64,
            duration=float(duration[0].item()),
            sample_rate=sample_rate,
            text=request.text
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Synthesis error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/batch", response_model=BatchSynthesisResponse)
async def batch_synthesize(batch_request: BatchSynthesisRequest):
    """
    Batch synthesize multiple texts
    
    Parameters:
    - requests: List of synthesis requests
    
    Returns:
    - List of base64-encoded WAV audio files
    """
    if text_to_speech is None:
        raise HTTPException(status_code=503, detail="TTS model not loaded")
    
    try:
        requests = batch_request.requests
        if not requests:
            raise HTTPException(status_code=400, detail="Empty batch request")
        
        # Prepare batch data
        texts = [req.text for req in requests]
        voice_paths = []
        
        for req in requests:
            if req.voice_style:
                voice_path = os.path.join("assets/voice_styles", req.voice_style)
                if not os.path.exists(voice_path):
                    raise HTTPException(
                        status_code=404,
                        detail=f"Voice style not found: {req.voice_style}"
                    )
            else:
                voice_path = "assets/voice_styles/M1.json"
            voice_paths.append(voice_path)
        
        # Load voice styles
        voice_style = load_voice_style(voice_paths, verbose=False)
        
        # Use common parameters from first request
        total_step = requests[0].total_step
        speed = requests[0].speed
        
        logger.info(f"Batch synthesis: {len(texts)} texts")
        
        # Batch synthesize
        wav, duration = text_to_speech.batch(texts, voice_style, total_step, speed)
        
        # Process results
        results = []
        sample_rate = text_to_speech.sample_rate
        
        for i, (text, dur) in enumerate(zip(texts, duration)):
            wav_trimmed = wav[i, :int(sample_rate * dur.item())]
            
            # Convert to WAV bytes
            wav_buffer = io.BytesIO()
            sf.write(wav_buffer, wav_trimmed, sample_rate, format='WAV')
            wav_bytes = wav_buffer.getvalue()
            
            # Encode to base64
            audio_base64 = base64.b64encode(wav_bytes).decode('utf-8')
            
            results.append(SynthesisResponse(
                audio_base64=audio_base64,
                duration=float(dur.item()),
                sample_rate=sample_rate,
                text=text
            ))
        
        logger.info(f"Batch synthesis completed: {len(results)} results")
        
        return BatchSynthesisResponse(results=results)
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Batch synthesis error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/")
async def root():
    """Root endpoint with API information"""
    return {
        "service": "Supertonic TTS API",
        "version": "1.0.0",
        "endpoints": {
            "health": "/health",
            "synthesize": "/synthesize",
            "batch": "/batch",
            "docs": "/docs"
        }
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8765)
