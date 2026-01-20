#!/usr/bin/env python3
"""
Mute Backend - WebSocket server for speech-to-text transcription
supporting multiple ASR models (Parakeet TDT v3 and OpenAI Whisper).
"""

import asyncio
import argparse
import json
import base64
import signal
import sys
import os
import subprocess
import logging
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Optional, Dict, Any
import time
import numpy as np
import weakref

# Setup logging with both console and file output
def setup_logging():
    """Configure logging with console and persistent file output."""
    log_format = '%(asctime)s - %(levelname)s - %(message)s'

    # Create logger
    logger = logging.getLogger(__name__)
    logger.setLevel(logging.INFO)

    # Console handler (stdout)
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(logging.INFO)
    console_handler.setFormatter(logging.Formatter(log_format))
    logger.addHandler(console_handler)

    # File handler with rotation
    try:
        log_dir = Path.home() / "Library" / "Application Support" / "Mute"
        log_dir.mkdir(parents=True, exist_ok=True)
        log_file = log_dir / "backend.log"

        # RotatingFileHandler: 5MB max, keep 3 backup files
        file_handler = RotatingFileHandler(
            log_file,
            maxBytes=5 * 1024 * 1024,  # 5 MB
            backupCount=3,
            encoding='utf-8'
        )
        file_handler.setLevel(logging.INFO)
        file_handler.setFormatter(logging.Formatter(log_format))
        logger.addHandler(file_handler)

        logger.info(f"Logging to file: {log_file}")
    except Exception as e:
        logger.warning(f"Could not setup file logging: {e}")

    return logger

logger = setup_logging()

try:
    import websockets
    from websockets.server import serve
except ImportError:
    logger.error("websockets not installed. Run: pip install websockets")
    sys.exit(1)

from asr_engine import ASREngine
from whisper_engine import WhisperEngine, WHISPER_AVAILABLE
from model_manager import ModelManager
from diarization_engine import DiarizationEngine, PYANNOTE_AVAILABLE


# =============================================================================
# Client Session - Per-client isolated state
# =============================================================================
class ClientSession:
    """Per-client session state for isolation between concurrent clients."""

    # Memory limits
    MAX_BUFFER_SECONDS = 300  # 5 minutes max recording
    MAX_BUFFER_SAMPLES = 16000 * MAX_BUFFER_SECONDS  # ~19.2 million samples

    def __init__(self, websocket, server: 'MuteServer'):
        self.websocket = websocket
        self.server = server
        self.session_id = id(websocket)

        # Recording state (isolated per client)
        self.is_recording = False
        self.audio_chunks: list[np.ndarray] = []  # Efficient numpy storage
        self.total_samples = 0  # Track total without concatenating
        self.current_settings = {}
        self.continuous_mode = False
        self._last_partial_text = ""
        self._last_log_second = 0

        # Model state for this session
        self.active_engine = None
        self.active_model = None

        # Interval transcription state
        self.has_done_first_interval = False

        # Diarization state
        self.diarization_enabled = False

        # Async lock for this session
        self.lock = asyncio.Lock()

        # Audio watchdog state (detect stuck recordings with no audio)
        self.audio_watchdog_task: Optional[asyncio.Task] = None
        self.first_audio_received = False

        logger.info(f"[Session {self.session_id}] Created new client session")

    def add_audio(self, audio_samples: np.ndarray) -> bool:
        """
        Add audio samples to buffer efficiently.

        Returns:
            True if audio was added, False if buffer is full
        """
        new_total = self.total_samples + len(audio_samples)

        # Check memory limit
        if new_total > self.MAX_BUFFER_SAMPLES:
            logger.warning(f"[Session {self.session_id}] Audio buffer limit reached "
                          f"({self.total_samples}/{self.MAX_BUFFER_SAMPLES} samples)")
            return False

        # Store as numpy array directly (no conversion to list)
        self.audio_chunks.append(audio_samples)
        self.total_samples = new_total
        return True

    def get_audio_array(self) -> np.ndarray:
        """Get all audio as a single numpy array."""
        if not self.audio_chunks:
            return np.array([], dtype=np.float32)
        return np.concatenate(self.audio_chunks)

    def clear_audio(self):
        """Clear audio buffer."""
        self.audio_chunks = []
        self.total_samples = 0

    def keep_audio_tail(self, seconds: float):
        """Keep only the last N seconds of audio (for context)."""
        samples_to_keep = int(16000 * seconds)

        if self.total_samples <= samples_to_keep:
            return  # Nothing to trim

        # Get full audio and keep tail
        full_audio = self.get_audio_array()
        tail_audio = full_audio[-samples_to_keep:]

        # Reset with just the tail
        self.audio_chunks = [tail_audio]
        self.total_samples = len(tail_audio)

        logger.info(f"[Session {self.session_id}] Kept {seconds:.1f}s context "
                   f"({self.total_samples} samples)")

    def get_buffer_seconds(self) -> float:
        """Get current buffer duration in seconds."""
        return self.total_samples / 16000

    def cleanup(self):
        """Clean up session resources."""
        logger.info(f"[Session {self.session_id}] Cleaning up session")
        self.clear_audio()
        if self.active_engine:
            self.active_engine.end_session()
        self.is_recording = False


