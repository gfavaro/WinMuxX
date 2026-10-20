#!/usr/bin/env python3
"""Compare repeatable process samples. Flags need three runs; never reports battery life."""
import argparse
import json
from pathlib import Path
from statistics import median


def metrics(report):
    if report.get('status') != 'completed' or report.get('elapsed_seconds', 0) < 30:
        raise ValueError('Only completed samples of at least 30 seconds can be compared')
    if report.get('sample_gaps_over_twice_interval', 0):
        raise ValueError('Interrupted sampling is inconclusive')
    return {'cpu': report['cpu_percent_one_core'],
            'wakeups': report['pkg_idle_wkups'] / report['elapsed_seconds'],
            'growth': report['footprint_last_decile_median_mib'] - report['footprint_first_decile_median_mib'],
            'footprint': report['footprint_first_decile_median_mib']}


def compare(baseline, candidates):
    old = metrics(baseline)
    values = [metrics(candidate) for candidate in candidates]
    if not values:
        raise ValueError('At least one candidate sample is required')
    new = {key: median(value[key] for value in values) for key in old}
    limits = {'cpu': old['cpu'] + max(.5, old['cpu'] * .25),
              'wakeups': old['wakeups'] + max(1, old['wakeups'] * .25),
              'growth': max(5, new['footprint'] * .05)}
    flagged = {key: {'measured': new[key], 'limit': limit} for key, limit in limits.items() if new[key] > limit}
    return {'status': ('confirmed_regression' if len(values) >= 3 else 'repeat_required') if flagged else 'passed',
            'candidate_runs': len(values), 'flags': flagged, 'baseline': old, 'candidate_medians': new,
            'scope': 'Process counters only; not watts, battery life, or WindowServer cost'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', required=True, type=Path)
    parser.add_argument('--candidate', required=True, type=Path, action='append')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    try:
        result = compare(json.loads(args.baseline.read_text()), [json.loads(p.read_text()) for p in args.candidate])
    except (ValueError, KeyError) as error:
        result = {'status': 'inconclusive', 'error': str(error)}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    return 0 if result['status'] == 'passed' else 2


if __name__ == '__main__':
    raise SystemExit(main())
