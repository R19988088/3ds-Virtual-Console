"""
vcoven web API — Flask server that wraps vcoven.py for Cloud Run.
Receives ROM + images + metadata, runs the build, returns the CIA.
Optionally uploads to GCS for QR code install via FBI.
"""

import os
import sys
import uuid
import json
import shutil
import hashlib
import subprocess
import tempfile
from datetime import datetime, timedelta, timezone
import sentry_sdk
from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
from google.cloud import storage
import google.auth
from google.auth.transport import requests as auth_requests
from google.auth import compute_engine

sentry_sdk.init(
    dsn=os.environ.get('SENTRY_DSN', 'https://f2bb47dbc40479ce6460c165f2c597b8@o4511139661938688.ingest.us.sentry.io/4511224581521408'),
    traces_sample_rate=1.0,
    profiles_sample_rate=0.5,
    environment=os.environ.get('ENV', 'production'),
)

app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 64 * 1024 * 1024  # 64MB max upload
CORS(app, resources={r"/*": {"origins": "*"}})

from admin import admin_bp
app.register_blueprint(admin_bp)

VCOVEN_PATH = os.path.join(os.path.dirname(__file__), 'vcoven.py')
MAX_ROM_SIZE = 64 * 1024 * 1024  # 64MB max
GCS_BUCKET = 'vcoven-builds'


def get_gcs_bucket():
    client = storage.Client()
    try:
        return client.get_bucket(GCS_BUCKET)
    except Exception:
        # Create bucket if it doesn't exist
        bucket = client.bucket(GCS_BUCKET)
        bucket.storage_class = 'STANDARD'
        return client.create_bucket(bucket, location='us-central1')


def archive_for_test_set(rom_path, params, build_ok, build_error):
    """Archive ROM + build metadata to GCS so we can replay failing builds later.
    Best-effort — never raises into the request flow."""
    try:
        with open(rom_path, 'rb') as f:
            data = f.read()
        sha = hashlib.sha256(data).hexdigest()
        bucket = get_gcs_bucket()

        rom_blob = bucket.blob(f'test-roms/roms/{sha[:16]}.gba')
        if not rom_blob.exists():
            rom_blob.upload_from_filename(rom_path, content_type='application/octet-stream')

        meta = {
            'ts': datetime.now(timezone.utc).isoformat(),
            'rom_sha256': sha,
            'rom_size': len(data),
            'build_ok': build_ok,
            'build_error': build_error,
            **params,
        }
        meta_blob = bucket.blob(f'test-roms/builds/{uuid.uuid4().hex}.json')
        meta_blob.upload_from_string(json.dumps(meta), content_type='application/json')
    except Exception as e:
        sentry_sdk.capture_exception(e)


@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'ok'})


@app.route('/upload', methods=['POST'])
def upload_file():
    """Upload a single file to GCS, return its path. Used to bypass Cloud Run body limits."""
    if 'file' not in request.files:
        return jsonify({'error': 'No file provided'}), 400

    f = request.files['file']
    file_id = uuid.uuid4().hex
    blob_name = f'uploads/{file_id}/{f.filename}'

    try:
        bucket = get_gcs_bucket()
        blob = bucket.blob(blob_name)
        blob.upload_from_file(f.stream, content_type=f.content_type or 'application/octet-stream')
        return jsonify({'path': blob_name})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/get-upload-url', methods=['POST'])
def get_upload_url():
    """Generate a signed URL for direct browser-to-GCS upload, bypassing Cloud Run's 32MiB body limit."""
    data = request.get_json()
    if not data or 'filename' not in data:
        return jsonify({'error': 'filename required'}), 400

    file_id = uuid.uuid4().hex
    filename = data['filename']
    content_type = data.get('contentType', 'application/octet-stream')
    blob_name = f'uploads/{file_id}/{filename}'

    try:
        credentials, project = google.auth.default()
        credentials.refresh(auth_requests.Request())

        bucket = get_gcs_bucket()
        blob = bucket.blob(blob_name)
        url = blob.generate_signed_url(
            version='v4',
            expiration=timedelta(minutes=15),
            method='PUT',
            content_type=content_type,
            service_account_email=credentials.service_account_email,
            access_token=credentials.token,
        )
        return jsonify({'url': url, 'path': blob_name})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/build-from-gcs', methods=['POST'])
