# Multi-stage build for slivka-bio-installer
ARG SLIVKA_BIO_INSTALLER_REPO=https://github.com/bartongroup/slivka-bio-installer.git
ARG SLIVKA_BIO_INSTALLER_REF=70122ece1a6c60fd74da71065302c87b532bfb9b

FROM mambaorg/micromamba:2.3.0-ubuntu24.04 AS installer

# Set working directory
WORKDIR /workspace

ARG SLIVKA_BIO_INSTALLER_REPO
ARG SLIVKA_BIO_INSTALLER_REF

# Install system dependencies needed for the installer
USER root
RUN apt-get update && apt-get install -y \
    ca-certificates \
    git \
    && rm -rf /var/lib/apt/lists/*

# Switch back to micromamba user for conda operations
USER $MAMBA_USER

# Create the installer environment
RUN micromamba create -n slivka-installer -c conda-forge \
    python=3.10 \
    click \
    ruamel.yaml \
    slivka::slivka \
    && micromamba clean --all --yes

# Clone the installer repository with submodules
USER root
RUN git clone --recurse-submodules "$SLIVKA_BIO_INSTALLER_REPO" /workspace/installer && \
    cd /workspace/installer && \
    git checkout "$SLIVKA_BIO_INSTALLER_REF" && \
    git submodule update --init --recursive

# `slivka-init` will not work if the directory already exists
# RUN mkdir -p /opt/slivka

# Run the installer
RUN eval "$(micromamba shell hook --shell bash)" && \
    micromamba activate slivka-installer && \
    cd /workspace/installer && \
    python install_cli.py \
        --non-interactive \
        --conda-exe autodetect \
        --service disembl-1.4 \
        --service aacon-1.1 \
        --service clustalo-1.2.4 \
        --service clustalw-2.1 \
        --service example \
        --service globplot-2.3 \
        --service jronn-3.1b \
        --service msaprobs-0.9.7 \
        --service muscle-3.8.1551 \
        --service muscle-5.1 \
        --service probcons-1.12 \
        --service rnaalifold-2.6.4 \
        --service tcoffee-13.41.0 \
        /opt/slivka

# Keep Jalview service labels distinct while using upstream installer content.
RUN eval "$(micromamba shell hook --shell bash)" && \
    micromamba activate slivka-installer && \
    python -c "from pathlib import Path; from ruamel.yaml import YAML; yaml=YAML(); names={'muscle-3.8.1551.service.yaml': 'MUSCLEv3', 'muscle-5.1.service.yaml': 'MUSCLEv5'}; exec(\"for filename, name in names.items():\\n    path = Path('/opt/slivka/services') / filename\\n    data = yaml.load(path)\\n    data['name'] = name\\n    yaml.dump(data, path)\")"

# Production stage
FROM mambaorg/micromamba:2.3.0-ubuntu24.04

ARG SLIVKA_BIO_INSTALLER_REPO
ARG SLIVKA_BIO_INSTALLER_REF

LABEL org.bartongroup.slivka-bio.installer.repo=$SLIVKA_BIO_INSTALLER_REPO
LABEL org.bartongroup.slivka-bio.installer.ref=$SLIVKA_BIO_INSTALLER_REF

# Install runtime dependencies
USER root
RUN apt-get update && apt-get install -y \
    supervisor \
    default-jre-headless \
    && rm -rf /var/lib/apt/lists/*

# Copy installed slivka from installer stage
COPY --from=installer /opt/slivka /opt/slivka
COPY --from=installer /opt/conda/envs /opt/conda/envs

# Copy slivka application configuration
COPY config.yaml /opt/slivka/config.yaml

# Copy slivka services runner configuration
COPY service-patches/_profiles.yaml /opt/slivka/services/_profiles.yaml

# Patch JRonn Jalview annotation generation until upstream parser handles JRonn output.
COPY scripts/jalview_parser.py /opt/slivka/scripts/jalview_parser.py
COPY --chmod=755 bin/JRonn.sh /opt/slivka/bin/JRonn.sh
COPY service-patches/jronn-3.1b.service.yaml /opt/slivka/services/

# Create log directory for slivka
RUN mkdir -p /var/log/slivka

# Copy supervisord configuration
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Create volume for services
VOLUME /opt/slivka/services

# Expose slivka port
EXPOSE 8000

# Set working directory
WORKDIR /opt/slivka

# Run supervisord
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
