# Use the official Debian 12 slim image as a parent image
FROM debian:12-slim

# Set non-interactive frontend for apt-get to avoid prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install only necessary dependencies
RUN apt-get update && apt-get install -y \
    ldap-utils \
    bc \
    xclip \
    zsh \
    bash \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user 'user'
RUN useradd -m -s /bin/zsh user
USER user

# Set working directory
WORKDIR /output

# Copy the linac script and the entrypoint
COPY --chown=user:user linac.sh /app/linac.sh
COPY --chown=user:user entrypoint.sh /usr/local/bin/entrypoint.sh

# Make the entrypoint executable
RUN chmod +x /usr/local/bin/entrypoint.sh

# Create a pbcopy command that uses xclip
RUN echo '#!/bin/sh' > /usr/local/bin/pbcopy && \
    echo 'xclip -selection clipboard -in' >> /usr/local/bin/pbcopy && \
    chmod +x /usr/local/bin/pbcopy

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# By default, show the linac help
CMD ["linac"]