def build_from_gcs():
    """Build CIA from files already uploaded to GCS."""
    data = request.get_json()
    if not data:
        return jsonify({'error': 'JSON body required'}), 400

    rom_path_gcs = data.get('romPath')
    icon_path_gcs = data.get('iconPath')
    banner_path_gcs = data.get('bannerPath')
    title = data.get('title', '').strip()
    title_id = data.get('titleId', '').strip()

    if not all([rom_path_gcs, icon_path_gcs, banner_path_gcs, title, title_id]):
        return jsonify({'error': 'Missing required fields'}), 400
    if len(title_id) != 16:
        return jsonify({'error': 'Title ID must be 16 hex digits'}), 400

    long_title = data.get('longTitle', '').strip()
    publisher = data.get('publisher', 'Homebrew').strip()
    product_code = data.get('productCode', 'CTR-N-HMBW').strip()
    save_type = data.get('saveType', 'auto').strip()
    want_qr = data.get('qr', False)

    work_dir = tempfile.mkdtemp(prefix='vcoven_')

    try:
        bucket = get_gcs_bucket()

        # Download files from GCS
        rom_path = os.path.join(work_dir, 'game.gba')
        icon_path = os.path.join(work_dir, 'icon.png')
        banner_path = os.path.join(work_dir, 'banner.png')
        output_path = os.path.join(work_dir, 'output.cia')

        bucket.blob(rom_path_gcs).download_to_filename(rom_path)
        bucket.blob(icon_path_gcs).download_to_filename(icon_path)
        bucket.blob(banner_path_gcs).download_to_filename(banner_path)

        # Build vcoven command
        cmd = [
            sys.executable, VCOVEN_PATH, 'build',
            rom_path,
            '--title', title,
            '--title-id', title_id,
            '--icon', icon_path,
            '--banner', banner_path,
            '--publisher', publisher,
            '--product-code', product_code,
            '-o', output_path,
        ]
        if long_title:
            cmd.extend(['--long-title', long_title])
        if save_type != 'auto':
            cmd.extend(['--save-type', save_type])

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=90, cwd=work_dir)

        build_ok = result.returncode == 0 and os.path.exists(output_path)
        build_error = None if build_ok else (result.stderr.strip() or result.stdout.strip() or 'Build failed')

        archive_for_test_set(rom_path, {
            'source': 'build-from-gcs',
            'title': title, 'long_title': long_title, 'title_id': title_id,
            'publisher': publisher, 'product_code': product_code, 'save_type': save_type,
        }, build_ok, build_error)

        if not build_ok:
            return jsonify({'error': build_error}), 500

        safe_title = ''.join(c for c in title if c.isalnum() or c in ' -_').strip()
        filename = f'{safe_title}.cia' if safe_title else 'output.cia'

        blob_name = f'builds/{uuid.uuid4().hex}.cia'
        blob = bucket.blob(blob_name)
        blob.content_disposition = f'attachment; filename="{filename}"'
        blob.upload_from_filename(output_path, content_type='application/octet-stream')
        blob.make_public()
        return jsonify({'downloadUrl': blob.public_url, 'filename': filename, 'size': os.path.getsize(output_path)})

    except subprocess.TimeoutExpired:
        return jsonify({'error': 'Build timed out (90s limit)'}), 504
    except Exception as e:
        return jsonify({'error': str(e)}), 500
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)
        # Clean up uploaded files
        for p in [rom_path_gcs, icon_path_gcs, banner_path_gcs]:
            try:
                bucket.blob(p).delete()
            except:
                pass


