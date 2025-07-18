# Multi-stage build for slivka-bio-installer
FROM mambaorg/micromamba:2.3.0-ubuntu24.04 AS installer

# Set working directory
WORKDIR /workspace

# Install system dependencies needed for the installer
USER root
RUN apt-get update && apt-get install -y \
    git \
    # docker.io \
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
# RUN git clone --recurse-submodules https://github.com/proteinverse/slivka-bio-installer.git /workspace/installer
COPY slivka-bio-installer/slivka-bio-installer /workspace/installer

# `slivka-init` will not work if the directory already exists
# RUN mkdir -p /opt/slivka

# Run the installer
RUN eval "$(micromamba shell hook --shell bash)" && \
    micromamba activate slivka-installer && \
    cd /workspace/installer && \
    python install.py --unattended --prefer-installer conda --overwrite --on-error skip /opt/slivka

# Production stage
FROM mambaorg/micromamba:2.3.0-ubuntu24.04

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
COPY slivka-bio-docker/config.yaml /opt/slivka/config.yaml

# Create log directory for slivka
RUN mkdir -p /var/log/slivka

# Copy supervisord configuration
COPY slivka-bio-docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Create volume for services
VOLUME /opt/slivka/services

# Expose slivka port
EXPOSE 8000

# Set working directory
WORKDIR /opt/slivka

# Run supervisord
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]