"""Record the installed framework, services and Conda tool packages without secrets."""
import importlib.metadata
import json
from pathlib import Path

environments = {}
for environment in sorted(Path('/opt/conda/envs').iterdir()):
    packages = []
    for metadata in sorted((environment / 'conda-meta').glob('*.json')):
        package = json.loads(metadata.read_text())
        packages.append({key: package.get(key) for key in ('name', 'version', 'build', 'subdir')})
    environments[environment.name] = packages

print(json.dumps({
    'framework_version': importlib.metadata.version('slivka'),
    'python_packages': sorted(
        (distribution.metadata['Name'], distribution.version)
        for distribution in importlib.metadata.distributions()
    ),
    'services': sorted(path.name for path in Path('/opt/slivka/services').glob('*.service.yaml')),
    'conda_environments': environments,
}, indent=2))
