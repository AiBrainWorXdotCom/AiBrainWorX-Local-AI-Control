"""MIT example: count completed replies locally; never store their content."""
import json
import os
from pathlib import Path
import sys

event = json.load(sys.stdin)
path = Path(os.environ['AIBRAINWORX_PLUGIN_DATA'])/'counts.json'
try:
    counters = json.loads(path.read_text())
except (OSError, ValueError):
    counters = {'replies': 0, 'characters': 0}
counters['replies'] += 1
counters['characters'] += len(event['data'].get('reply', ''))
path.write_text(json.dumps(counters), encoding='utf-8')
print(json.dumps(event))
