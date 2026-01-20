#!/usr/bin/env python3
"""
Whisper Engine - Speech recognition using OpenAI Whisper model.
"""

import logging
import asyncio
from typing import Optional
import numpy as np

logger = logging.getLogger(__name__)

# Try to import whisper
WHISPER_AVAILABLE = False

try:
    import whisper
    WHISPER_AVAILABLE = True
    logger.info("OpenAI Whisper is available")
except ImportError:
    logger.warning("OpenAI Whisper not installed. Run: pip install openai-whisper")


class WhisperEngine:
    """Speech recognition engine using OpenAI Whisper."""

    SAMPLE_RATE = 16000  # Whisper expects 16kHz audio

    def __init__(self, model_name: str = "base"):
        """
        Initialize WhisperEngine.

        Args:
            model_name: Any valid Whisper model name (tiny, base, small, medium,
                       large-v3, large-v3-turbo, turbo, etc.)
        """
        # Validate against actual available models if whisper is installed
        if WHISPER_AVAILABLE:
            available = whisper.available_models()
            if model_name not in available:
                logger.warning(f"Model '{model_name}' not in available models: {available}")
                logger.warning("Defaulting to 'base'")
                model_name = "base"

        self.model_size = model_name
        self.model = None
        self.is_loaded = False
        self.device = "cpu"

        # Session state
        self.session_active = False
        self.last_transcription = ""

        # Determine device
        try:
            import torch
            if torch.cuda.is_available():
                self.device = "cuda"
                logger.info("Using CUDA GPU for Whisper inference")
            elif torch.backends.mps.is_available():
                # Whisper has issues with MPS, use CPU for now
                self.device = "cpu"
                logger.info("MPS available but using CPU for Whisper (better compatibility)")
            else:
                self.device = "cpu"
                logger.info("Using CPU for Whisper inference")
        except ImportError:
            self.device = "cpu"
            logger.info("PyTorch not available, using CPU")

    async def load_model(self):
        """Load the Whisper model."""
        if not WHISPER_AVAILABLE:
            raise RuntimeError("OpenAI Whisper is not installed")

        logger.info(f"Loading Whisper model: {self.model_size}")

        try:
            # Run model loading in thread pool to not block event loop
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(None, self._load_model_sync)

            self.is_loaded = True
            logger.info(f"Whisper {self.model_size} model loaded successfully")

        except Exception as e:
            logger.error(f"Failed to load Whisper model: {e}")
            raise

    def _load_model_sync(self):
        """Synchronous model loading."""
        # Whisper automatically downloads the model if not cached
        self.model = whisper.load_model(self.model_size, device=self.device)
        logger.info(f"Whisper model loaded on device: {self.device}")

    def start_session(self):
        """Start a new transcription session."""
        self.session_active = True
        self.last_transcription = ""
        logger.debug("Whisper transcription session started")

    def end_session(self):
        """End the current transcription session."""
        self.session_active = False
        self.last_transcription = ""
        logger.debug("Whisper transcription session ended")

    async def transcribe_incremental(self, audio: np.ndarray) -> str:
        """
        Transcribe audio incrementally (for partial results).

        Note: Whisper doesn't support true streaming, so this does full
        transcription on the accumulated audio.

        Args:
            audio: Audio samples as float32 numpy array (16kHz mono)

        Returns:
            Partial transcription text
        """
        if not self.is_loaded or not self.session_active:
            return ""

        try:
            # Only transcribe if we have enough audio (at least 1 second for Whisper)
            min_samples = int(self.SAMPLE_RATE * 1.0)
            if len(audio) < min_samples:
                return self.last_transcription

            # Run transcription in thread pool
            loop = asyncio.get_event_loop()
            text = await loop.run_in_executor(
                None,
                self._transcribe_sync,
                audio
            )

            if text:
                self.last_transcription = text
            return text if text else self.last_transcription

        except Exception as e:
            logger.error(f"Incremental transcription error: {e}")
            return self.last_transcription

    async def transcribe_final(self, audio: np.ndarray) -> str:
        """
        Transcribe audio for final result.

        Args:
            audio: Audio samples as float32 numpy array (16kHz mono)

        Returns:
            Final transcription text
        """
        if not self.is_loaded:
            return ""

        try:
            if len(audio) < 1600:  # Less than 0.1 seconds
                return ""

            # Run transcription in thread pool
            loop = asyncio.get_event_loop()
            text = await loop.run_in_executor(
                None,
                self._transcribe_sync,
                audio
            )

            return text

        except Exception as e:
            logger.error(f"Final transcription error: {e}")
            return ""

    def _transcribe_sync(self, audio: np.ndarray) -> str:
        """Synchronous transcription."""
        if self.model is None:
            return ""

        try:
            # Ensure audio is 1D
            audio = audio.flatten()

            # Ensure audio is the right dtype
            if audio.dtype != np.float32:
                audio = audio.astype(np.float32)

            # Normalize audio if needed
            max_val = np.abs(audio).max()
            if max_val > 1.0:
                audio = audio / max_val
            elif max_val < 0.01:
                logger.warning(f"Audio level very low: {max_val}")

            logger.info(f"Whisper transcribing {len(audio)/16000:.2f}s of audio")

            # Transcribe using Whisper
            # fp16=False for CPU compatibility
            # condition_on_previous_text=False prevents hallucinations like "Thank you"
            result = self.model.transcribe(
                audio,
                fp16=(self.device == "cuda"),
                language=None,  # Auto-detect language
                condition_on_previous_text=False,  # Prevent hallucinations
                no_speech_threshold=0.6,  # Higher threshold to detect no-speech segments
            )

            text = result.get("text", "").strip()

            if text:
                logger.info(f"Whisper transcription: '{text[:100]}...' " if len(text) > 100 else f"Whisper transcription: '{text}'")

            return text

        except Exception as e:
            logger.error(f"Whisper transcription error: {e}")
            import traceback
            traceback.print_exc()
            return ""

    def _transcribe_with_timestamps_sync(self, audio: np.ndarray) -> dict:
        """Synchronous transcription with word-level timestamps."""
        if self.model is None:
            return {"text": "", "words": []}

        try:
            # Ensure audio is 1D
            audio = audio.flatten()

            # Ensure audio is the right dtype
            if audio.dtype != np.float32:
                audio = audio.astype(np.float32)

            # Normalize audio if needed
            max_val = np.abs(audio).max()
            if max_val > 1.0:
                audio = audio / max_val
            elif max_val < 0.01:
                logger.warning(f"Audio level very low: {max_val}")

            logger.info(f"Whisper transcribing with timestamps: {len(audio)/16000:.2f}s of audio")

            # Transcribe with word timestamps
            # condition_on_previous_text=False prevents hallucinations like "Thank you"
            result = self.model.transcribe(
                audio,
                fp16=(self.device == "cuda"),
                language=None,
                word_timestamps=True,  # Enable word-level timestamps
                condition_on_previous_text=False,  # Prevent hallucinations
                no_speech_threshold=0.6,  # Higher threshold to detect no-speech segments
            )

            # Extract words with timestamps from segments
            words = []
            for segment in result.get("segments", []):
                for word_info in segment.get("words", []):
                    words.append({
                        "word": word_info.get("word", "").strip(),
                        "start": word_info.get("start", 0),
                        "end": word_info.get("end", 0),
                    })

            text = result.get("text", "").strip()
            logger.info(f"Whisper found {len(words)} words with timestamps")

            return {"text": text, "words": words}

        except Exception as e:
            logger.error(f"Whisper transcription with timestamps error: {e}")
            import traceback
            traceback.print_exc()
            return {"text": "", "words": []}

    async def transcribe_with_timestamps(self, audio: np.ndarray) -> dict:
        """
        Transcribe audio and return word-level timestamps.

        Args:
            audio: Audio samples as float32 numpy array (16kHz mono)

        Returns:
            Dict with 'text' (full text) and 'words' (list of {word, start, end})
        """
        if not self.is_loaded:
            return {"text": "", "words": []}

        try:
            if len(audio) < 1600:  # Less than 0.1 seconds
                return {"text": "", "words": []}

            # Run transcription in thread pool
            loop = asyncio.get_event_loop()
            result = await loop.run_in_executor(
                None,
                self._transcribe_with_timestamps_sync,
                audio
            )

            return result

        except Exception as e:
            logger.error(f"Transcription with timestamps error: {e}")
            return {"text": "", "words": []}

    def unload(self):
        """Unload the model to free memory."""
        if self.model is not None:
            logger.info(f"Unloading Whisper {self.model_size} model from memory...")
            del self.model
            self.model = None
            self.is_loaded = False

            try:
                import torch
                # Synchronize and clear GPU cache
                if torch.cuda.is_available():
                    logger.info("Clearing CUDA cache...")
                    try:
                        torch.cuda.synchronize()
                        torch.cuda.empty_cache()
                        logger.info("CUDA cache cleared successfully")
                    except Exception as e:
                        logger.error(f"Failed to clear CUDA cache: {e}")

                if hasattr(torch, 'mps') and torch.backends.mps.is_available():
                    logger.info("Clearing MPS (Apple Silicon) cache...")
                    try:
                        torch.mps.synchronize()
                        torch.mps.empty_cache()
                        logger.info("MPS cache cleared successfully")
                    except Exception as e:
                        logger.error(f"Failed to clear MPS cache: {e}")
            except ImportError:
                logger.warning("PyTorch not available, skipping GPU cache clearing")

            # Force garbage collection to release memory
            import gc
            logger.info("Running garbage collection...")
            collected = gc.collect()
            logger.info(f"Garbage collection completed, {collected} objects collected")

            logger.info(f"Whisper {self.model_size} model unloaded successfully")

    @staticmethod
    def get_available_models() -> list:
        """Get list of available Whisper model sizes."""
        return WhisperEngine.MODEL_SIZES.copy()

    @staticmethod
    def is_available() -> bool:
        """Check if Whisper is available."""
        return WHISPER_AVAILABLE
