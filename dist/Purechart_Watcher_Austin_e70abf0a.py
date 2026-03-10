#!/usr/bin/env python3
"""
PureChart File Upload Live - Drop-In Folder Watcher

Place this script in the folder you want to monitor.
It watches its own directory for new files and uploads them to PureChart.

Install dependencies:
  pip install requests watchdog

Usage:
  1. Copy this file into the folder to monitor (e.g. C:\\PanoramicXrays)
  2. Double-click or run: python purechart_watcher.py
"""

import os
import sys
import time
import hashlib
import base64
import logging
import json
import platform
import subprocess
import requests
from watchdog.events import FileSystemEventHandler

# Use PollingObserver on Windows for reliability (ReadDirectoryChangesW can miss events)
if platform.system() == "Windows":
    from watchdog.observers.polling import PollingObserver as Observer
else:
    from watchdog.observers import Observer

# ─── Configuration (pre-filled from PureChart) ───────────────────────
SUPABASE_URL = "https://whzohbzqhqaohpohmqah.supabase.co"
ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Indoem9oYnpxaHFhb2hwb2htcWFoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyNTUzNzQsImV4cCI6MjA3NDgzMTM3NH0.p_BZ1XaPIihSdo-41YKbr4ZmS-NZRfGr9AerEEgpmcc"
ORGANIZATION_ID = "33b007f2-753b-44a4-bafe-08b1370f66a7"
FACILITY_ID = "550e8400-e29b-41d4-a716-446655440005"
SCRIPT_ID = "e70abf0a-60ca-4db0-aa9d-b67239c1b90f"
FILE_EXTENSIONS = [".jpg",".jpeg",".png",".tiff",".tif",".pdf"]
MAX_FILE_SIZE = 50 * 1024 * 1024  # 50MB
CLEANUP_AGE_HOURS = 48  # Delete uploaded files older than this

# Watch the folder where this script lives
WATCH_FOLDER = os.path.dirname(os.path.abspath(__file__))

# Compound extensions that os.path.splitext cannot handle
COMPOUND_EXTENSIONS = [".nii.gz"]

# ─── Logging ─────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler(
            os.path.join(WATCH_FOLDER, "purechart_upload.log"), encoding="utf-8"
        ),
    ],
)
log = logging.getLogger("purechart-upload")

# Track processed file hashes to avoid re-uploading
processed_hashes = set()
HASH_CACHE_FILE = os.path.join(WATCH_FOLDER, ".purechart_hashes.json")
PID_FILE = os.path.join(WATCH_FOLDER, ".purechart_watcher.pid")


def load_hash_cache():
    global processed_hashes
    if os.path.exists(HASH_CACHE_FILE):
        try:
            with open(HASH_CACHE_FILE, "r") as f:
                processed_hashes = set(json.load(f))
            log.info(f"Loaded {len(processed_hashes)} cached hashes")
        except Exception as e:
            log.warning(f"Could not load hash cache: {e}")


def save_hash_cache():
    try:
        with open(HASH_CACHE_FILE, "w") as f:
            json.dump(list(processed_hashes), f)
    except Exception as e:
        log.warning(f"Could not save hash cache: {e}")


def compute_sha256(filepath, retries=5):
    """Compute SHA-256 with retry for Windows file locking."""
    for attempt in range(retries):
        try:
            sha256 = hashlib.sha256()
            with open(filepath, "rb") as f:
                for chunk in iter(lambda: f.read(8192), b""):
                    sha256.update(chunk)
            return sha256.hexdigest()
        except PermissionError:
            if attempt < retries - 1:
                log.warning(f"File locked ({attempt + 1}/{retries}), retrying: {os.path.basename(filepath)}")
                time.sleep(1)
            else:
                raise
        except OSError:
            raise  # Don't retry for file-not-found or other OS errors


def get_hostname():
    import socket
    try:
        return socket.gethostname()
    except Exception:
        return "unknown"


def get_public_ip():
    try:
        resp = requests.get("https://api.ipify.org?format=json", timeout=5)
        return resp.json().get("ip", "")
    except Exception:
        return ""


def get_file_ext(filepath):
    """Get file extension, handling compound extensions like .nii.gz."""
    basename = os.path.basename(filepath).lower()
    for compound in COMPOUND_EXTENSIONS:
        if basename.endswith(compound):
            return compound
    return os.path.splitext(basename)[1]


