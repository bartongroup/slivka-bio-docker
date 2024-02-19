# Use Miniconda as the base image
FROM continuumio/miniconda3

# Set a working directory
WORKDIR /app

# Install supervisord
RUN apt-get update && apt-get install -y supervisor default-jre-headless

# Install slivka-bio using Conda
RUN conda install anaconda-client -n base \
    && conda env create slivka/compbio-services

# Copy Slivka config
COPY ./settings.yml /opt/conda/envs/compbio-services/var/slivka-bio/

# Copy supervisord config
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Expose the port Slivka is running on
EXPOSE 8000

# Run supervisord
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
