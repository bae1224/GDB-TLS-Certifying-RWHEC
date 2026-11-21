"""Verify the released real44 inputs and prepare the frozen cutoff sweep."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import numpy as np

ROOT = Path(__file__).resolve().parent


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify():
    hashes = json.loads((ROOT/'SHA256.json').read_text())
    for name, expected in hashes.items():
        assert digest(ROOT/name) == expected, f'Changed or missing release file: {name}'
    data = ROOT/'data'
    ids = json.loads((ROOT/'input/sample_ids.json').read_text())
    entries = json.loads((data/'manifest.json').read_text())['samples']
    samples = [json.loads(p.read_text()) for p in sorted((data/'samples').glob('*.json'))]
    assert len(ids) == len(set(ids)) == len(entries) == len(samples) == 44
    assert [s['sample_id'] for s in samples] == [e['sample_id'] for e in entries] == ids
    assert len(list((data/'images').glob('*.JPG'))) == 44
    for s, e in zip(samples, entries):
        assert s['image'] == e['image'] and s['robot_record'] == e['robot_record']
        assert digest(data/e['image']) == s['image_sha256']
        assert digest(data/e['robot_record']) == s['robot_record_sha256']
        robot = json.loads((data/e['robot_record']).read_text())
        assert robot['sample_id'] == s['sample_id']
        assert np.allclose(robot['T_base_hand'], s['T_base_hand'], atol=1e-12, rtol=0)
    for letter in ['A','B']:
        assert np.allclose(np.loadtxt(ROOT/f'input/{letter}.csv', delimiter=','),
                           np.loadtxt(data/f'combined/tag_0_cam_0_{letter}.csv', delimiter=','),
                           atol=1e-14, rtol=0)
    constraints = ROOT.parent/'src/rotation_sdp_constraints.jl'
    provenance = json.loads((ROOT/'provenance.json').read_text())
    assert digest(constraints) == provenance['rotation_constraints_sha256']
    print(f'Verified {len(hashes)} release files and all 44 image/robot/pose pairings.', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify-only', action='store_true')
    parser.add_argument('--output', type=Path, default=ROOT/'.work/reproduction')
    args = parser.parse_args()
    verify()
    if args.verify_only:
        return
    output = args.output.resolve()
    if output.exists():
        raise SystemExit(f'Output already exists; choose a new directory: {output}')
    protocol = json.loads((ROOT/'protocol.json').read_text())
    rows = []
    for tau in protocol['diagnostic_cutoffs']:
        name = f'cutoff_{tau:.2f}'.replace('.', 'p')
        folder = output/'cases'/name
        folder.mkdir(parents=True)
        for filename in ['A.csv','B.csv','X_candidate.csv','Y_candidate.csv']:
            shutil.copy2(ROOT/'input'/filename, folder/filename)
        (folder/'metadata.toml').write_text(f'N = 44\nrot_weight = 125.0\ntranslation_weight = 5000.0\ntau2 = {tau}\n')
        rows.append(f'{name}\t{folder}\t{tau}\t{int(tau in protocol["timed_cutoffs"])}')
    (output/'cases.tsv').write_text('\n'.join(rows)+'\n')
    print(f'Prepared {len(rows)} cutoffs in {output}', flush=True)


if __name__ == '__main__':
    main()
