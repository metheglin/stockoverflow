FROM ruby:4.0

# System dependencies
RUN apt-get update && apt-get install -y \
    git \
    openssh-client \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -s /bin/bash sandbox

# Install Claude Code CLI as sandbox user
USER sandbox
RUN curl -fsSL https://claude.ai/install.sh | bash
USER root

# Workspace (owned by sandbox)
RUN mkdir -p /workspace/project && chown -R sandbox:sandbox /workspace

# Config mount point (readable by sandbox)
RUN mkdir -p /config && chown sandbox:sandbox /config

# Entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace

USER sandbox
ENV PATH="/home/sandbox/.local/bin:${PATH}"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
