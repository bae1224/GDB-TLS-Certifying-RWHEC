"""Independent numerical identity checks; these are not a proof over all poses.

Requires NumPy. Does not import the Julia objective, projector, or lower bound.
Run after run_benchmark.jl, when the generated slacks/ directory is present.
"""
from pathlib import Path
import hashlib
import json
try:
    import tomllib
except ImportError:
    import toml as tomllib
import numpy as np

root = Path(__file__).resolve().parent
protocol = json.loads((root / 'protocol.json').read_text())
rng = np.random.default_rng(20261124)
read_toml = lambda p: tomllib.loads(p.read_text())

def poses(path):
    rows = np.loadtxt(path, delimiter=',')
    matrices = []
    for w, x, y, z, *_ in rows:
        matrices.append([[1-2*y*y-2*z*z, 2*x*y-2*z*w, 2*x*z+2*y*w],
                         [2*x*y+2*z*w, 1-2*x*x-2*z*z, 2*y*z-2*x*w],
                         [2*x*z-2*y*w, 2*y*z+2*x*w, 1-2*x*x-2*y*y]])
    return np.array(matrices), rows[:, 4:7]

def rotation():
    q, _ = np.linalg.qr(rng.normal(size=(3, 3)))
    if np.linalg.det(q) < 0:
        q[:, 0] *= -1
    return q

records = []
for spec in protocol['cases']:
    folder = root / spec['folder']
    meta = read_toml(folder / 'metadata.toml')
    A, ta = poses(folder / 'A.csv'); B, tb = poses(folder / 'B.csv')
    n = len(A)
    runs = read_toml(root / 'runs' / (spec['name'] + '.toml'))['runs']
    for run in (r for r in runs if r['mode'] == 'ssr_drs_rwhe'):
        prefix = root / 'slacks' / (spec['name'] + '_rep' + str(run['repeat']))
        file = Path(str(prefix) + '_slack.f64')
        S = np.fromfile(file, dtype='<f8').reshape(25*(n+1), 25*(n+1), order='F')
        W = np.loadtxt(str(prefix) + '_W.csv', delimiter=',')
        largest = 0.
        for j in range(20):
            RX, RY = rotation(), rotation()
            tX, tY = rng.normal(size=(2, 3)) * (0.1, 1., 10., 100.)[j % 4]
            er = A @ RX - RY @ B
            et = (A @ tX[..., None]).squeeze(-1) + ta - (RY @ tb[..., None]).squeeze(-1) - tY
            q = (meta['rot_weight'] * np.sum(er*er, axis=(1, 2)) +
                 meta['translation_weight'] * np.sum(et*et, axis=1)) / meta['tau2']
            theta = rng.choice([-1., 1.], n)
            if j == 0: theta[:] = 1
            if j == 1: theta[:] = -1
            if j == 2: theta[:] = -1; theta[0] = 1
            x = np.r_[tX, tY, RX.ravel(order='F'), RY.ravel(order='F'), 1.]
            phi = np.kron(np.r_[1., theta], np.linalg.solve(W, x))
            expected = np.dot((1+theta)/2, q) + ((1-theta)/2).sum() - run['target']
            error = abs(phi @ S @ phi - expected) / max(1., abs(expected))
            largest = max(largest, error)
        assert largest < 1e-6, (spec['name'], run['repeat'], largest)
        records.append(dict(case=spec['name'], repeat=run['repeat'],
            largest_relative_identity_error=float(largest),
            slack_sha256=hashlib.sha256(file.read_bytes()).hexdigest()))
report = dict(passed=True, saved_slacks_checked=len(records), physical_pose_checks=20*len(records),
    scope='Numerical identity spot checks only; global lower-bound justification is in LOWER_BOUND.md and verified_bound.jl.',
    results=records)
(root/'physical_validation.json').write_text(json.dumps(report, indent=2))
print(f'PASS: {len(records)} slacks, {20*len(records)} physical identity checks')
