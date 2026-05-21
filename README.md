
# Slivka-Bio Docker

[![License](https://img.shields.io/github/license/bartongroup/slivka-bio-docker)](LICENSE)
[![GitHub issues](https://img.shields.io/github/issues/bartongroup/slivka-bio-docker)](https://github.com/bartongroup/slivka-bio-docker/issues)

This repository contains the Docker configuration for setting up `slivka-bio`. You can find a pre-built image of [slivka-bio on Docker Hub](https://hub.docker.com/r/stuartmac/slivka-bio).

## Overview

`slivka-bio` is a pre-configured instance of a `slivka` server bundled with tools for bioinformatics applications. This Dockerized setup includes `slivka-bio` and MongoDB for data storage.

You can find out more about what `slivka` is and how to use it:

- at our [public server](https://www.compbio.dundee.ac.uk/slivka/) hosted at the University of Dundee.
- on GitHub at the [Slivka-bio](https://github.com/bartongroup/slivka-bio) and [Slivka](https://github.com/bartongroup/slivka) repositories.
- in the [Slivka documentation](https://bartongroup.github.io/slivka/).

## Prerequisites

- Docker
- Docker Compose

## Installation

To get started with `slivka-bio-docker`:

1. **Clone the Repository**

   ```bash
   git clone https://github.com/bartongroup/slivka-bio-docker.git
   cd slivka-bio-docker
   ```

2. **Run with Docker Compose**

   ```bash
   docker compose up -d
   ```

This will start `slivka-bio` and MongoDB using [compose.yml](/Users/stuart/Work/Projects/Slivka/slivka-bio-docker/compose.yml).

Published ports in the current compose setup:

- `slivka-bio`: `http://localhost:4040`
- `mongo`: host port `27018` mapped to container port `27017`
- `jupyter`: `http://localhost:8888` when the `jupyter` profile is enabled

## Testing

To test the configured services, access a terminal within your `slivka-bio` container and run:

   ```bash
   eval "$(micromamba shell hook --shell bash)"
   micromamba activate slivka-installer
   slivka test-services
   ```

### Release Image Test Summary

To test one or more images on the native Docker platform and record a release summary, pass the exact image reference including tag:

   ```bash
   ./test-release-image.sh --pull docker.io/drsasp/slivka-bio:latest
   ```

The script starts `mongo` and `slivka-bio` with Docker Compose, runs `slivka test-services <service>` for each expected service, and writes JSON plus per-service logs under `release-tests/<image>/<platform>/`. The `example` service is intentionally excluded from the default release set.

To test a subset of services:

   ```bash
   ./test-release-image.sh \
     --service clustalo-1.2.4 \
     --service jronn-3.1b \
     docker.io/drsasp/slivka-bio:latest
   ```

To test a locally built image without pulling from a registry:

   ```bash
   ./test-release-image.sh slivka-bio:dev-local
   ```

The local image reference must already exist in Docker. Use `--pull` only for registry images.

Do not set `DOCKER_DEFAULT_PLATFORM` when using this script; release checks are intended to use the native platform selected by Docker.

### Compose Modes

The compose setup is split into:

- [compose.yml](/Users/stuart/Work/Projects/Slivka/slivka-bio-docker/compose.yml): base services plus an optional `jupyter` profile
- [compose.build.yml](/Users/stuart/Work/Projects/Slivka/slivka-bio-docker/compose.build.yml): builds the image locally instead of pulling it

Examples:

```bash
# Standard local test
docker compose up -d

# With Jupyter
docker compose --profile jupyter up -d

# Build locally
docker compose -f compose.yml -f compose.build.yml up -d --build

# Build locally + Jupyter
docker compose -f compose.yml -f compose.build.yml --profile jupyter up -d --build
```

### Local Image Builds

The Docker image builds `slivka-bio` by cloning the installer repository inside
the Docker build. The release build uses the Barton Group fork pinned in the
Dockerfile:

- `SLIVKA_BIO_INSTALLER_REPO`
- `SLIVKA_BIO_INSTALLER_REF`

This keeps the distribution build reproducible and makes divergence from the
upstream installer traceable. For release builds, update the pinned installer
`ARG` values in the Dockerfile and commit that change before pushing an image.

For local development, build against a different fork, branch, tag, or commit by
passing build arguments directly:

```bash
docker compose -f compose.yml -f compose.build.yml build \
  --build-arg SLIVKA_BIO_INSTALLER_REPO=https://github.com/example/slivka-bio-installer.git \
  --build-arg SLIVKA_BIO_INSTALLER_REF=feature-branch
```

The helper script exposes the same inputs:

```bash
./build.sh \
  --installer-repo https://github.com/example/slivka-bio-installer.git \
  --installer-ref feature-branch
```

The helper script refuses `--push` when installer overrides are supplied, so a
pushed image's installer dependency remains reviewable from the committed
Dockerfile.

Built images include labels for the installer source/ref and the Docker build
repository revision:

- `org.bartongroup.slivka-bio.installer.repo`
- `org.bartongroup.slivka-bio.installer.ref`
- `org.opencontainers.image.revision`
- `org.opencontainers.image.source`
- `org.bartongroup.slivka-bio-docker.dirty`

The helper script sets the Docker repository labels automatically from Git. It
also refuses `--push` when the Docker repository has uncommitted changes, so
release images are tied to a committed build recipe.

To inspect labels on a local image:

```bash
docker image inspect slivka-bio:dev-local \
  --format '{{ json .Config.Labels }}'
```

*Compatibility note: earlier versions of these instructions suggested forcing `linux/amd64` emulation on Apple Silicon Macs as a workaround for tools that were not readily available on that platform. This is no longer possible due to a QEMU/ZMQ incompatibility in the Slivka local queue path.*

## Configuration

- The `settings.yml` file contains the configuration for `slivka-bio`. Adjust it as necessary for your environment.

## Usage

After starting the services, the `slivka-bio` API documentation will be accessible via:

- **URL:** `http://localhost:4040/api/` (or the appropriate domain/IP address)

MongoDB is also started and configured to work with `slivka-bio`.

For users looking to interact with `slivka-bio` from Python environments, including Jupyter notebooks, check out the [Python client](https://github.com/bartongroup/slivka-python-client) to get started.

## Contributing

Contributions to this project are welcome! Please fork the repository and submit a pull request with your changes.

## License

This project is licensed under the [Apache-2.0 License](LICENSE). See the LICENSE file for details.

## Funding

- This project was developed as part of the [BBSRC](https://www.ukri.org/councils/bbsrc/) funded [Dundee Resource for Protein Structure Prediction and Sequence Analysis](https://gow.bbsrc.ukri.org/grants/AwardDetails.aspx?FundingReference=BB%2fR014752%2f1) (grant number 208391/Z/17/Z).
