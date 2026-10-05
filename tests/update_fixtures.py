"""Build offline updater fixtures; no download or host service access."""
import hashlib
import sys
import zipfile
from pathlib import Path

root = Path(sys.argv[1])
repo = Path(sys.argv[2])
root.mkdir(exist_ok=True)
with zipfile.ZipFile(root / 'core.zip', 'w') as archive:
    archive.writestr('xray', '#!/bin/bash\nif [[ $1 == version ]]; then echo "Xray 99.0.1"; else exit 0; fi\n')
digest = hashlib.sha256((root / 'core.zip').read_bytes()).hexdigest()
(root / 'core.dgst').write_text('SHA2-256= ' + digest + '\n')
with zipfile.ZipFile(root / 'incomplete-sh.zip', 'w') as archive:
    archive.write(repo / 'xray.sh', 'xray.sh')
for bad in (False, True):
    with zipfile.ZipFile(root / ('bad-sh.zip' if bad else 'sh.zip'), 'w') as archive:
        for file in [repo / 'xray.sh', repo / 'update_geodata.sh', *sorted((repo / 'src').glob('*'))]:
            if file.is_file():
                archive.write(file, file.relative_to(repo))
        if bad:
            archive.writestr('broken.sh', 'if then\n')