@app.route('/build', methods=['POST'])
def build():
    # Validate required files
    if 'rom' not in request.files:
        return jsonify({'error': 'ROM file required'}), 400
    if 'icon' not in request.files:
        return jsonify({'error': 'Icon image required'}), 400
    if 'banner' not in request.files:
        return jsonify({'error': 'Banner image required'}), 400

    rom = request.files['rom']
    icon = request.files['icon']
    banner = request.files['banner']

    # Validate metadata
    title = request.form.get('title', '').strip()
    title_id = request.form.get('titleId', '').strip()
    if not title:
        return jsonify({'error': 'Title required'}), 400
    if not title_id or len(title_id) != 16:
        return jsonify({'error': 'Title ID must be 16 hex digits'}), 400

    long_title = request.form.get('longTitle', '').strip()
    publisher = request.form.get('publisher', 'Homebrew').strip()
    product_code = request.form.get('productCode', 'CTR-N-HMBW').strip()
    save_type = request.form.get('saveType', 'auto').strip()
    want_qr = request.form.get('qr', 'false').strip().lower() == 'true'

    # Create temp workspace
    work_dir = tempfile.mkdtemp(prefix='vcoven_')

    try:
        # Save uploaded files
        rom_path = os.path.join(work_dir, 'game.gba')
        icon_path = os.path.join(work_dir, 'icon.png')
        banner_path = os.path.join(work_dir, 'banner.png')
        output_path = os.path.join(work_dir, 'output.cia')

        rom.save(rom_path)
        icon.save(icon_path)
        banner.save(banner_path)

        # Check ROM size
        if os.path.getsize(rom_path) > MAX_ROM_SIZE:
            return jsonify({'error': 'ROM too large (max 64MB)'}), 400

        # Build vcoven command
        cmd = [
            sys.executable, VCOVEN_PATH, 'build',
            rom_path,
            '--title', title,
            '--title-id', title_id,
            '--icon', icon_path,
            '--banner', banner_path,
            '--publisher', publisher,
            '--product-code', product_code,
            '-o', output_path,
        ]

        if long_title:
            cmd.extend(['--long-title', long_title])
        if save_type != 'auto':
            cmd.extend(['--save-type', save_type])

        # Run vcoven
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=90,
            cwd=work_dir,
        )

        build_ok = result.returncode == 0 and os.path.exists(output_path)
        build_error = None if build_ok else (result.stderr.strip() or result.stdout.strip() or 'Build failed')

        archive_for_test_set(rom_path, {
            'source': 'multipart',
            'title': title, 'long_title': long_title, 'title_id': title_id,
            'publisher': publisher, 'product_code': product_code, 'save_type': save_type,
        }, build_ok, build_error)

        if not build_ok:
            return jsonify({'error': build_error}), 500

        safe_title = ''.join(c for c in title if c.isalnum() or c in ' -_').strip()
        filename = f'{safe_title}.cia' if safe_title else 'output.cia'

        # If QR requested, upload to GCS and return a public URL
        if want_qr:
            try:
                bucket = get_gcs_bucket()
                blob_name = f'builds/{uuid.uuid4().hex}.cia'
                blob = bucket.blob(blob_name)
                blob.content_disposition = f'attachment; filename="{filename}"'
                blob.upload_from_filename(output_path, content_type='application/octet-stream')
                blob.make_public()

                download_url = blob.public_url

                return jsonify({
                    'downloadUrl': download_url,
                    'filename': filename,
                    'size': os.path.getsize(output_path),
                })
            except Exception as e:
                return jsonify({'error': f'QR upload failed: {str(e)}. Use Build & Download instead.'}), 500

        return send_file(
            output_path,
            mimetype='application/octet-stream',
            as_attachment=True,
            download_name=filename,
        )

    except subprocess.TimeoutExpired:
        return jsonify({'error': 'Build timed out (90s limit)'}), 504
    except Exception as e:
        return jsonify({'error': str(e)}), 500
    finally:
        try:
            shutil.rmtree(work_dir, ignore_errors=True)
        except:
            pass


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=True)
