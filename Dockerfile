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
    net-tools \
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

# Create directory for HTTP server
RUN mkdir -p /var/www/html
RUN echo '<!DOCTYPE html><html><head><title>Dev Container Health Check</title></head><body><h1>Development Container is Healthy</h1></body></html>' > /var/www/html/index.html

# Set up working directory
WORKDIR /home/developer

# Copy health check scripts
COPY simple-http-server.sh /usr/local/bin/
COPY updated-health-check.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/simple-http-server.sh /usr/local/bin/updated-health-check.sh

# Expose SSH port and HTTP port for health checks
EXPOSE 22 80

# Start SSH server and HTTP server
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh
CMD ["/usr/local/bin/entrypoint.sh"]
