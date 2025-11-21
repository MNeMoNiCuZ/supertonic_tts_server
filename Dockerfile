# Dockerfile for Supertonic TTS Service
FROM python:3.10-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements-server.txt .
RUN pip install --no-cache-dir -r requirements-server.txt

# Copy application files
COPY py/helper.py ./py/
COPY server.py .

# Copy assets (models and voice styles)
COPY assets ./assets

# Create results directory
RUN mkdir -p /app/results

# Create non-root user
RUN useradd -m -u 1000 ttsuser && \
    chown -R ttsuser:ttsuser /app
USER ttsuser

# Expose port
EXPOSE 8765

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:8765/health')" || exit 1

# Run the server
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8765"]