def kill_process_on_port(port: int):
    """Kill any existing process using the specified port."""
    try:
        # Find PID using lsof
        result = subprocess.run(
            ['lsof', '-ti', f':{port}'],
            capture_output=True,
            text=True
        )
        if result.stdout.strip():
            pids = result.stdout.strip().split('\n')
            current_pid = str(os.getpid())
            for pid in pids:
                if pid and pid != current_pid:
                    logger.info(f"Killing existing process {pid} on port {port}")
                    try:
                        os.kill(int(pid), signal.SIGKILL)
                    except (ProcessLookupError, PermissionError) as e:
                        logger.warning(f"Could not kill process {pid}: {e}")
            # Give the OS time to release the port
            time.sleep(0.5)
    except Exception as e:
        logger.warning(f"Could not check for existing processes on port {port}: {e}")


class MuteServer:
    """WebSocket server for Mute."""

    # Model identifiers
    MODEL_PARAKEET = "parakeet"
    # Use actual Whisper model names
    WHISPER_MODELS = ["base", "large-v3-turbo"]

    def __init__(self, port: int = 9877):
        self.port = port
        self.model_manager = ModelManager()
        self.clients: set = set()
        self.sessions: Dict[int, ClientSession] = {}  # websocket id -> session
        self.start_time = time.time()
        self.is_shutting_down = False

        # Global lock for model operations (loading/unloading)
        self.model_lock = asyncio.Lock()

        # Multi-model support (shared across clients)
        self.engines: Dict[str, Any] = {}  # model_id -> engine instance
        self.default_model: str = self.MODEL_PARAKEET  # Default model
        self.loaded_models: set = set()  # Track which models are loaded

        # Speaker diarization (shared engine)
        self.diarization_engine: Optional[DiarizationEngine] = None

        # Keep-warm settings (eager model loading)
        self.keep_warm_enabled: bool = False
        self.keep_warm_models: set = set()  # Which models to keep warm
        self.keep_warm_duration: str = "4h"  # "1h", "4h", "8h", "16h", "permanent"
        self.last_inference_time: Dict[str, float] = {}
        self.keep_warm_task: Optional[asyncio.Task] = None
        
    async def start(self):
        """Start the WebSocket server."""
        # Kill any existing process on this port first
        kill_process_on_port(self.port)

        logger.info(f"Starting Mute server on port {self.port}")
        self.start_time = time.time()

        # Check if Parakeet model is available and load it
        if self.model_manager.is_model_downloaded():
            logger.info("Parakeet model found, loading...")
            await self.load_model(self.MODEL_PARAKEET)
        else:
            logger.info("Parakeet model not downloaded yet")

        # Log Whisper availability
        if WHISPER_AVAILABLE:
            logger.info("Whisper is available for use")
        else:
            logger.info("Whisper is not installed")

        # Start WebSocket server with SO_REUSEADDR and keep-alive pings
        try:
            self.server = await serve(
                self.handle_client,
                "localhost",
                self.port,
                reuse_address=True,
                ping_interval=30,  # Send ping every 30 seconds
                ping_timeout=30,   # Close if no pong within 30 seconds
            )
            logger.info(f"Server running at ws://localhost:{self.port}/ws")

            # Wait until shutdown is requested
            while not self.is_shutting_down:
                await asyncio.sleep(1)

            # Graceful shutdown
            await self.shutdown()

        except OSError as e:
            if e.errno == 48:  # Address already in use
                logger.error(f"Port {self.port} is still in use. Retrying after cleanup...")
                kill_process_on_port(self.port)
                time.sleep(1)
                # Retry once
                self.server = await serve(
                    self.handle_client,
                    "localhost",
                    self.port,
                    reuse_address=True,
                    ping_interval=30,
                    ping_timeout=30,
                )
                logger.info(f"Server running at ws://localhost:{self.port}/ws (retry)")

                while not self.is_shutting_down:
                    await asyncio.sleep(1)

                await self.shutdown()
            else:
                raise

    async def shutdown(self):
        """Gracefully shut down the server."""
        logger.info("=== GRACEFUL SHUTDOWN INITIATED ===")

        # Stop keep-warm monitor
        if self.keep_warm_task and not self.keep_warm_task.done():
            self.keep_warm_task.cancel()
            try:
                await self.keep_warm_task
            except asyncio.CancelledError:
                pass
            logger.info("Keep-warm monitor stopped")

        # Stop all active recordings and clean up sessions
        for session_id, session in list(self.sessions.items()):
            try:
                if session.is_recording:
                    logger.info(f"[Session {session_id}] Stopping active recording")
                    async with session.lock:
                        session.is_recording = False
                        if session.active_engine:
                            session.active_engine.end_session()
                session.cleanup()
            except Exception as e:
                logger.error(f"[Session {session_id}] Error during cleanup: {e}")

        self.sessions.clear()

        # Close all client connections
        for client in list(self.clients):
            try:
                await client.close(1001, "Server shutting down")
            except Exception:
                pass
        self.clients.clear()
        logger.info("All client connections closed")

        # Unload all models
        async with self.model_lock:
            for model_id in list(self.loaded_models):
                try:
                    logger.info(f"Unloading model: {model_id}")
                    if model_id in self.engines:
                        engine = self.engines[model_id]
                        if hasattr(engine, 'unload'):
                            engine.unload()
                        del self.engines[model_id]
                    self.loaded_models.discard(model_id)
                except Exception as e:
                    logger.error(f"Error unloading model {model_id}: {e}")

        logger.info("All models unloaded")

        # Close the server
        if hasattr(self, 'server') and self.server:
            self.server.close()
            await self.server.wait_closed()
            logger.info("WebSocket server closed")

        logger.info("=== SHUTDOWN COMPLETE ===")

    async def load_model(self, model_id: str):
        """Load a specific ASR model. Caller should hold model_lock if needed."""
        logger.info(f"Loading model: {model_id}")

        # Check if already loaded
        if model_id in self.loaded_models:
            logger.info(f"Model {model_id} already loaded")
            return

        try:
            if model_id == self.MODEL_PARAKEET:
                # Load Parakeet model
                model_path = self.model_manager.get_model_path()
                if not model_path:
                    raise RuntimeError("Parakeet model not downloaded")
                engine = ASREngine(model_path)
                await engine.load_model()
                self.engines[model_id] = engine
                self.loaded_models.add(model_id)
                logger.info("Parakeet model loaded successfully")

            elif model_id in self.WHISPER_MODELS:
                # Load Whisper model
                if not WHISPER_AVAILABLE:
                    raise RuntimeError("Whisper is not installed")
                engine = WhisperEngine(model_id)
                await engine.load_model()
                self.engines[model_id] = engine
                self.loaded_models.add(model_id)
                logger.info(f"Whisper {model_id} model loaded successfully")

            else:
                raise RuntimeError(f"Unknown model: {model_id}")

            # Set as default if it's the first loaded model
            if self.default_model == self.MODEL_PARAKEET and model_id in self.loaded_models:
                if len(self.loaded_models) == 1:
                    self.default_model = model_id

        except Exception as e:
            logger.error(f"Failed to load model {model_id}: {e}")
            raise

    def get_available_models(self) -> list:
        """Get list of available models with their status."""
        models = []

        # Parakeet
        parakeet_downloaded = self.model_manager.is_model_downloaded()
        parakeet_loaded = self.MODEL_PARAKEET in self.loaded_models
        models.append({
            "id": self.MODEL_PARAKEET,
            "name": "NVIDIA Parakeet TDT v3",
            "description": "High-quality multilingual transcription (25 languages)",
            "size": "~2.5 GB",
            "downloaded": parakeet_downloaded,
            "loaded": parakeet_loaded,
            "available": parakeet_downloaded,
        })

        # Whisper models - use actual Whisper model names
        whisper_info = {
            "base": ("Whisper Base", "142 MB", "Good balance of speed and accuracy"),
            "large-v3-turbo": ("Whisper Large v3 Turbo", "1.5 GB", "Fast and accurate"),
        }

        # Check which models are cached
        import os
        cache_dir = os.path.expanduser("~/.cache/whisper")
        cached_models = set()
        if os.path.exists(cache_dir):
            for f in os.listdir(cache_dir):
                if f.endswith(".pt"):
                    # Remove .pt extension to get model name
                    cached_models.add(f[:-3])

        for model_id in self.WHISPER_MODELS:
            name, size, desc = whisper_info.get(model_id, (f"Whisper {model_id}", "Unknown", ""))
            loaded = model_id in self.loaded_models
            is_cached = model_id in cached_models
            models.append({
                "id": model_id,
                "name": name,
                "description": desc,
                "size": size,
                "downloaded": is_cached,
                "loaded": loaded,
                "available": WHISPER_AVAILABLE,
            })

        return models
    
    async def handle_client(self, websocket):
        """Handle a WebSocket client connection."""
        # Create per-client session
        session = ClientSession(websocket, self)
        session_id = session.session_id

        self.clients.add(websocket)
        self.sessions[session_id] = session
        logger.info(f"[Session {session_id}] Client connected. Total clients: {len(self.clients)}")

        try:
            # Send initial status
            await self.send_status(websocket)

            async for message in websocket:
                if self.is_shutting_down:
                    break
                await self.handle_message(websocket, session, message)

        except websockets.exceptions.ConnectionClosed:
            logger.info(f"[Session {session_id}] Client disconnected")
        except Exception as e:
            logger.error(f"[Session {session_id}] Error handling client: {e}")
            import traceback
            traceback.print_exc()
        finally:
            # Clean up session
            session.cleanup()
            self.sessions.pop(session_id, None)
            self.clients.discard(websocket)
            logger.info(f"[Session {session_id}] Session cleaned up. Remaining clients: {len(self.clients)}")
    
    async def send_status(self, websocket):
        """Send current status to client."""
        # Check if any model is loaded and ready
        any_model_loaded = len(self.loaded_models) > 0
        parakeet_loaded = self.MODEL_PARAKEET in self.loaded_models

        await websocket.send(json.dumps({
            "type": "ready",
            "model_loaded": any_model_loaded,
            "parakeet_loaded": parakeet_loaded,
            "whisper_available": WHISPER_AVAILABLE,
            "active_model": self.default_model,
            "loaded_models": list(self.loaded_models),
        }))
    
    async def handle_message(self, websocket, session: ClientSession, message: str):
        """Handle incoming WebSocket message."""
        try:
            data = json.loads(message)
            msg_type = data.get("type", "")

            if msg_type == "ping":
                await websocket.send(json.dumps({"type": "pong"}))

            elif msg_type == "start":
                await self.handle_start(websocket, session, data.get("settings", {}))

            elif msg_type == "audio":
                await self.handle_audio(websocket, session, data)

            elif msg_type == "stop":
                await self.handle_stop(websocket, session)

            elif msg_type == "download_model":
                await self.handle_download_model(websocket)

            elif msg_type == "clear_cache":
                await self.handle_clear_cache(websocket)

            elif msg_type == "get_models":
                await self.handle_get_models(websocket)

            elif msg_type == "load_model":
                await self.handle_load_model(websocket, data.get("model", ""))

            elif msg_type == "transcribe_interval":
                await self.handle_transcribe_interval(websocket, session)

            elif msg_type == "set_keep_warm":
                await self.handle_set_keep_warm(websocket, data.get("models", []), data.get("duration", "4h"))

            else:
                logger.warning(f"[Session {session.session_id}] Unknown message type: {msg_type}")

        except json.JSONDecodeError:
            logger.error(f"[Session {session.session_id}] Invalid JSON message: {message[:100]}")
        except Exception as e:
            logger.error(f"[Session {session.session_id}] Error handling message: {e}")
            import traceback
            traceback.print_exc()
            await self.send_error(websocket, str(e))
    
    async def handle_start(self, websocket, session: ClientSession, settings: dict):
        """Handle start recording command."""
        logger.info(f"[Session {session.session_id}] === STARTING RECORDING ===")
        logger.info(f"[Session {session.session_id}] Settings received: {settings}")

        async with session.lock:
            # Get requested model from settings
            requested_model = settings.get("model", self.default_model)

            # Check if the requested model is loaded (with model lock)
            async with self.model_lock:
                if requested_model not in self.engines:
                    # Try to load the model on-demand with retry
                    max_retries = 2
                    last_error = None
                    for attempt in range(max_retries):
                        try:
                            if attempt > 0:
                                logger.info(f"[Session {session.session_id}] Retry {attempt} loading model {requested_model}")
                                # Force garbage collection before retry
                                import gc
                                gc.collect()
                                await asyncio.sleep(1)  # Brief pause before retry
                            await self.load_model(requested_model)
                            await websocket.send(json.dumps({
                                "type": "model_loaded",
                                "model": requested_model
                            }))
                            last_error = None
                            break
                        except Exception as e:
                            last_error = e
                            logger.error(f"[Session {session.session_id}] Model load attempt {attempt + 1} failed: {e}")

                    if last_error:
                        await self.send_error(websocket, f"Model '{requested_model}' not available after {max_retries} attempts: {last_error}")
                        return

                # Get engine reference
                engine = self.engines.get(requested_model)

            if not engine or not engine.is_loaded:
                await self.send_error(websocket, f"Model '{requested_model}' not loaded")
                return

            # Set session state
            session.active_engine = engine
            session.active_model = requested_model
            session.is_recording = True
            session.clear_audio()
            session.current_settings = settings
            session.continuous_mode = settings.get("continuous_mode", False)
            session._last_partial_text = ""
            session.has_done_first_interval = False

            # Speaker diarization
            session.diarization_enabled = settings.get("enable_diarization", False)
            logger.info(f"[Session {session.session_id}] Diarization enabled: {session.diarization_enabled}")

            if session.diarization_enabled and PYANNOTE_AVAILABLE:
                if self.diarization_engine is None:
                    model_dir = os.path.join(os.path.dirname(__file__), "models", "diarization")
                    logger.info(f"[Session {session.session_id}] Creating DiarizationEngine")
                    self.diarization_engine = DiarizationEngine(model_dir)
                if not self.diarization_engine.is_loaded:
                    logger.info(f"[Session {session.session_id}] Loading diarization model on-demand...")
                    try:
                        await self.diarization_engine.load_model()
                    except Exception as e:
                        logger.error(f"[Session {session.session_id}] Failed to load diarization model: {e}")
                        session.diarization_enabled = False

            # Start ASR engine session
            session.active_engine.start_session()

            logger.info(f"[Session {session.session_id}] Recording started with model: {requested_model}, "
                       f"continuous_mode: {session.continuous_mode}, diarization: {session.diarization_enabled}")

        # Send recording_ready confirmation so client knows to start sending audio
        await websocket.send(json.dumps({
            "type": "recording_ready",
            "model": requested_model
        }))

        # Start audio watchdog - auto-cleanup if no audio received within timeout
        session.first_audio_received = False
        session.audio_watchdog_task = asyncio.create_task(
            self._audio_watchdog(websocket, session, timeout_seconds=5.0)
        )

    async def _audio_watchdog(self, websocket, session: ClientSession, timeout_seconds: float):
        """Watchdog task that auto-stops recording if no audio is received within timeout."""
        try:
            await asyncio.sleep(timeout_seconds)
            # If we get here, timeout elapsed - check if audio was received
            if session.is_recording and not session.first_audio_received:
                logger.warning(f"[Session {session.session_id}] No audio received after {timeout_seconds}s, auto-stopping recording")
                await self.send_error(websocket, "no_audio_timeout")
                # Cleanup the recording state
                async with session.lock:
                    session.is_recording = False
                    session.clear_audio()
                    if session.active_engine:
                        session.active_engine.end_session()
        except asyncio.CancelledError:
            # Watchdog was cancelled (audio received or recording stopped normally)
            pass
        except Exception as e:
            logger.error(f"[Session {session.session_id}] Audio watchdog error: {e}")

    async def handle_audio(self, websocket, session: ClientSession, data: dict):
        """Handle incoming audio chunk."""
        if not session.is_recording:
            return

        # Cancel audio watchdog on first audio received
        if not session.first_audio_received:
            session.first_audio_received = True
            if session.audio_watchdog_task and not session.audio_watchdog_task.done():
                session.audio_watchdog_task.cancel()
                logger.info(f"[Session {session.session_id}] Audio watchdog cancelled - audio flowing")

        try:
            # Decode base64 audio
            audio_b64 = data.get("data", "")
            audio_bytes = base64.b64decode(audio_b64)

            # Convert to float32 numpy array (keep as numpy, don't convert to list)
            audio_samples = np.frombuffer(audio_bytes, dtype=np.float32).copy()

            # Add to buffer with memory limit check
            async with session.lock:
                if not session.add_audio(audio_samples):
                    # Buffer full - stop recording
                    logger.warning(f"[Session {session.session_id}] Buffer limit reached, stopping recording")
                    await self.send_error(websocket, "Recording too long (max 5 minutes). Stopping.")
                    await self.handle_stop(websocket, session)
                    return

                buffer_seconds = session.get_buffer_seconds()

            # Log periodically (every ~2 seconds)
            if int(buffer_seconds) > 0 and int(buffer_seconds) != session._last_log_second:
                session._last_log_second = int(buffer_seconds)
                logger.info(f"[Session {session.session_id}] Recording: {buffer_seconds:.1f}s")

            # Incremental transcription for continuous mode
            if session.continuous_mode and session.active_engine:
                # Only transcribe every ~1.5 seconds of audio to avoid overloading
                if buffer_seconds >= 1.5 and (buffer_seconds % 1.5) < 0.1:
                    try:
                        async with session.lock:
                            audio_array = session.get_audio_array()
                        partial_text = await session.active_engine.transcribe_incremental(audio_array)
                        # Only send if text changed
                        if partial_text and partial_text != session._last_partial_text:
                            session._last_partial_text = partial_text
                            await websocket.send(json.dumps({
                                "type": "partial",
                                "text": partial_text,
                                "timestamp": int(buffer_seconds * 1000)
                            }))
                            logger.info(f"[Session {session.session_id}] Partial: '{partial_text[:50]}...'")
                    except Exception as e:
                        logger.error(f"[Session {session.session_id}] Incremental transcription error: {e}")

        except Exception as e:
            logger.error(f"[Session {session.session_id}] Error processing audio: {e}")
    
    async def handle_stop(self, websocket, session: ClientSession):
        """Handle stop recording command."""
        # Cancel audio watchdog if running
        if session.audio_watchdog_task and not session.audio_watchdog_task.done():
            session.audio_watchdog_task.cancel()

        async with session.lock:
            buffer_samples = session.total_samples
            buffer_seconds = session.get_buffer_seconds()
            logger.info(f"[Session {session.session_id}] Stopping recording. "
                       f"Buffer: {buffer_samples} samples ({buffer_seconds:.2f}s)")

            if not session.is_recording:
                logger.warning(f"[Session {session.session_id}] Stop called but not recording")
                return

            session.is_recording = False

            try:
                # Get final transcription
                if session.total_samples > 0 and session.active_engine:
                    audio_array = session.get_audio_array()
                    logger.info(f"[Session {session.session_id}] Transcribing {len(audio_array)} samples "
                               f"with {session.active_model}")

                    final_text = await session.active_engine.transcribe_final(audio_array)

                    # If final is empty but we have a last partial result, use that
                    if not final_text and session.active_engine.last_transcription:
                        logger.info(f"[Session {session.session_id}] Final was empty, using last partial")
                        final_text = session.active_engine.last_transcription

                    logger.info(f"[Session {session.session_id}] Final transcription: '{final_text}'")

                    await websocket.send(json.dumps({
                        "type": "final",
                        "text": final_text,
                        "timestamp": 0,
                        "model": session.active_model
                    }))
                else:
                    await websocket.send(json.dumps({
                        "type": "final",
                        "text": "",
                        "timestamp": 0
                    }))

                # Update last inference time for keep-warm tracking
                if session.active_model:
                    self.last_inference_time[session.active_model] = time.time()

            except Exception as e:
                logger.error(f"[Session {session.session_id}] Error in final transcription: {e}")
                import traceback
                traceback.print_exc()
                await self.send_error(websocket, str(e))
            finally:
                session.clear_audio()
                if session.active_engine:
                    session.active_engine.end_session()

    async def handle_transcribe_interval(self, websocket, session: ClientSession):
        """
        Handle interval transcription using sliding window with context skipping.

        Approach:
        1. Transcribe the full buffer (which includes ~2s context from previous interval)
        2. Use word timestamps to skip words in the first ~2 seconds (the overlap/context)
        3. Clear buffer except for last ~2 seconds (to be context for next interval)

        This ensures we have context for accurate word boundaries while avoiding duplicates.
        """
        async with session.lock:
            if not session.is_recording:
                logger.warning(f"[Session {session.session_id}] Interval transcription requested but not recording")
                return

            if session.total_samples == 0 or not session.active_engine:
                await websocket.send(json.dumps({
                    "type": "interval_transcription",
                    "text": "",
                    "is_final": False
                }))
                return

            try:
                buffer_seconds = session.get_buffer_seconds()
                context_seconds = 2.0  # How much context we keep between intervals
                logger.info(f"[Session {session.session_id}] === INTERVAL TRANSCRIPTION ===")
                logger.info(f"[Session {session.session_id}] Model: {session.active_model}, "
                           f"Buffer: {buffer_seconds:.1f}s, First: {not session.has_done_first_interval}")

                # Need at least 3 seconds to have meaningful new audio beyond context
                min_buffer = context_seconds + 1.0
                if buffer_seconds < min_buffer:
                    logger.info(f"[Session {session.session_id}] Buffer too short, waiting for more audio")
                    await websocket.send(json.dumps({
                        "type": "interval_transcription",
                        "text": "",
                        "is_final": False
                    }))
                    return

                # Get audio array (efficient - only concatenates here)
                audio_array = session.get_audio_array()

                # Check if engine supports word timestamps (needed for context skipping)
                words = []
                speakers = []

                if hasattr(session.active_engine, 'transcribe_with_timestamps'):
                    result = await session.active_engine.transcribe_with_timestamps(audio_array)
                    words = result.get("words", [])

                    # If this is NOT the first interval, skip words in the context window
                    if session.has_done_first_interval and words:
                        words = [w for w in words if w["start"] >= context_seconds - 0.5]
                        logger.info(f"[Session {session.session_id}] After context skip: {len(words)} words")

                    # Apply speaker diarization if enabled
                    if session.diarization_enabled and self.diarization_engine and self.diarization_engine.is_loaded and words:
                        logger.info(f"[Session {session.session_id}] Applying diarization...")
                        segments = await self.diarization_engine.diarize(audio_array)

                        if segments:
                            words = self.diarization_engine.assign_speakers_to_words(words, segments)
                            raw_speakers = [w.get("speaker", "Unknown") for w in words]
                            speaker_map = self.diarization_engine.format_speakers(raw_speakers)
                            for w in words:
                                raw_speaker = w.get("speaker", "Unknown")
                                w["speaker"] = speaker_map.get(raw_speaker, raw_speaker)
                            speakers = list(set(w["speaker"] for w in words))

                    # Format text
                    if speakers and len(speakers) > 1:
                        text = self._format_with_speakers(words)
                    else:
                        text = " ".join(w["word"] for w in words).strip()

                else:
                    # No word timestamps - fall back to simple approach
                    logger.warning(f"[Session {session.session_id}] No word timestamp support")
                    text = await session.active_engine.transcribe_final(audio_array)
                    text = text.strip() if text else ""

                if text:
                    logger.info(f"[Session {session.session_id}] Result: '{text[:80]}...' " if len(text) > 80 else f"[Session {session.session_id}] Result: '{text}'")

                # Send the transcription
                await websocket.send(json.dumps({
                    "type": "interval_transcription",
                    "text": text,
                    "speakers": speakers,
                    "is_final": False
                }))

                # Mark that we've done at least one interval
                session.has_done_first_interval = True

                # Update last inference time for keep-warm tracking
                if session.active_model:
                    self.last_inference_time[session.active_model] = time.time()

                # Keep last ~2 seconds for context
                session.keep_audio_tail(context_seconds)

            except Exception as e:
                logger.error(f"[Session {session.session_id}] Interval transcription error: {e}")
                import traceback
                traceback.print_exc()
                await self.send_error(websocket, str(e))

    def _format_with_speakers(self, words: list) -> str:
        """
        Format transcription with speaker labels.
        Groups consecutive words by speaker.

        Args:
            words: List of word dicts with "word" and "speaker" keys

        Returns:
            Formatted string like "Speaker 1: Hello. Speaker 2: Hi there."
        """
        if not words:
            return ""

        result = []
        current_speaker = None

        for word_info in words:
            speaker = word_info.get("speaker", "Unknown")
            word = word_info.get("word", "")

            if speaker != current_speaker:
                if current_speaker is not None:
                    result.append("\n")  # New line for new speaker
                result.append(f"{speaker}: ")
                current_speaker = speaker

            result.append(word + " ")

        return "".join(result).strip()

    async def _handle_simple_interval_transcription(self, websocket):
        """Fallback for engines without word timestamp support - not recommended for continuous capture."""
        # This is a simple fallback that just transcribes new audio without overlap
        # It may cut words at boundaries, but avoids the duplicate issue
        buffer_seconds = len(self.audio_buffer) / 16000

        audio_array = np.array(self.audio_buffer, dtype=np.float32)
        text = await self.active_engine.transcribe_final(audio_array)

        await websocket.send(json.dumps({
            "type": "interval_transcription",
            "text": text,
            "is_final": False
        }))

    async def handle_download_model(self, websocket):
        """Handle Parakeet model download request."""
        logger.info("Starting Parakeet model download")

        try:
            async for progress in self.model_manager.download_model_async():
                await websocket.send(json.dumps({
                    "type": "model_progress",
                    "percent": progress
                }))

            await websocket.send(json.dumps({
                "type": "model_downloaded"
            }))

            # Load the Parakeet model
            await self.load_model(self.MODEL_PARAKEET)

            if self.MODEL_PARAKEET in self.loaded_models:
                await websocket.send(json.dumps({
                    "type": "model_loaded",
                    "model": self.MODEL_PARAKEET
                }))
            else:
                await websocket.send(json.dumps({
                    "type": "model_error",
                    "message": "Failed to load model after download"
                }))

        except Exception as e:
            logger.error(f"Model download failed: {e}")
            await websocket.send(json.dumps({
                "type": "model_error",
                "message": str(e)
            }))

    async def handle_get_models(self, websocket):
        """Handle get available models request."""
        models = self.get_available_models()
        await websocket.send(json.dumps({
            "type": "models_list",
            "models": models,
            "active_model": self.default_model
        }))

    async def handle_load_model(self, websocket, model_id: str):
        """Handle load specific model request."""
        logger.info(f"Loading model on request: {model_id}")

        if not model_id:
            await self.send_error(websocket, "Model ID not specified")
            return

        # Check if it's a valid model
        valid_models = [self.MODEL_PARAKEET] + self.WHISPER_MODELS
        if model_id not in valid_models:
            await self.send_error(websocket, f"Unknown model: {model_id}")
            return

        try:
            async with self.model_lock:
                # Check if already loaded
                if model_id in self.loaded_models:
                    await websocket.send(json.dumps({
                        "type": "model_loaded",
                        "model": model_id
                    }))
                    return

                # Load the model
                await self.load_model(model_id)

            await websocket.send(json.dumps({
                "type": "model_loaded",
                "model": model_id
            }))

        except Exception as e:
            logger.error(f"Failed to load model {model_id}: {e}")
            await websocket.send(json.dumps({
                "type": "model_error",
                "message": str(e),
                "model": model_id
            }))
    
    async def handle_clear_cache(self, websocket):
        """Handle cache clear request (clears Parakeet cache only)."""
        logger.info("Clearing Parakeet model cache")

        async with self.model_lock:
            # Unload Parakeet model if loaded
            if self.MODEL_PARAKEET in self.engines:
                self.engines[self.MODEL_PARAKEET].unload()
                del self.engines[self.MODEL_PARAKEET]
                self.loaded_models.discard(self.MODEL_PARAKEET)

            # If default model was Parakeet, switch to first available
            if self.default_model == self.MODEL_PARAKEET:
                if self.engines:
                    self.default_model = next(iter(self.engines))
                # else keep Parakeet as default (will need to be downloaded again)

            # Clear Parakeet cache
            self.model_manager.clear_cache()

        await self.send_status(websocket)

    async def handle_set_keep_warm(self, websocket, models: list, duration: str):
        """Handle set_keep_warm message to enable/disable eager model loading."""
        logger.info(f"Setting keep-warm: models={models}, duration={duration}")

        self.keep_warm_models = set(models)  # Store which models to keep warm
        self.keep_warm_enabled = len(models) > 0
        self.keep_warm_duration = duration

        if self.keep_warm_enabled:
            # Start keep-warm monitor if not already running
            if self.keep_warm_task is None or self.keep_warm_task.done():
                self.keep_warm_task = asyncio.create_task(self._keep_warm_monitor())
                logger.info("Started keep-warm monitor task")

            # Eagerly load all specified models
            for model_id in models:
                async with self.model_lock:
                    if model_id in self.loaded_models:
                        continue

                    try:
                        # Check if model can be loaded
                        if model_id == self.MODEL_PARAKEET:
                            if not self.model_manager.is_model_downloaded():
                                logger.info(f"Skipping {model_id} - not downloaded")
                                continue
                        elif model_id in self.WHISPER_MODELS:
                            if not WHISPER_AVAILABLE:
                                logger.info(f"Skipping {model_id} - Whisper not available")
                                continue
                        else:
                            logger.warning(f"Unknown model {model_id}, skipping")
                            continue

                        logger.info(f"Eagerly loading {model_id} for keep-warm")
                        await self.load_model(model_id)
                        # Update inference time so it doesn't immediately unload
                        self.last_inference_time[model_id] = time.time()

                    except Exception as e:
                        logger.error(f"Failed to eagerly load {model_id}: {e}")
                        continue

                # Notify client that model is loaded (outside lock)
                await websocket.send(json.dumps({
                    "type": "model_loaded",
                    "model": model_id
                }))
        else:
            # Stop keep-warm monitor
            if self.keep_warm_task and not self.keep_warm_task.done():
                self.keep_warm_task.cancel()
                try:
                    await self.keep_warm_task
                except asyncio.CancelledError:
                    pass
                self.keep_warm_task = None
                logger.info("Stopped keep-warm monitor task")

        # Send confirmation
        await websocket.send(json.dumps({
            "type": "keep_warm_updated",
            "models": list(self.keep_warm_models),
            "duration": self.keep_warm_duration
        }))

    async def _keep_warm_monitor(self):
        """Background task that monitors model idle time and unloads idle models."""
        logger.info("Keep-warm monitor started")

        while self.keep_warm_enabled:
            try:
                await asyncio.sleep(60)  # Check every 60 seconds

                if not self.keep_warm_enabled:
                    break

                # Skip if duration is permanent
                if self.keep_warm_duration == "permanent":
                    continue

                duration_seconds = self._get_duration_seconds(self.keep_warm_duration)
                current_time = time.time()

                # Check each loaded model for idle timeout
                models_to_unload = []
                for model_id in list(self.loaded_models):
                    last_used = self.last_inference_time.get(model_id, current_time)
                    idle_time = current_time - last_used

                    if idle_time > duration_seconds:
                        logger.info(f"Model {model_id} idle for {idle_time:.0f}s (limit: {duration_seconds}s), marking for unload")
                        models_to_unload.append(model_id)

                # Unload idle models
                for model_id in models_to_unload:
                    await self._unload_model(model_id)

            except asyncio.CancelledError:
                logger.info("Keep-warm monitor cancelled")
                break
            except Exception as e:
                logger.error(f"Error in keep-warm monitor: {e}")

        logger.info("Keep-warm monitor stopped")

    async def _unload_model(self, model_id: str):
        """Unload a model and notify clients."""
        async with self.model_lock:
            if model_id not in self.engines:
                return

            logger.info(f"Unloading model: {model_id}")

            try:
                # Unload the engine
                engine = self.engines[model_id]
                if hasattr(engine, 'unload'):
                    engine.unload()

                # Remove from tracking
                del self.engines[model_id]
                self.loaded_models.discard(model_id)
                self.last_inference_time.pop(model_id, None)

                # If this was the default model, switch to first available
                if self.default_model == model_id:
                    if self.engines:
                        self.default_model = next(iter(self.engines))
                    # else keep current default (will need to be reloaded)

                logger.info(f"Model {model_id} unloaded successfully")

            except Exception as e:
                logger.error(f"Error unloading model {model_id}: {e}")

        # Notify all clients (outside lock)
        message = json.dumps({
            "type": "model_unloaded",
            "model": model_id
        })
        for client in self.clients:
            try:
                await client.send(message)
            except Exception:
                pass

    def _get_duration_seconds(self, duration: str) -> int:
        """Convert duration string to seconds."""
        duration_map = {
            "1h": 3600,
            "4h": 14400,
            "8h": 28800,
            "16h": 57600,
            "permanent": float('inf')
        }
        return duration_map.get(duration, 14400)  # Default to 4h
    
    async def send_error(self, websocket, message: str):
        """Send error message to client."""
        try:
            await websocket.send(json.dumps({
                "type": "error",
                "message": message
            }))
        except:
            pass


def main():
    parser = argparse.ArgumentParser(description="Mute Backend Server")
    parser.add_argument("--port", type=int, default=9877, help="WebSocket server port")
    args = parser.parse_args()

    server = MuteServer(port=args.port)

    # Handle shutdown gracefully
    def signal_handler(sig, frame):
        logger.info(f"Received signal {sig}, initiating graceful shutdown...")
        server.is_shutting_down = True

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Run server
    try:
        asyncio.run(server.start())
    except KeyboardInterrupt:
        logger.info("Keyboard interrupt received")
    finally:
        logger.info("Server process exiting")


if __name__ == "__main__":
    main()