def is_own_file(filepath):
    """Skip our own log/cache/script files."""
    basename = os.path.basename(filepath).lower()
    if basename in ("purechart_upload.log", ".purechart_hashes.json", ".purechart_watcher.pid"):
        return True
    if basename.startswith("purechart_watcher") and basename.endswith(".py"):
        return True
    return False


def wait_for_file_stable(filepath, timeout=60):
    """Wait until file size stops changing AND file is readable (not locked)."""
    if not os.path.exists(filepath):
        return False
    prev_size = -1
    stable_count = 0
    missing_count = 0
    start = time.time()
    while time.time() - start < timeout:
        try:
            size = os.path.getsize(filepath)
            if size == prev_size and size > 0:
                stable_count += 1
                if stable_count >= 3:
                    # Verify file is actually readable (not locked on Windows)
                    try:
                        with open(filepath, "rb") as f:
                            f.read(1)
                        return True
                    except (PermissionError, OSError):
                        log.debug(f"File stable but still locked: {os.path.basename(filepath)}")
                        stable_count = 0  # Reset — file still locked
            else:
                stable_count = 0
            prev_size = size
        except OSError:
            missing_count += 1
            if missing_count >= 3:
                return False  # File disappeared — stop waiting
        time.sleep(0.5)
    return prev_size > 0


def upload_file(filepath):
    if is_own_file(filepath):
        return

    if not os.path.exists(filepath):
        return

    filename = os.path.basename(filepath)
    ext = get_file_ext(filepath)

    if ext not in FILE_EXTENSIONS:
        return

    try:
        file_size = os.path.getsize(filepath)
    except OSError as e:
        log.warning(f"Cannot read {filename}: {e}")
        return

    if file_size == 0:
        log.warning(f"Skipping {filename}: empty file")
        return

    if file_size > MAX_FILE_SIZE:
        log.warning(f"Skipping {filename}: too large ({file_size} bytes)")
        return

    try:
        file_hash = compute_sha256(filepath)
    except (PermissionError, OSError) as e:
        log.warning(f"Cannot read {filename} (file locked?): {e}")
        return

    if file_hash in processed_hashes:
        log.info(f"Skipping {filename}: already processed (hash match)")
        return

    # Read and encode file (retry for Windows file locking)
    for attempt in range(3):
        try:
            with open(filepath, "rb") as f:
                file_data = f.read()
            break
        except (PermissionError, OSError) as e:
            if attempt < 2:
                log.warning(f"File locked, retrying read ({attempt + 1}/3): {filename}")
                time.sleep(1)
            else:
                log.warning(f"Cannot read {filename} after retries: {e}")
                return
    base64_data = base64.b64encode(file_data).decode("utf-8")

    # Determine MIME type
    mime_map = {
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".tiff": "image/tiff",
        ".tif": "image/tiff",
        ".pdf": "application/pdf",
        ".dcm": "application/dicom",
        ".stl": "model/stl",
        ".obj": "model/obj",
        ".nii": "application/x-nifti",
        ".nii.gz": "application/x-nifti",
    }
    mime_type = mime_map.get(ext, "application/octet-stream")

    payload = {
        "base64Data": base64_data,
        "organizationId": ORGANIZATION_ID,
        "facilityId": FACILITY_ID,
        "scriptId": SCRIPT_ID,
        "fileHash": file_hash,
        "originalFilename": filename,
        "mimeType": mime_type,
        "fileSize": file_size,
        "uploadSourceIp": get_public_ip(),
        "uploadDeviceName": get_hostname(),
        "localFilePath": filepath,
    }

    url = f"{SUPABASE_URL}/functions/v1/facility-upload-live"
    headers = {
        "Authorization": f"Bearer {ANON_KEY}",
        "apikey": ANON_KEY,
        "Content-Type": "application/json",
    }

    try:
        log.info(f"Uploading {filename} ({file_size} bytes, hash={file_hash[:12]}...)")
        resp = requests.post(url, json=payload, headers=headers, timeout=120)
        result = resp.json()

        if result.get("success"):
            processed_hashes.add(file_hash)
            save_hash_cache()
            if result.get("duplicate"):
                log.info(f"  -> Duplicate detected (existing ID: {result.get('existingId')})")
            else:
                log.info(f"  -> Uploaded OK (ID: {result.get('id')})")
        elif result.get("error", "").startswith("Script deactivated"):
            log.error(f"  -> Script has been deactivated. Stopping watcher.")
            remove_autostart()
            sys.exit(1)
        else:
            log.error(f"  -> Upload failed: {result.get('error')}")
    except Exception as e:
        log.error(f"  -> Network error: {e}")


