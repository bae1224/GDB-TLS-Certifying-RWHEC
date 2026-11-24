"""Create a fresh run directory without copying or overwriting scored outputs."""
from pathlib import Path
import shutil
import sys

root = Path(__file__).resolve().parent
dest = Path(sys.argv[1]).resolve()
if dest.exists():
    raise SystemExit(f'Refusing to overwrite {dest}')
dest.mkdir(parents=True)
for path in root.iterdir():
    if path.name in {'cases', 'environment'}:
        shutil.copytree(path, dest / path.name)
    elif path.is_file() and (path.suffix in {'.jl', '.py', '.md'} or
                           path.name in {'cases.tsv', 'protocol.json', 'LICENSE', 'UPSTREAM.json', '.gitignore'}):
        shutil.copy2(path, dest / path.name)
print(dest)
