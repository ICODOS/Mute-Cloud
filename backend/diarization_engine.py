#!/usr/bin/env python3
"""
Diarization Engine - Speaker identification using pyannote.audio.
"""

import logging
import asyncio
import os
from pathlib import Path
from typing import Optional, List, Dict
import numpy as np

logger = logging.getLogger(__name__)

# Try to import pyannote
PYANNOTE_AVAILABLE = False

try:
    from pyannote.audio import Pipeline
    import torch
    PYANNOTE_AVAILABLE = True
    logger.info("pyannote.audio is available")
except ImportError:
    logger.warning("pyannote.audio not installed. Run: pip install pyannote.audio")


class DiarizationEngine:
    """Speaker diarization engine using pyannote.audio."""

    SAMPLE_RATE = 16000  # Expected sample rate

    def __init__(self, model_dir: Optional[str] = None):
        """
        Initialize DiarizationEngine.

        Args:
            model_dir: Directory containing cached pyannote models.
                      If None, uses default HuggingFace cache.
        """
        self.model_dir = model_dir
        self.pipeline = None
        self.is_loaded = False
        self.device = "cpu"

        # Determine device
        if PYANNOTE_AVAILABLE:
            try:
                if torch.cuda.is_available():
                    self.device = "cuda"
                    logger.info("Using CUDA GPU for diarization")
                elif torch.backends.mps.is_available():
                    # MPS can work with pyannote but may have issues
                    self.device = "cpu"
                    logger.info("MPS available but using CPU for diarization (better compatibility)")
                else:
                    self.device = "cpu"
                    logger.info("Using CPU for diarization")
            except Exception:
                self.device = "cpu"

    async def load_model(self):
        """Load the pyannote diarization pipeline."""
        if not PYANNOTE_AVAILABLE:
            raise RuntimeError("pyannote.audio is not installed")

        logger.info("Loading pyannote speaker-diarization-3.1 model...")

        try:
            # Run model loading in thread pool to not block event loop
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(None, self._load_model_sync)

            self.is_loaded = True
            logger.info("Diarization model loaded successfully")

        except Exception as e:
            logger.error(f"Failed to load diarization model: {e}")
            raise

    def _load_model_sync(self):
        """Synchronous model loading."""
        # If we have a local model directory, set the cache dir
        if self.model_dir and os.path.exists(self.model_dir):
            # Set ALL HuggingFace cache environment variables
            os.environ['HF_HUB_CACHE'] = self.model_dir
            os.environ['TRANSFORMERS_CACHE'] = self.model_dir
            os.environ['HF_HOME'] = self.model_dir
            logger.info(f"Using local model cache: {self.model_dir}")

        # Load the pipeline
        # Note: token not needed if models are already cached locally
        self.pipeline = Pipeline.from_pretrained(
            "pyannote/speaker-diarization-3.1"
        )

        # Move to appropriate device
        if self.device != "cpu":
            self.pipeline = self.pipeline.to(torch.device(self.device))

        logger.info(f"Diarization pipeline loaded on device: {self.device}")

    def diarize_sync(self, audio: np.ndarray) -> List[Dict]:
        """
        Perform speaker diarization on audio.

        Args:
            audio: Audio samples as float32 numpy array (16kHz mono)

        Returns:
            List of speaker segments:
            [{"speaker": "SPEAKER_00", "start": 0.0, "end": 5.2}, ...]
        """
        if not self.is_loaded or self.pipeline is None:
            return []

        try:
            # Ensure audio is 1D float32
            audio = audio.flatten().astype(np.float32)

            # Normalize if needed
            max_val = np.abs(audio).max()
            if max_val > 1.0:
                audio = audio / max_val

            # pyannote expects a dict with "waveform" and "sample_rate"
            audio_dict = {
                "waveform": torch.from_numpy(audio).unsqueeze(0),  # Add channel dimension
                "sample_rate": self.SAMPLE_RATE
            }

            logger.info(f"Diarizing {len(audio)/self.SAMPLE_RATE:.2f}s of audio")

            # Run diarization
            result = self.pipeline(audio_dict)

            # pyannote 4.0+ returns DiarizeOutput, need to get speaker_diarization
            if hasattr(result, 'speaker_diarization'):
                diarization = result.speaker_diarization
            else:
                # Older versions return Annotation directly
                diarization = result

            # Extract segments
            segments = []
            for turn, _, speaker in diarization.itertracks(yield_label=True):
                segments.append({
                    "speaker": speaker,
                    "start": turn.start,
                    "end": turn.end
                })

            logger.info(f"Found {len(segments)} speaker segments")
            return segments

        except Exception as e:
            logger.error(f"Diarization error: {e}")
            import traceback
            traceback.print_exc()
            return []

    async def diarize(self, audio: np.ndarray) -> List[Dict]:
        """
        Async wrapper for diarization.

        Args:
            audio: Audio samples as float32 numpy array (16kHz mono)

        Returns:
            List of speaker segments
        """
        if not self.is_loaded:
            return []

        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, self.diarize_sync, audio)

    def assign_speakers_to_words(
        self,
        words: List[Dict],
        segments: List[Dict]
    ) -> List[Dict]:
        """
        Assign speaker labels to words based on timestamp overlap.

        Args:
            words: List of word dicts with "word", "start", "end" keys
            segments: List of speaker segments with "speaker", "start", "end" keys

        Returns:
            Words list with added "speaker" key for each word
        """
        if not segments:
            # No diarization results - return words unchanged
            return words

        # Create a mapping of time ranges to speakers
        # For each word, find which speaker segment it falls into
        result = []
        for word in words:
            word_start = word.get("start", 0)
            word_end = word.get("end", 0)
            word_mid = (word_start + word_end) / 2

            # Find the speaker segment that contains this word's midpoint
            assigned_speaker = None
            max_overlap = 0

            for seg in segments:
                seg_start = seg["start"]
                seg_end = seg["end"]

                # Check if word midpoint falls within segment
                if seg_start <= word_mid <= seg_end:
                    assigned_speaker = seg["speaker"]
                    break

                # Alternatively, find segment with maximum overlap
                overlap_start = max(word_start, seg_start)
                overlap_end = min(word_end, seg_end)
                overlap = max(0, overlap_end - overlap_start)

                if overlap > max_overlap:
                    max_overlap = overlap
                    assigned_speaker = seg["speaker"]

            # Add speaker to word dict
            word_with_speaker = word.copy()
            word_with_speaker["speaker"] = assigned_speaker or "Unknown"
            result.append(word_with_speaker)

        return result

    def format_speakers(self, speakers: List[str]) -> Dict[str, str]:
        """
        Create friendly speaker names from pyannote labels.

        Args:
            speakers: List of speaker labels like ["SPEAKER_00", "SPEAKER_01"]

        Returns:
            Mapping from original label to friendly name:
            {"SPEAKER_00": "Speaker 1", "SPEAKER_01": "Speaker 2"}
        """
        unique_speakers = sorted(set(speakers))
        return {
            label: f"Speaker {i+1}"
            for i, label in enumerate(unique_speakers)
        }

    def unload(self):
        """Unload the model to free memory."""
        if self.pipeline is not None:
            del self.pipeline
            self.pipeline = None
            self.is_loaded = False

            try:
                import torch
                if torch.cuda.is_available():
                    torch.cuda.empty_cache()
            except ImportError:
                pass

            logger.info("Diarization model unloaded")

    @staticmethod
    def is_available() -> bool:
        """Check if pyannote is available."""
        return PYANNOTE_AVAILABLE
