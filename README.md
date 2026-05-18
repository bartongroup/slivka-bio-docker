
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

## Testing

To test the configured services, access a terminal within your `slivka-bio` container and run:

   ```bash
   eval "$(micromamba shell hook --shell bash)"
   micromamba activate slivka-installer
   slivka test-services
   ```

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

## Configuration

- The `settings.yml` file contains the configuration for `slivka-bio`. Adjust it as necessary for your environment.

## Usage

After starting the services, the `slivka-bio` API documentation will be accessible via:

- **URL:** `http://localhost:8080/api/` (or the appropriate domain/IP address)

MongoDB is also started and configured to work with `slivka-bio`.

For users looking to interact with `slivka-bio` from Python environments, including Jupyter notebooks, check out the [Python client](https://github.com/bartongroup/slivka-python-client) to get started.

## Contributing

Contributions to this project are welcome! Please fork the repository and submit a pull request with your changes.

## License

This project is licensed under the [Apache-2.0 License](LICENSE). See the LICENSE file for details.

## Funding

- This project was developed as part of the [BBSRC](https://www.ukri.org/councils/bbsrc/) funded [Dundee Resource for Protein Structure Prediction and Sequence Analysis](https://gow.bbsrc.ukri.org/grants/AwardDetails.aspx?FundingReference=BB%2fR014752%2f1) (grant number 208391/Z/17/Z).