class NewFileHandler(FileSystemEventHandler):
    def on_created(self, event):
        if event.is_directory:
            return
        try:
            filepath = event.src_path
            if not os.path.exists(filepath):
                return
            ext = get_file_ext(filepath)
            if ext in FILE_EXTENSIONS and not is_own_file(filepath):
                log.info(f"New file detected: {os.path.basename(filepath)}")
                if wait_for_file_stable(filepath):
                    upload_file(filepath)
                else:
                    log.warning(f"File not stable after timeout: {os.path.basename(filepath)}")
        except Exception as e:
            log.error(f"Error handling new file: {e}")

    def on_modified(self, event):
        if event.is_directory:
            return
        try:
            filepath = event.src_path
            if not os.path.exists(filepath):
                return
            ext = get_file_ext(filepath)
            if ext in FILE_EXTENSIONS and not is_own_file(filepath):
                if wait_for_file_stable(filepath):
                    file_hash = compute_sha256(filepath)
                    if file_hash not in processed_hashes:
                        upload_file(filepath)
        except Exception as e:
            log.error(f"Error handling modified file: {e}")

    def on_moved(self, event):
        if event.is_directory:
            return
        try:
            filepath = event.dest_path
            if not os.path.exists(filepath):
                return
            ext = get_file_ext(filepath)
            if ext in FILE_EXTENSIONS and not is_own_file(filepath):
                log.info(f"File moved/renamed: {os.path.basename(filepath)}")
                if wait_for_file_stable(filepath):
                    upload_file(filepath)
        except Exception as e:
            log.error(f"Error handling moved file: {e}")


def cleanup_old_files():
    """Delete uploaded files older than CLEANUP_AGE_HOURS."""
    cutoff = time.time() - (CLEANUP_AGE_HOURS * 3600)
    deleted = 0
    for filename in os.listdir(WATCH_FOLDER):
        filepath = os.path.join(WATCH_FOLDER, filename)
        if not os.path.isfile(filepath) or is_own_file(filepath):
            continue
        ext = get_file_ext(filepath)
        if ext not in FILE_EXTENSIONS:
            continue
        try:
            file_hash = compute_sha256(filepath)
            if file_hash not in processed_hashes:
                continue  # Not yet uploaded — keep it
            mtime = os.path.getmtime(filepath)
            if mtime < cutoff:
                os.remove(filepath)
                deleted += 1
                log.info(f"Cleanup: deleted {filename} (older than {CLEANUP_AGE_HOURS}h)")
        except OSError as e:
            log.warning(f"Cleanup: could not delete {filename}: {e}")
    if deleted:
        log.info(f"Cleanup complete: {deleted} file(s) removed")


def mark_existing_files():
    """Mark all existing files as already processed so only new files get uploaded."""
    log.info(f"Marking existing files in {WATCH_FOLDER} as known...")
    count = 0
    for filename in os.listdir(WATCH_FOLDER):
        filepath = os.path.join(WATCH_FOLDER, filename)
        if os.path.isfile(filepath) and not is_own_file(filepath):
            ext = get_file_ext(filepath)
            if ext in FILE_EXTENSIONS:
                try:
                    file_hash = compute_sha256(filepath)
                    processed_hashes.add(file_hash)
                    count += 1
                except Exception as e:
                    log.warning(f"Could not hash {filename}: {e}")
    if count:
        save_hash_cache()
    log.info(f"Marked {count} existing files as known (will not upload)")


def stop_existing_watcher():
    """Kill any previously running watcher process via PID file."""
    if not os.path.exists(PID_FILE):
        return
    try:
        with open(PID_FILE, "r") as f:
            old_pid = int(f.read().strip())
        if old_pid == os.getpid():
            return
        if platform.system() == "Windows":
            subprocess.run(["taskkill", "/F", "/PID", str(old_pid)],
                           capture_output=True, timeout=5)
        else:
            import signal
            os.kill(old_pid, signal.SIGTERM)
        log.info(f"Stopped previous watcher (PID {old_pid})")
        time.sleep(1)
    except (ValueError, ProcessLookupError, subprocess.TimeoutExpired):
        pass  # Process already gone or invalid PID
    except PermissionError:
        log.warning(f"Could not stop previous watcher (PID {old_pid}): permission denied")
    except Exception as e:
        log.warning(f"Could not stop previous watcher: {e}")


