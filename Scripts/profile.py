#!/usr/bin/env python3
"""Sample app CPU and resident memory; physical footprint is in --diagnostics JSON."""
import argparse, json, statistics, subprocess, time
from pathlib import Path
parser = argparse.ArgumentParser()
parser.add_argument('--pid', type=int, required=True)
parser.add_argument('--seconds', type=int, default=30)
parser.add_argument('--diagnostics', default='/tmp/snow-desktop-diagnostics.json')
parser.add_argument('--output')
args = parser.parse_args()
samples = []
for _ in range(args.seconds):
    row = subprocess.check_output(['ps', '-p', str(args.pid), '-o', '%cpu=,rss='], text=True).split()
    samples.append((float(row[0]), int(row[1]) / 1024))
    time.sleep(1)
report = {'samples': len(samples), 'cpuMeanPercentOfOneCore': round(statistics.mean(s[0] for s in samples), 2),
          'cpuMaxPercentOfOneCore': max(s[0] for s in samples), 'residentMaxMBIncludingSharedPages': round(max(s[1] for s in samples), 1)}
path = Path(args.diagnostics)
if path.exists(): report['latestAppDiagnostics'] = json.loads(path.read_text())
text = json.dumps(report, indent=2)
if args.output: Path(args.output).write_text(text + '\n')
print(text)
