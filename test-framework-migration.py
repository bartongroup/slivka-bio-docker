#!/usr/bin/env python3
"""Test upgrade and restore-based rollback using disposable jobs, DB and volumes."""
import argparse
import json
import platform
from pathlib import Path
import subprocess
import time
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('baseline')
parser.add_argument('candidate')
parser.add_argument('--output-dir', required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parent
output = Path(args.output_dir)
output.mkdir(parents=True, exist_ok=True)
prefix = 'slivka-migration-' + uuid.uuid4().hex[:10]
network, mongo = prefix + '-net', prefix + '-mongo'
media, backup, rollback_media = (prefix + suffix for suffix in ('-media', '-backup', '-rollback'))
mongo_image = 'docker.io/library/mongo:7.0@sha256:41e8195b2791692695e1dc9bd21cd51d0a3af05fff8ace9304a5c1acf94f1ae1'
python = '/opt/conda/envs/slivka-installer/bin/python'
containers, volumes = [], []
report = {'baseline': args.baseline, 'candidate': args.candidate, 'host': platform.machine()}

def docker(*command, input=None):
    result = subprocess.run(['docker', *command], input=input, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f'docker {command}:\n{result.stdout}\n{result.stderr}')
    return result.stdout

def run_app(image, name, volume):
    docker('run', '-d', '--pull=never', '--name', name, '--network', network,
           '-v', volume + ':/opt/slivka/media', image)
    containers.append(name)

def smoke(name, filename, existing=None):
    command = ['exec', '-i']
    if existing:
        command += ['-e', 'SLIVKA_SMOKE_EXISTING_JOB=' + existing]
    command += [name, python]
    value = json.loads(docker(*command, input=(root / 'releases/api-smoke.py').read_text()))
    (output / filename).write_text(json.dumps(value, indent=2) + '\n')
    return value

try:
    for image in (args.baseline, args.candidate):
        arch = docker('image', 'inspect', image, '--format', '{{.Architecture}}').strip()
        expected = {'aarch64': 'arm64', 'arm64': 'arm64', 'x86_64': 'amd64'}[platform.machine()]
        assert arch == expected, f'Refusing emulation: {arch} != {expected}'
    docker('network', 'create', network)
    for volume in (media, backup, rollback_media):
        docker('volume', 'create', volume)
        volumes.append(volume)
    docker('run', '-d', '--name', mongo, '--network', network, '--network-alias', 'mongo',
           '-v', backup + ':/backup', mongo_image)
    containers.append(mongo)
    baseline = prefix + '-baseline'
    run_app(args.baseline, baseline, media)
    original = smoke(baseline, 'before.json')
    old_id = original['job']['id']
    docker('stop', baseline)
    docker('exec', mongo, 'mongodump', '--db', 'slivka', '--archive=/backup/mongo.archive')
    docker('run', '--rm', '--network', 'none', '-v', media + ':/media:ro',
           '-v', backup + ':/backup', '--entrypoint', '/bin/tar', args.baseline,
           '-C', '/media', '-cf', '/backup/media.tar', '.')
    for command in (
        ['migration', '1-nested-job-dirs', 'mongodb://mongo:27017', 'slivka', '--jobs-dir', '/opt/slivka/media/jobs'],
        ['migration', '2-tz-aware-timestamps', '--from-timezone', 'UTC', 'mongodb://mongo:27017', 'slivka'],
    ):
        log = docker('run', '--rm', '--network', network, '-v', media + ':/opt/slivka/media',
                     '-e', 'SLIVKA_HOME=/opt/slivka', '--entrypoint',
                     '/opt/conda/envs/slivka-installer/bin/slivka', args.candidate, *command)
        (output / (command[1] + '.log')).write_text(log)
    candidate = prefix + '-candidate'
    run_app(args.candidate, candidate, media)
    upgraded = smoke(candidate, 'after.json', old_id)
    assert upgraded['existing_output_hashes'] == original['output_hashes'], 'Historical outputs changed'
    report['upgrade'] = 'passed'
    docker('stop', candidate)
    docker('exec', mongo, 'mongorestore', '--drop', '--archive=/backup/mongo.archive')
    docker('run', '--rm', '--network', 'none', '-v', rollback_media + ':/media',
           '-v', backup + ':/backup:ro', '--entrypoint', '/bin/tar', args.baseline,
           '-C', '/media', '-xf', '/backup/media.tar')
    rollback = prefix + '-rollback'
    run_app(args.baseline, rollback, rollback_media)
    restored = smoke(rollback, 'rollback.json', old_id)
    assert restored['existing_output_hashes'] == original['output_hashes'], 'Restored outputs changed'
    report['rollback'] = 'passed'
    report['status'] = 'passed'
except Exception as error:
    report['status'] = 'failed'
    report['error'] = str(error)
    for name in containers:
        try:
            (output / (name + '.log')).write_text(docker('logs', name))
        except Exception:
            pass
    raise
finally:
    report['tested_at_unix'] = int(time.time())
    (output / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
    for name in reversed(containers):
        subprocess.run(['docker', 'rm', '-f', '-v', name], capture_output=True)
    for volume in volumes:
        subprocess.run(['docker', 'volume', 'rm', volume], capture_output=True)
    subprocess.run(['docker', 'network', 'rm', network], capture_output=True)
