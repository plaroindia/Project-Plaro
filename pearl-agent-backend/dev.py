#!/usr/bin/env python3
"""
Development server launcher - runs both FastAPI backend and Vite dev server
"""

import subprocess
import threading
import time
import os
import sys
from pathlib import Path

def run_backend():
    """Run FastAPI backend"""
    print("🚀 Starting FastAPI backend on http://localhost:8000")
    os.chdir(Path(__file__).parent)
    subprocess.run([sys.executable, "-m", "uvicorn", "main:app", "--reload", "--host", "0.0.0.0", "--port", "8000"])

def run_frontend():
    """Run Vite dev server"""
    print("⚡ Starting Vite dev server on http://localhost:3000")
    os.chdir(Path(__file__).parent / "pearl-agent")
    subprocess.run(["npm", "run", "dev"])

def main():
    print("🔥 Starting PEARL Agent Development Environment")
    print("=" * 50)
    
    # Start backend in a separate thread
    backend_thread = threading.Thread(target=run_backend)
    backend_thread.daemon = True
    backend_thread.start()
    
    # Give backend time to start
    time.sleep(2)
    
    # Start frontend (this will block)
    try:
        run_frontend()
    except KeyboardInterrupt:
        print("\n🛑 Shutting down development servers...")
        sys.exit(0)

if __name__ == "__main__":
    main()