# RWHEC_TLS_Certification

Data and code for the original **44-pair RB5-850 / GoPro HERO13 experiment**
in the KRoC manuscript below.

## RWHEC

Robot-world and hand-eye calibration (RWHEC) jointly estimates the camera pose
relative to the robot hand (`X`) and the target pose relative to the robot base
(`Y`) from paired observations satisfying `A_i X = Y B_i`.
[Wise et al.](https://arxiv.org/abs/2507.23045v2) generalize this formulation to
multiple sensors/targets and unknown monocular scale, using a semidefinite
programming (SDP) relaxation to certify least-squares (LS) optimality.

## KRoC paper

**Grouped Deletion Bounds for Certifying Full-Support RWHE Candidates** checks
whether a fixed LS candidate is also optimal under truncated least squares (TLS).
For full-support candidates, whose observation costs are all below the cutoff,
it reuses the LS dual solution and combines singleton and pairwise deletion
bounds in a cascade. This gives a sufficient numerical certificate without
enumerating observation-deletion sets.

## Data and code

Start with **[the Real44 reproduction guide](real44data/README.md)**.

| Resource | Location |
|---|---|
| Images and paired pose records | [real44data/data](real44data/data) |
| Fixed paper A/B/X/Y inputs | [real44data/input](real44data/input) |
| Original paper results and figures | [real44data/reference](real44data/reference) |
| Frozen experimental protocol | [protocol.json](real44data/protocol.json) |
| Reproduce and independently validate | [reproduce.sh](real44data/reproduce.sh) |
| Numerical certificate implementation | [real44data/lib](real44data/lib) |

## Reproduce

Run from the repository root on Linux x86_64 with Python 3.10 or later:

```bash
python3 -m venv real44data/.venv
real44data/.venv/bin/python -m pip install -r real44data/requirements.txt
bash scripts/install_julia_rb5.sh
RWHE_PYTHON=real44data/.venv/bin/python bash real44data/reproduce.sh
```

The Julia runtime is pinned to 1.10.10 and its dependencies are recorded in
`rb5/Manifest.toml`. Results are written to
`real44data/.work/reproduction/`; the published reference files are preserved.

The run checks 75 cutoffs, performs 324 warmed timing calls (12 cutoffs × 3 methods
× 9 repetitions), independently reconstructs the costs and bounds in NumPy,
compares certificate decisions with the paper, and generates figures. Hardware
connection is not required.

## Recorded Real44 results

- AX=YB consistency RMS: **7.777714 mm**, **0.959949°**.
- At the 16 tested cutoffs from **3.30 to 4.05**, pairwise and cascade certify
  while singleton is inconclusive. Singleton certifies from tested cutoff 4.10.
- At cutoff 4, the original median runtimes were **11.9 ms / inconclusive** for
  singleton, **29.3 ms / certified** for pairwise, and **28.1 ms / certified** for
  cascade. New runtime measurements depend on the execution environment.

These are floating-point certificates for the stated objective and consistency
residuals, not physical ground-truth calibration accuracy. The 75 cutoffs are a
sensitivity analysis on the same 44 observations. Inconclusive does not imply
suboptimality. Other acquisition sessions and synthetic experiments are outside
this repository's release scope.

Support code comes from the existing RB5 calibration repository; exact source
commit and file hashes are in [UPSTREAM.json](UPSTREAM.json). Experimental code
provenance is in [real44data/provenance.json](real44data/provenance.json).
See [LICENSE](LICENSE).
