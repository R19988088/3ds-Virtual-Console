"""Admin API endpoints for vcoven dashboard — build stats, feedback, errors.

All stats are served from Firestore (all-time, append-only) rather than GCS
(auto-deletes after 1 day). This keeps counters consistent with every build ever
logged from the frontend."""

import os
import json
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from flask import Blueprint, jsonify

admin_bp = Blueprint('admin', __name__)

FB_PROJECT = 'vcoven-web'
FB_KEY = os.environ.get('FB_KEY', 'AIzaSyCioXpCJN2d2cJobdox8k3KuTc7hwMrmfo')
FB_BASE = f'https://firestore.googleapis.com/v1/projects/{FB_PROJECT}/databases/(default)/documents'


def _post_json(url, body):
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode('utf-8'),
        headers={'Content-Type': 'application/json'},
        method='POST',
    )
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read().decode('utf-8'))


def _get_json(url):
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.loads(r.read().decode('utf-8'))


def _firestore_count(where=None):
    """COUNT aggregation over the `builds` collection, optionally filtered."""
    query = {'from': [{'collectionId': 'builds'}]}
    if where is not None:
        query['where'] = where
    body = {
        'structuredAggregationQuery': {
            'structuredQuery': query,
            'aggregations': [{'alias': 'total', 'count': {}}],
        }
    }
    url = f'{FB_BASE}:runAggregationQuery?key={FB_KEY}'
    data = _post_json(url, body)
    for item in data:
        if 'result' in item:
            return int(item['result']['aggregateFields']['total']['integerValue'])
    return 0


def _firestore_list_all(page_size=300):
    """Paginate through all `builds` docs, newest first."""
    docs = []
    page_token = None
    while True:
        params = {
            'pageSize': str(page_size),
            'orderBy': 'timestamp desc',
            'key': FB_KEY,
        }
        if page_token:
            params['pageToken'] = page_token
        url = f'{FB_BASE}/builds?{urllib.parse.urlencode(params)}'
        data = _get_json(url)
        docs.extend(data.get('documents', []))
        page_token = data.get('nextPageToken')
        if not page_token:
            break
    return docs


def _field(doc_fields, key, kind='stringValue', default=''):
    v = doc_fields.get(key, {})
    return v.get(kind, default)


@admin_bp.route('/admin/stats', methods=['GET'])
def stats():
    # All-time total via aggregation (1 read per 1000 docs counted)
    try:
        total_builds = _firestore_count()
    except Exception:
        total_builds = 0

    # Today's count via aggregation with a timestamp filter
    today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    today_filter = {
        'fieldFilter': {
            'field': {'fieldPath': 'timestamp'},
            'op': 'GREATER_THAN_OR_EQUAL',
            'value': {'timestampValue': today_start.isoformat().replace('+00:00', 'Z')},
        }
    }
    try:
        today_builds = _firestore_count(today_filter)
    except Exception:
        today_builds = 0

    # Full doc list for chart + size sum (used by admin.html per-day chart)
    try:
        all_docs = _firestore_list_all()
    except Exception:
        all_docs = []

    total_size = 0
    recent = []
    for doc in all_docs:
        f = doc.get('fields', {})
        size = int(_field(f, 'outputSize', 'integerValue', '0') or 0)
        total_size += size
        recent.append({
            'name': _field(f, 'outputFile'),
            'size': size,
            'created': _field(f, 'timestamp', 'timestampValue'),
        })

    return jsonify({
        'total_builds': total_builds,
        'today_builds': today_builds,
        'total_size_mb': round(total_size / 1024 / 1024, 1),
        'builds': recent,
    })
