"""Record the installed framework, services and Conda tool packages without secrets."""
import importlib.metadata
import json
from pathlib import Path

environments = {}
environment_paths = [
    environment
    for base in (Path('/opt/conda/envs'), Path('/opt/slivka/conda_envs'))
    if base.is_dir()
    for environment in base.iterdir()
    if environment.is_dir()
]
for environment in sorted(environment_paths):
    packages = []
    for metadata in sorted((environment / 'conda-meta').glob('*.json')):
        package = json.loads(metadata.read_text())
        packages.append({key: package.get(key) for key in ('name', 'version', 'build', 'subdir')})
    environments[str(environment)] = packages

print(json.dumps({
    'framework_version': importlib.metadata.version('slivka'),
    'python_packages': sorted(
        (distribution.metadata['Name'], distribution.version)
        for distribution in importlib.metadata.distributions()
    ),
    'services': sorted(path.name for path in Path('/opt/slivka/services').glob('*.service.yaml')),
    'conda_environments': environments,
}, indent=2))
