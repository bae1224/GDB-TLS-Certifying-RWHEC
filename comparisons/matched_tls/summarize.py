"""Aggregate all fixed cases, including every timeout and inconclusive run."""
from pathlib import Path
from statistics import median
import csv
import hashlib
import json
import math
try:
    import tomllib
except ImportError:
    import toml as tomllib

root = Path(__file__).resolve().parent
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
read_toml = lambda p: tomllib.loads(p.read_text())
protocol = json.loads((root / 'protocol.json').read_text())
assert all(sha(root / p) == h for p, h in protocol['input_sha256'].items())
rows = []
consistent = True
for spec in protocol['cases']:
    report = read_toml(root / 'runs' / (spec['name'] + '.toml'))
    assert report['protocol_sha256'] == sha(root / 'protocol.json')
    assert all(sha(root / p) == h for p, h in report['source_sha256'].items())
    assert len(report['runs']) == 12
    for method in protocol['methods']:
        runs = [r for r in report['runs'] if r['mode'] == method]
        assert {r['repeat'] for r in runs} == {1, 2, 3}
        states = {r['status'] for r in runs}
        consistent &= len(states) == 1
        if method == 'ssr_drs_rwhe':
            for r in runs:
                assert r['lower'] >= 0
                assert r['sublevel_translation_bound'] < math.inf
                assert max(r['sublevel_left_inverse_errors']) < 1
                assert abs(r['upper'] - r['nominal_upper']) < 1e-7
                if r['lower'] > 0:
                    assert r['positive_bound_validation_performed']
                if r['status'] == 'numerically_certified':
                    assert 0 <= r['relative_gap'] <= 1e-6
        rows.append(dict(case=spec['name'], motion=spec['motion'], N=spec['N'], method=method,
            certified=all(r['status'] == 'numerically_certified' for r in runs),
            status=';'.join(sorted(states)), median_seconds=median(r['total_seconds'] for r in runs),
            min_seconds=min(r['total_seconds'] for r in runs), max_seconds=max(r['total_seconds'] for r in runs),
            timeout_repeats=sum(r['status'] == 'time_limit' for r in runs),
            relative_gap=max(r.get('relative_gap', math.inf) for r in runs)))
groups = {}
for group in ['broad', 'limited', 'real']:
    stats = {'cases': sum(s['motion'] == group for s in protocol['cases'])}
    for method in protocol['methods']:
        subset = [r for r in rows if r['motion'] == group and r['method'] == method]
        stats[method] = dict(certified=sum(r['certified'] for r in subset),
            sum_case_medians_seconds=sum(r['median_seconds'] for r in subset),
            timeout_repeats=sum(r['timeout_repeats'] for r in subset))
    groups[group] = stats
summary = dict(cases=len(protocol['cases']), measured_calls=3*len(rows), repeats=3,
    all_inputs_unchanged=True, all_repeats_consistent=consistent, groups=groups,
    protocol_sha256=sha(root / 'protocol.json'), selection=protocol['selection'],
    official_DRS_or_STRIDE_run=False,
    scope='Fixed nine-case comparison of this RWHEC reimplementation under the stated budget; no official DRS/STRIDE performance claim.')
(root / 'matched_summary.json').write_text(json.dumps(summary, indent=2))
with (root / 'matched_case_results.csv').open('w') as f:
    writer = csv.DictWriter(f, fieldnames=list(rows[0]))
    writer.writeheader(); writer.writerows(rows)
print(json.dumps(summary, indent=2))
