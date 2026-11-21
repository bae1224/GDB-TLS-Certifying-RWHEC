# RWHEC_TLS_Certification

Reproduction data and code for **Grouped Deletion Bounds for Certifying
Full-Support RWHE Candidates**. This repository contains the original **44-pair
RB5-850 / GoPro HERO13 real-data experiment**.

The certificate reuses a least-squares dual solution and checks singleton,
pairwise, and cascade bounds for a fixed full-support candidate under truncated
least squares (TLS). The release contains the 44 original-resolution images,
paired robot records, processed poses, fixed X/Y, original numerical results,
and portable reproduction scripts.

Start with **[the Real44 reproduction guide](research/real44/README.md)**.

| Resource | Location |
|---|---|
| Images and paired pose records | [research/real44/data](research/real44/data) |
| Fixed paper A/B/X/Y inputs | [research/real44/input](research/real44/input) |
| Original paper results and figures | [research/real44/reference](research/real44/reference) |
| Frozen experimental protocol | [protocol.json](research/real44/protocol.json) |
| Reproduce and independently validate | [reproduce.sh](research/real44/reproduce.sh) |
| Numerical certificate implementation | [research/real44/lib](research/real44/lib) |

## Reproduce

Run from the repository root on Linux x86_64 with Python 3.10 or later:

```bash
python3 -m venv research/real44/.venv
research/real44/.venv/bin/python -m pip install -r research/real44/requirements.txt
bash scripts/install_julia_rb5.sh
RWHE_PYTHON=research/real44/.venv/bin/python bash research/real44/reproduce.sh
```

The Julia runtime is pinned to 1.10.10 and its dependencies are recorded in
`environments/rb5/Manifest.toml`. Results are written to
`research/real44/.work/reproduction/`; the published reference files are preserved.

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
provenance is in [research/real44/provenance.json](research/real44/provenance.json).
See [LICENSE](LICENSE).