def write_pid_file():
    """Write current process ID so a newer script can stop us."""
    try:
        with open(PID_FILE, "w") as f:
            f.write(str(os.getpid()))
    except OSError as e:
        log.warning(f"Could not write PID file: {e}")


def setup_autostart():
    """Register this script to auto-start on Windows login."""
    if platform.system() != "Windows":
        return
    try:
        startup_dir = os.path.join(os.environ.get("APPDATA", ""), "Microsoft", "Windows", "Start Menu", "Programs", "Startup")
        if not os.path.isdir(startup_dir):
            log.warning("Windows Startup folder not found — skipping auto-start setup")
            return

        # Name startup bat by folder hash so each watched folder gets exactly one entry.
        # Same folder = overwrites old bat; different folder = coexists.
        folder_hash = hashlib.md5(WATCH_FOLDER.encode()).hexdigest()[:8]
        bat_name = f"purechart_watcher_{folder_hash}.bat"
        bat_path = os.path.join(startup_dir, bat_name)
        script_path = os.path.abspath(__file__)
        python_path = sys.executable

        # Write bat file that starts the watcher fully hidden (no window, no taskbar)
        with open(bat_path, "w") as f:
            f.write(f'@echo off\npowershell -Command "Start-Process \'{python_path}\' -ArgumentList \'\\"{script_path}\\"\' -WindowStyle Hidden"\n')
        log.info(f"Auto-start configured: {bat_name} (folder: {WATCH_FOLDER})")
        log.info(f"  Script will start automatically on Windows login")
    except Exception as e:
        log.warning(f"Could not setup auto-start: {e}")


def remove_autostart():
    """Remove auto-start entry for THIS folder (called when script is deactivated)."""
    if platform.system() != "Windows":
        return
    try:
        startup_dir = os.path.join(os.environ.get("APPDATA", ""), "Microsoft", "Windows", "Start Menu", "Programs", "Startup")
        folder_hash = hashlib.md5(WATCH_FOLDER.encode()).hexdigest()[:8]
        bat_name = f"purechart_watcher_{folder_hash}.bat"
        bat_path = os.path.join(startup_dir, bat_name)
        if os.path.exists(bat_path):
            os.remove(bat_path)
            log.info(f"Removed startup entry: {bat_name}")
    except Exception:
        pass


def remove_older_scripts():
    """Remove other Purechart_Watcher scripts in this folder, keeping only this one."""
    my_path = os.path.abspath(__file__)
    for filename in os.listdir(WATCH_FOLDER):
        if not filename.lower().startswith("purechart_watcher") or not filename.endswith(".py"):
            continue
        filepath = os.path.join(WATCH_FOLDER, filename)
        if os.path.abspath(filepath) == my_path:
            continue
        try:
            os.remove(filepath)
            log.info(f"Removed older script: {filename}")
        except OSError as e:
            log.warning(f"Could not remove old script {filename}: {e}")


def main():
    load_hash_cache()

    log.info("=" * 60)
    log.info("PureChart File Upload Live - Drop-In Folder Watcher")
    log.info(f"  Platform: {platform.system()} {platform.release()}")
    log.info(f"  Python: {sys.version.split()[0]}")
    log.info(f"  Observer: {'PollingObserver' if platform.system() == 'Windows' else 'Native'}")
    log.info(f"  Watching: {WATCH_FOLDER}")
    log.info(f"  Extensions: {FILE_EXTENSIONS}")
    log.info(f"  Facility: {FACILITY_ID}")
    log.info(f"  Script ID: {SCRIPT_ID}")
    log.info("=" * 60)

    stop_existing_watcher()
    write_pid_file()
    remove_older_scripts()
    setup_autostart()

    mark_existing_files()
    cleanup_old_files()

    handler = NewFileHandler()
    observer = Observer()
    observer.schedule(handler, WATCH_FOLDER, recursive=False)
    observer.start()
    log.info("Watching for new files... Press Ctrl+C to stop.")
    log.info(f"  Auto-cleanup: uploaded files deleted after {CLEANUP_AGE_HOURS}h")

    try:
        last_cleanup = time.time()
        while True:
            time.sleep(1)
            # Run cleanup once per hour
            if time.time() - last_cleanup >= 3600:
                cleanup_old_files()
                last_cleanup = time.time()
    except KeyboardInterrupt:
        observer.stop()
        log.info("Stopped.")
    observer.join()


if __name__ == "__main__":
    main()
