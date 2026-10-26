"""Local customization migration. Default is preview; --apply is explicit."""
import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent/'app'))
import customization_migration as migration

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', required=True)
parser.add_argument('--target', required=True)
parser.add_argument('--baseline', help='Original shipped relative-file SHA-256 JSON manifest')
parser.add_argument('--report', help='Save the private plan to this local JSON file')
parser.add_argument('--apply', action='store_true', help='Apply the reviewed, conflict-free transfer to the candidate folder')
args = parser.parse_args()
baseline = json.loads(Path(args.baseline).read_text()) if args.baseline else None
report = migration.plan(args.source, args.target, baseline)
if args.report:
    Path(args.report).write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(migration.apply(report) if args.apply else report, indent=2))
