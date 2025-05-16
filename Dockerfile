FROM ubuntu:22.04

# Set non-interactive installation
ENV DEBIAN_FRONTEND=noninteractive

# Install base development tools and SSH server
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    openssh-server \
    python3 \
    python3-pip \
    sudo \
    vim \
    wget \
    zsh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Configure SSH server
RUN mkdir /var/run/sshd
RUN echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
RUN echo 'PermitRootLogin no' >> /etc/ssh/sshd_config
RUN echo 'AllowAgentForwarding yes' >> /etc/ssh/sshd_config

# Create a non-root user for development
RUN useradd -m -s /bin/bash -G sudo developer
RUN echo 'developer ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/developer

# Set up SSH authorized_keys for the developer user
RUN mkdir -p /home/developer/.ssh && \
    chmod 700 /home/developer/.ssh && \
    touch /home/developer/.ssh/authorized_keys && \
    chmod 600 /home/developer/.ssh/authorized_keys && \
    chown -R developer:developer /home/developer/.ssh

# Set up working directory
WORKDIR /home/developer

# Expose SSH port
EXPOSE 22

# Start SSH server
CMD ["/usr/sbin/sshd", "-D"]
