"""Benchmark a save with an isolated mod directory and report tick timings."""
import argparse
import csv
import json
from pathlib import Path
import shutil
import statistics
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('factorio', type=Path)
parser.add_argument('mods', type=Path, help='Installed mod directory, including mod list and settings')
parser.add_argument('save', type=Path)
parser.add_argument('--mod', type=Path, default=Path(__file__).resolve().parents[1], help='Companion checkout or release ZIP')
parser.add_argument('--ticks', type=int, default=1800)
parser.add_argument('--runs', type=int, default=3)
args = parser.parse_args()
root = Path(tempfile.mkdtemp(prefix='entourage-benchmark-'))
mods = root / 'mods'
mods.mkdir()
for path in args.mods.iterdir():
    if (path.is_dir() or path.suffix == '.zip') and not path.name.startswith('companion-drones-luan'):
        (mods / path.name).symlink_to(path.resolve())
source = args.mod.resolve()
if source.is_dir():
    shutil.copytree(source, mods / source.name, ignore=shutil.ignore_patterns('.git', 'art', 'docs', 'tests'))
else:
    (mods / source.name).symlink_to(source)
for name in ['mod-list.json', 'mod-settings.dat']:
    shutil.copy2(args.mods / name, mods / name)
(root / 'config.ini').write_text('[path]\nread-data=__PATH__system-read-data__\nwrite-data=' + str(root) + '\n')
print('Artifacts:', root, flush=True)
with (root / 'benchmark.log').open('w') as log:
    subprocess.run([str(args.factorio), '--config', str(root / 'config.ini'), '--mod-directory', str(mods),
        '--benchmark', str(args.save), '--benchmark-ticks', str(args.ticks), '--benchmark-runs', str(args.runs),
        '--benchmark-verbose', 'all'], stdout=log, stderr=subprocess.STDOUT, timeout=300, check=True)
rows, keys = [], None
for line in (root / 'benchmark.log').read_text().splitlines():
    if line.startswith('tick,timestamp,'):
        keys = next(csv.reader([line]))
    elif keys and line.startswith('t') and line.split(',')[0][1:].isdigit():
        rows.append(dict(zip(keys, next(csv.reader([line])))))
assert len(rows) == args.ticks * args.runs, 'Missing benchmark ticks; inspect benchmark.log'
result = {'ticks': len(rows)}
for name in ['wholeUpdate', 'scriptUpdate']:
    values = sorted(float(row[name]) / 1e6 for row in rows)
    result[name] = {'mean_ms': statistics.mean(values), 'p99_ms': values[int(len(values) * .99)],
        'max_ms': max(values), 'ticks_above_16_67': sum(value > 1000 / 60 for value in values)}
(root / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
