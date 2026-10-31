"""Package and smoke-test the native release executable."""
import os
from native_linkage import verify_linkage
from pathlib import Path
import platform
import subprocess
import tarfile
import zipfile

system, arch, extension = (os.environ[name] for name in ('RELEASE_PLATFORM', 'RELEASE_ARCH', 'RELEASE_EXTENSION'))
expected_system = {'Linux': 'Linux', 'Darwin': 'Darwin', 'Windows': 'Windows'}[system]
assert platform.system() == expected_system
actual_arch = platform.machine().lower()
assert actual_arch in ({'x86_64', 'amd64'} if arch == 'x86_64' else {'arm64', 'aarch64'}), actual_arch
assert extension == ('zip' if system == 'Windows' else 'tar.gz')
executable = 'gdpw.exe' if system == 'Windows' else 'gdpw'
binary = Path('cli/target')/os.environ['RUST_TARGET']/'release'/executable
identity = f"gdpw version {os.environ['VERSION']}"
assert subprocess.check_output([str(binary), '--version'], text=True).strip() == identity
import json
assert json.loads(subprocess.check_output([str(binary), '--build-info'], text=True)) == dict(version=os.environ['VERSION'],commit=os.environ['COMMIT'])
Path('dist').mkdir(exist_ok=True)
archive = Path('dist')/f'gdpw_{system}_{arch}.{extension}'
license = Path('LICENSE')
if extension == 'zip':
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as bundle:
        bundle.write(binary, executable)
        bundle.write('README.md', 'README.md')
        bundle.write(license, 'LICENSE')
else:
    with tarfile.open(archive, 'w:gz') as bundle:
        bundle.add(binary, arcname=executable)
        bundle.add('README.md', arcname='README.md')
        bundle.add(license, arcname='LICENSE')

verify_linkage(binary, system)
