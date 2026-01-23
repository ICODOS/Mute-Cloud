#!/usr/bin/env python3
"""
ASR Engine - Speech recognition using NVIDIA Parakeet TDT v3 model.
"""

import logging
import asyncio
import gzip
import shutil
import tarfile
import tempfile
from pathlib import Path
from typing import Optional
import numpy as np

logger = logging.getLogger(__name__)

# Try to import torch and nemo
TORCH_AVAILABLE = False
NEMO_AVAILABLE = False

try:
    import torch
    TORCH_AVAILABLE = True
    logger.info(f"PyTorch version: {torch.__version__}")
    
    # Check for MPS (Apple Silicon) support
    if torch.backends.mps.is_available():
        logger.info("MPS (Apple Silicon) is available")
    else:
        logger.info("MPS not available, using CPU")
        
except ImportError:
    logger.warning("PyTorch not installed")

try:
    import nemo.collections.asr as nemo_asr
    NEMO_AVAILABLE = True
    logger.info("NeMo ASR is available")
except ImportError:
    logger.warning("NeMo not installed. Run: pip install nemo_toolkit[asr]")


class ASREngine:
    """Speech recognition engine using NVIDIA Parakeet TDT v3."""
    
    SAMPLE_RATE = 16000  # Parakeet expects 16kHz audio
    
    def __init__(self, model_path: Optional[str] = None):
        self.model_path = model_path
        self.model = None
        self.is_loaded = False
        self.device = "cpu"
        
        # Session state
        self.session_active = False
        self.last_transcription = ""
        
        # Determine device - prefer MPS (Apple Silicon GPU) for speed
        if TORCH_AVAILABLE:
            if torch.backends.mps.is_available():
                self.device = "mps"
                logger.info("Using MPS (Apple Silicon GPU) for inference")
            elif torch.cuda.is_available():
                self.device = "cuda"
                logger.info("Using CUDA GPU for inference")
            else:
                self.device = "cpu"
                logger.info("Using CPU for inference")
    
    async def load_model(self):
        """Load the ASR model."""
        if not NEMO_AVAILABLE:
            raise RuntimeError("NeMo is not installed")
        
        if not self.model_path:
            raise RuntimeError("Model path not specified")
        
        logger.info(f"Loading model from {self.model_path}")
        
        try:
            # Run model loading in thread pool to not block event loop
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(None, self._load_model_sync)
            
            self.is_loaded = True
            logger.info("Model loaded successfully")
            
        except Exception as e:
            logger.error(f"Failed to load model: {e}")
            raise
    
    def _load_model_sync(self):
        """Synchronous model loading."""
        model_path = self.model_path

        # Check if the .nemo file is gzipped or plain tar
        # NeMo expects gzip-compressed tar, but HuggingFace may provide plain tar
        if not self._is_gzipped(model_path):
            logger.info("Model file is not gzipped, converting to gzip format...")
            model_path = self._convert_to_gzip(model_path)
            logger.info(f"Using gzipped model at: {model_path}")

        # Load model using NeMo
        # Parakeet TDT is an EncDecRNNTBPEModel
        self.model = nemo_asr.models.EncDecRNNTBPEModel.restore_from(
            model_path,
            map_location=self.device
        )

        # Explicitly move to device (important for MPS)
        if self.device == "mps":
            self.model = self.model.to("mps")
        elif self.device == "cuda":
            self.model = self.model.cuda()

        # Set to eval mode
        self.model.eval()

        # Freeze the model
        self.model.freeze()

        logger.info(f"Model loaded on device: {self.device}")

    def _is_gzipped(self, filepath: str) -> bool:
        """Check if a file is gzip-compressed."""
        try:
            with open(filepath, 'rb') as f:
                # Gzip magic number is 1f 8b
                magic = f.read(2)
                return magic == b'\x1f\x8b'
        except Exception:
            return False

    def _convert_to_gzip(self, filepath: str) -> str:
        """
        Convert a plain tar file to gzip-compressed tar.
        Returns path to the gzipped file.
        """
        # Create gzipped version alongside original
        gzip_path = filepath + ".gz"

        # Check if gzipped version already exists
        if Path(gzip_path).exists():
            logger.info(f"Gzipped version already exists: {gzip_path}")
            return gzip_path

        logger.info(f"Compressing {filepath} to {gzip_path}")

        try:
            with open(filepath, 'rb') as f_in:
                with gzip.open(gzip_path, 'wb') as f_out:
                    shutil.copyfileobj(f_in, f_out)

            logger.info(f"Compression complete: {gzip_path}")
            return gzip_path

        except Exception as e:
            logger.error(f"Failed to compress model file: {e}")
            # If compression fails, try to load original anyway
            return filepath
    
    def start_session(self):
        """Start a new transcription session."""
        self.session_active = True
        self.last_transcription = ""
        logger.debug("Transcription session started")
    
    def end_session(self):
        """End the current transcription session."""
        self.session_active = False
        self.last_transcription = ""
        logger.debug("Transcription session ended")
    
    async def transcribe_incremental(self, audio: np.ndarray) -> str:
        """
        Transcribe audio incrementally (for partial results).
        
        Args:
            audio: Audio samples as float32 numpy array (16kHz mono)
            
        Returns:
            Partial transcription text
        """
        if not self.is_loaded or not self.session_active:
            return ""
        
        try:
            # Only transcribe if we have enough audio (at least 0.5 seconds)
            min_samples = int(self.SAMPLE_RATE * 0.5)
            if len(audio) < min_samples:
                return self.last_transcription
            
            # Run transcription in thread pool
            loop = asyncio.get_event_loop()
            text = await loop.run_in_executor(
                None, 
                self._transcribe_sync, 
                audio
            )
            
            # Only update last_transcription if we got non-empty text
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
            
            # NOTE: Swift AudioCaptureManager already resamples to 16kHz
            # No additional resampling needed here
            
            # Normalize audio if needed
            max_val = np.abs(audio).max()
            if max_val > 1.0:
                audio = audio / max_val
            elif max_val < 0.01:
                logger.warning(f"Audio level very low: {max_val}")
            
            logger.info(f"Transcribing {len(audio)/16000:.2f}s of audio on {self.device}")
            
            # NeMo's transcribe method expects a list of numpy arrays or file paths
            with torch.inference_mode():
                hypotheses = self.model.transcribe(
                    [audio],
                    batch_size=1
                )
            
            # Extract text from hypothesis
            if hypotheses and len(hypotheses) > 0:
                if isinstance(hypotheses[0], str):
                    result = hypotheses[0].strip()
                elif hasattr(hypotheses[0], 'text'):
                    result = hypotheses[0].text.strip()
                else:
                    result = str(hypotheses[0]).strip()
                logger.info(f"Transcription: '{result[:100]}...' " if len(result) > 100 else f"Transcription: '{result}'")
                return result
            
            return ""
            
        except Exception as e:
            logger.error(f"Transcription error: {e}")
            import traceback
            traceback.print_exc()
            return ""
    
    def unload(self):
        """Unload the model to free memory."""
        if self.model is not None:
            logger.info("Unloading ASR model from memory...")
            del self.model
            self.model = None
            self.is_loaded = False

            if TORCH_AVAILABLE:
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

            # Force garbage collection to release memory
            import gc
            logger.info("Running garbage collection...")
            collected = gc.collect()
            logger.info(f"Garbage collection completed, {collected} objects collected")

            logger.info("ASR model unloaded successfully")

    def warm_up(self):
        """Run a tiny inference to keep model weights in active GPU memory."""
        if not self.is_loaded or self.model is None:
            return
        try:
            silence = np.zeros(8000, dtype=np.float32)  # 0.5s of silence
            with torch.inference_mode():
                self.model.transcribe([silence], batch_size=1)
            logger.info("Model warm-up inference completed")
        except Exception as e:
            logger.warning(f"Warm-up inference failed: {e}")


