# Use an official Ubuntu as a parent image
FROM ubuntu:20.04

# Set environment variables
ENV OUTPUT_DIR="/output"

# Set non-interactive frontend for apt-get
ENV DEBIAN_FRONTEND=noninteractive

# Install necessary packages
RUN apt-get update && \
    apt-get install -y \
    python3-pip \
    ffmpeg \
    rclone \
    curl \
    jq \
    tzdata && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install the latest version of streamlink via pip
RUN pip3 install --upgrade streamlink

# Create output directory
RUN mkdir -p "$OUTPUT_DIR"

# Copy the script into the container
COPY stream_recorder.sh /usr/local/bin/stream_recorder.sh

# Make the script executable
RUN chmod +x /usr/local/bin/stream_recorder.sh

# Set the entrypoint to the script
ENTRYPOINT ["/usr/local/bin/stream_recorder.sh"]
