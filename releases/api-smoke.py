"""Exercise the actual HTTP API and local queue, not just process startup."""
import json
import hashlib
import os
import time
import urllib.parse
import urllib.request

base = 'http://127.0.0.1:4040/api/v1.1'
# Podman inherits host proxies; loopback checks must stay inside this container.
http = urllib.request.build_opener(urllib.request.ProxyHandler({}))

def request(path, data=None):
    url = path if path.startswith('http') else (
        'http://127.0.0.1:4040' + path if path.startswith('/api/') else base + path
    )
    body = None if data is None else urllib.parse.urlencode(data).encode()
    with http.open(url, data=body, timeout=15) as response:
        return json.load(response)

for attempt in range(60):
    try:
        version = request('/version')
        services = request('/services')['services']
        break
    except Exception:
        if attempt == 59:
            raise
        time.sleep(2)

# Multipart upload is required for the file input. No third-party HTTP client
# is needed, so this also runs on the original compatibility image.
boundary = 'slivka-release-smoke-boundary'
sequence = '>one\nMKTAYIAKQRQISFVKSHFSRQ\n>two\nMKTAYIAKQRQISFVKSHFSRK\n'
body = (
    f'--{boundary}\r\nContent-Disposition: form-data; name="input"; filename="input.fa"\r\n'
    f'Content-Type: text/plain\r\n\r\n{sequence}\r\n--{boundary}--\r\n'
).encode()
req = urllib.request.Request(
    base + '/services/clustalo-1.2.4/jobs', data=body,
    headers={'Content-Type': 'multipart/form-data; boundary=' + boundary},
)
with http.open(req, timeout=30) as response:
    job = json.load(response)
    location = response.headers['Location']
for attempt in range(120):
    job = request(location)
    if job['finished']:
        break
    time.sleep(1)
else:
    raise RuntimeError('ClustalO API job did not finish within 120 seconds')
assert job['status'] == 'COMPLETED', job
files = request(location + '/files')['files']
assert any(output['path'] == 'output.txt' for output in files), files
def output_hashes(output_files):
    hashes = {}
    for output in output_files:
        content_url = urllib.parse.urljoin('http://127.0.0.1:4040', output['@content'])
        with http.open(content_url, timeout=15) as response:
            content = response.read()
        if output['path'] == 'output.txt':
            assert content and b'MKTAY' in content, output
        hashes[output['path']] = hashlib.sha256(content).hexdigest()
    return hashes

result = {'version': version, 'service_count': len(services), 'job': job, 'files': files,
          'output_hashes': output_hashes(files)}
if os.environ.get('SLIVKA_SMOKE_EXISTING_JOB'):
    existing = request('/jobs/' + os.environ['SLIVKA_SMOKE_EXISTING_JOB'])
    assert existing['status'] == 'COMPLETED', existing
    existing_files = request('/jobs/' + existing['id'] + '/files')['files']
    result['existing_job'] = existing
    result['existing_output_hashes'] = output_hashes(existing_files)
print(json.dumps(result, indent=2))
