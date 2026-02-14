# Mini Docker Hub for HPE GreenLake - Ubuntu + Docker + ak user + Jupyter
FROM ubuntu:22.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install system dependencies + Docker
RUN apt-get update && apt-get install -y \
    curl wget git vim htop sudo \
    build-essential ca-certificates gnupg lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Install Docker Engine
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# Install NVIDIA Container Toolkit (ntools)
RUN curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
    && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
       sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
       tee /etc/apt/sources.list.d/nvidia-container-toolkit.list \
    && apt-get update \
    && apt-get install -y nvidia-container-toolkit \
    && nvidia-ctk runtime configure --runtime=docker \
    && systemctl restart docker \
    && rm -rf /var/lib/apt/lists/*

# Create user 'ak' with sudo (UID 1000)
RUN groupadd -g 1000 ak && \
    useradd -m -u 1000 -g 1000 -s /bin/bash ak && \
    echo "ak ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    usermod -aG docker ak

# Install Miniconda + JupyterLab (lightweight)
RUN apt-get update && apt-get install -y wget && \
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh && \
    bash /tmp/miniconda.sh -b -p /opt/conda && rm /tmp/miniconda.sh && \
    /opt/conda/bin/conda install -y python=3.11 jupyterlab && \
    /opt/conda/bin/conda clean --all -y && \
    rm -rf /var/lib/apt/lists/* && \
    ln -s /opt/conda/bin/jupyter /usr/local/bin/jupyter

ENV PATH="/opt/conda/bin:$PATH"

# Fix permissions
RUN chown -R ak:ak /opt/conda /home/ak && \
    mkdir -p /workspace && chown ak:ak /workspace && chmod 775 /workspace

# Jupyter config for ak
USER ak
RUN mkdir -p ~/.jupyter && \
    echo "c.ServerApp.root_dir = '/workspace'" > ~/.jupyter/jupyter_lab_config.py && \
    echo "c.ServerApp.ip = '0.0.0.0'" >> ~/.jupyter/jupyter_lab_config.py && \
    echo "c.ServerApp.port = 8888" >> ~/.jupyter/jupyter_lab_config.py && \
    echo "c.ServerApp.token = ''" >> ~/.jupyter/jupyter_lab_config.py && \
    echo "c.ServerApp.allow_root = True" >> ~/.jupyter/jupyter_lab_config.py

USER root

# Docker socket + data volumes
VOLUME ["/var/lib/docker", "/workspace"]
EXPOSE 8888 2375 2376

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD docker info || exit 1

# Default: start JupyterLab (or override for Docker daemon)
CMD ["jupyter", "lab", "--no-browser", "--allow-root", "--ip=0.0.0.0", "--port=8888"]
