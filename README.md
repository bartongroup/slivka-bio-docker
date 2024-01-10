
# Slivka-Bio Docker Compose

[![License](https://img.shields.io/github/license/bartongroup/slivka-bio-docker)](LICENSE)
[![GitHub issues](https://img.shields.io/github/issues/bartongroup/slivka-bio-docker)]

This repository contains the Docker configuration for setting up `slivka-bio`.

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

2. **Build and Run with Docker Compose**

   ```bash
   docker-compose up -d
   ```

This will build the `slivka-bio` image and start all the services as defined in the `docker-compose.yml`.

## Configuration

- The `settings.yml` file contains the configuration for `slivka-bio`. Adjust it as necessary for your environment.

## Usage

After starting the services, `slivka-bio` will be accessible via:

- **URL:** `http://localhost:8080` (or the appropriate domain/IP address)

MongoDB is also started and configured to work with `slivka-bio`.

## Contributing

Contributions to this project are welcome! Please fork the repository and submit a pull request with your changes.

## License

This project is licensed under the [Apache-2.0 License](LICENSE). See the LICENSE file for details.

## Funding

- This project was developed as part of the [BBSRC](https://www.ukri.org/councils/bbsrc/) funded [Dundee Resource for Protein Structure Prediction and Sequence Analysis](https://gow.bbsrc.ukri.org/grants/AwardDetails.aspx?FundingReference=BB%2fR014752%2f1) (grant number 208391/Z/17/Z).