class MockASREngine:
    """
    Mock ASR engine for testing without the actual model.
    Returns placeholder text based on audio duration.
    """
    
    SAMPLE_RATE = 16000
    
    def __init__(self, model_path: Optional[str] = None):
        self.model_path = model_path
        self.is_loaded = False
        self.session_active = False
    
    async def load_model(self):
        """Simulate model loading."""
        await asyncio.sleep(2)  # Simulate loading time
        self.is_loaded = True
        logger.info("Mock model loaded")
    
    def start_session(self):
        self.session_active = True
    
    def end_session(self):
        self.session_active = False
    
    async def transcribe_incremental(self, audio: np.ndarray) -> str:
        """Return mock partial transcription."""
        if not self.is_loaded or not self.session_active:
            return ""
        
        duration = len(audio) / self.SAMPLE_RATE
        if duration < 0.5:
            return ""
        elif duration < 1.0:
            return "Hello"
        elif duration < 2.0:
            return "Hello world"
        else:
            return "Hello world, this is a test"
    
    async def transcribe_final(self, audio: np.ndarray) -> str:
        """Return mock final transcription."""
        if not self.is_loaded:
            return ""
        
        duration = len(audio) / self.SAMPLE_RATE
        return f"This is a mock transcription. Audio duration: {duration:.1f} seconds."
    
    def unload(self):
        self.is_loaded = False
