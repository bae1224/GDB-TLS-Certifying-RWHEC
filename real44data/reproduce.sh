#!/usr/bin/env bash
# Run only the published real44 experiment, preserving its reference outputs.
set -euo pipefail
rwhe_package="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
rwhe_repo="$(cd -- "$rwhe_package/.." && pwd)"
rwhe_output="${1:-$rwhe_package/.work/reproduction}"
rwhe_python="${RWHE_PYTHON:-python3}"
export OPENBLAS_NUM_THREADS=1
export JULIA_NUM_THREADS=1
export PYTHONDONTWRITEBYTECODE=1
export MPLCONFIGDIR="${MPLCONFIGDIR:-$rwhe_package/.work/matplotlib}"
"$rwhe_python" "$rwhe_package/prepare.py" --output "$rwhe_output"
bash "$rwhe_repo/scripts/julia_rb5.sh" "$rwhe_package/evaluate.jl" diagnostics "$rwhe_output"
bash "$rwhe_repo/scripts/julia_rb5.sh" "$rwhe_package/evaluate.jl" timings "$rwhe_output"
"$rwhe_python" "$rwhe_package/analyze.py" "$rwhe_output"
"$rwhe_python" "$rwhe_package/figures.py" "$rwhe_output"
