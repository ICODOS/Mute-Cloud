#!/usr/bin/env python3
"""
Model Manager - Download and manage NVIDIA Parakeet TDT v3 model.
"""

import os
import logging
import shutil
import asyncio
from pathlib import Path
from typing import Optional, AsyncGenerator

logger = logging.getLogger(__name__)

# Try to import huggingface_hub
HF_AVAILABLE = False
try:
    from huggingface_hub import snapshot_download, hf_hub_download
    from huggingface_hub.utils import HfHubHTTPError
    HF_AVAILABLE = True
except ImportError:
    logger.warning("huggingface_hub not installed. Run: pip install huggingface_hub")


class ModelManager:
    """Manager for downloading and caching NVIDIA Parakeet model."""
    
    MODEL_ID = "nvidia/parakeet-tdt-0.6b-v3"  # v3 multilingual (25 European languages)
    MODEL_FILENAME = "parakeet-tdt-0.6b-v3.nemo"
    MODEL_SIZE_MB = 2393  # ~2.39 GB actual size
    
    def __init__(self, cache_dir: Optional[str] = None):
        if cache_dir:
            self.cache_dir = Path(cache_dir)
        else:
            # Default to ~/Library/Application Support/Mute/Models
            app_support = Path.home() / "Library" / "Application Support" / "Mute"
            self.cache_dir = app_support / "Models"
        
        # Ensure cache directory exists
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        
        logger.info(f"Model cache directory: {self.cache_dir}")
    
    def get_model_path(self) -> Optional[str]:
        """Get path to the downloaded model file."""
        # Check for .nemo file in cache
        nemo_files = list(self.cache_dir.glob("*.nemo"))
        if nemo_files:
            return str(nemo_files[0])
        
        # Check in HF cache subdirectory
        hf_cache = self.cache_dir / "hf_cache"
        if hf_cache.exists():
            nemo_files = list(hf_cache.rglob("*.nemo"))
            if nemo_files:
                return str(nemo_files[0])
        
        return None
    
    def is_model_downloaded(self) -> bool:
        """Check if model is already downloaded."""
        model_path = self.get_model_path()
        if model_path and Path(model_path).exists():
            # Verify file size (model should be > 500MB)
            size_mb = Path(model_path).stat().st_size / (1024 * 1024)
            if size_mb > 100:  # At least 100MB
                logger.info(f"Model found at {model_path} ({size_mb:.1f} MB)")
                return True
        return False
    
    def download_model(self, progress_callback=None) -> str:
        """
        Download the model from Hugging Face.
        
        Args:
            progress_callback: Optional callback(percent) for progress updates
            
        Returns:
            Path to downloaded model
        """
        if not HF_AVAILABLE:
            raise RuntimeError("huggingface_hub is not installed")
        
        logger.info(f"Downloading model {self.MODEL_ID}")
        
        try:
            # Use hf_hub_download for single file
            local_path = hf_hub_download(
                repo_id=self.MODEL_ID,
                filename=self.MODEL_FILENAME,
                cache_dir=str(self.cache_dir / "hf_cache"),
                resume_download=True,
            )
            
            logger.info(f"Model downloaded to {local_path}")
            return local_path
            
        except HfHubHTTPError as e:
            logger.error(f"HF Hub error: {e}")
            # Try alternative model ID
            return self._try_alternative_download()
        except Exception as e:
            logger.error(f"Download failed: {e}")
            raise
    
    async def download_model_async(self) -> AsyncGenerator[float, None]:
        """
        Download model asynchronously with progress updates.
        
        Yields:
            Progress percentage (0-100)
        """
        if not HF_AVAILABLE:
            raise RuntimeError("huggingface_hub is not installed")
        
        logger.info(f"Starting async download of {self.MODEL_ID}")
        
        try:
            # Get expected model size
            total_size = self.MODEL_SIZE_MB * 1024 * 1024  # ~2.5GB for v3
            
            try:
                from huggingface_hub import model_info
                info = model_info(self.MODEL_ID)
                for sibling in info.siblings:
                    if sibling.rfilename.endswith('.nemo'):
                        if hasattr(sibling, 'size') and sibling.size:
                            total_size = sibling.size
                            break
            except Exception as e:
                logger.warning(f"Could not get model info: {e}")
            
            logger.info(f"Expected model size: {total_size / (1024*1024):.1f} MB")
            
            # Start download in background thread
            loop = asyncio.get_running_loop()
            download_future = loop.run_in_executor(None, self.download_model)
            
            # Monitor progress by checking file sizes
            hf_cache = self.cache_dir / "hf_cache"
            model_cache = hf_cache / f"models--{self.MODEL_ID.replace('/', '--')}"
            last_progress = 0

            while not download_future.done():
                await asyncio.sleep(0.5)  # Check more frequently

                # Check for model files (blobs contain the actual data)
                current_size = 0
                blobs_dir = model_cache / "blobs"
                if blobs_dir.exists():
                    try:
                        for f in blobs_dir.iterdir():
                            if f.is_file() and not f.name.startswith('.'):
                                current_size += f.stat().st_size
                    except Exception:
                        pass

                # Calculate progress - allow up to 99% during download
                if total_size > 0 and current_size > 0:
                    progress = min(99, (current_size / total_size) * 100)
                    if progress > last_progress:
                        last_progress = progress
                        yield progress

            # Wait for download to complete and get result
            result = await download_future
            logger.info(f"Download complete: {result}")
            yield 100
            
        except Exception as e:
            logger.error(f"Async download failed: {e}")
            raise
    
    def _try_alternative_download(self) -> str:
        """Try downloading from alternative source or model ID."""
        alternative_ids = [
            ("nvidia/parakeet-tdt-0.6b-v3", "parakeet-tdt-0.6b-v3.nemo"),  # v3 multilingual
            ("nvidia/parakeet-tdt-0.6b-v2", "parakeet-tdt-0.6b-v2.nemo"),  # v2 English
        ]
        
        for model_id, expected_file in alternative_ids:
            try:
                logger.info(f"Trying alternative model: {model_id}")
                
                # List files in repo
                from huggingface_hub import list_repo_files
                files = list_repo_files(model_id)
                
                # Find .nemo file
                nemo_files = [f for f in files if f.endswith('.nemo')]
                if nemo_files:
                    local_path = hf_hub_download(
                        repo_id=model_id,
                        filename=nemo_files[0],
                        cache_dir=str(self.cache_dir / "hf_cache"),
                        resume_download=True,
                    )
                    return local_path
                    
            except Exception as e:
                logger.warning(f"Alternative {model_id} failed: {e}")
                continue
        
        raise RuntimeError("Could not download model from any source")
    
    def clear_cache(self):
        """Clear the model cache."""
        logger.info(f"Clearing cache at {self.cache_dir}")
        
        try:
            # Remove all files in cache directory
            for item in self.cache_dir.iterdir():
                if item.is_file():
                    item.unlink()
                elif item.is_dir():
                    shutil.rmtree(item)
            
            logger.info("Cache cleared")
        except Exception as e:
            logger.error(f"Failed to clear cache: {e}")
    
    def get_cache_size(self) -> int:
        """Get total size of cache in bytes."""
        total = 0
        for item in self.cache_dir.rglob("*"):
            if item.is_file():
                total += item.stat().st_size
        return total
    
    def get_cache_size_str(self) -> str:
        """Get human-readable cache size."""
        size = self.get_cache_size()
        if size < 1024:
            return f"{size} B"
        elif size < 1024 * 1024:
            return f"{size / 1024:.1f} KB"
        elif size < 1024 * 1024 * 1024:
            return f"{size / (1024 * 1024):.1f} MB"
        else:
            return f"{size / (1024 * 1024 * 1024):.1f} GB"


# Standalone test
if __name__ == "__main__":
    import asyncio
    
    logging.basicConfig(level=logging.INFO)
    
    async def test():
        manager = ModelManager()
        
        print(f"Cache directory: {manager.cache_dir}")
        print(f"Model downloaded: {manager.is_model_downloaded()}")
        print(f"Cache size: {manager.get_cache_size_str()}")
        
        if not manager.is_model_downloaded():
            print("Downloading model...")
            async for progress in manager.download_model_async():
                print(f"Progress: {progress:.1f}%")
        
        print(f"Model path: {manager.get_model_path()}")
    
    asyncio.run(test())
