FROM python:3.12-slim

RUN apt-get update && apt-get install -y curl unzip && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Download Linux x86_64 binaries
RUN mkdir -p tools && \
    # makerom
    curl -sL "https://github.com/3DSGuy/Project_CTR/releases/download/makerom-v0.19.0/makerom-v0.19.0-ubuntu_x86_64.zip" -o /tmp/makerom.zip && \
    unzip -o /tmp/makerom.zip -d tools/ && chmod +x tools/makerom && \
    # ctrtool
    curl -sL "https://github.com/3DSGuy/Project_CTR/releases/download/ctrtool-v1.3.0/ctrtool-v1.3.0-ubuntu_x86_64.zip" -o /tmp/ctrtool.zip && \
    unzip -o /tmp/ctrtool.zip -d tools/ && chmod +x tools/ctrtool && \
    # 3dstool
    curl -sL "https://github.com/dnasdw/3dstool/releases/download/v1.2.6/3dstool_linux_x86_64.tar.gz" -o /tmp/3dstool.tar.gz && \
    tar xzf /tmp/3dstool.tar.gz -C tools/ && chmod +x tools/3dstool && \
    # bannertool
    curl -sL "https://github.com/vedoot/vcoven/releases/download/v0.1.0/bannertool-linux-x86_64.tar.gz" -o /tmp/bannertool.tar.gz && \
    tar xzf /tmp/bannertool.tar.gz -C tools/ && mv tools/bannertool tools/bannertool_bin 2>/dev/null; chmod +x tools/bannertool_bin && \
    # cleanup
    rm -rf /tmp/*.zip /tmp/*.tar.gz

# Install Python deps
RUN pip install --no-cache-dir \
    pillow==11.3.0 \
    flask==3.1.1 \
    flask-cors==6.0.0 \
    gunicorn==23.0.0 \
    google-cloud-storage==3.10.1 \
    'sentry-sdk[flask]==2.40.0'

# Copy vcoven source + template
COPY vcoven.py .
COPY template/ template/
COPY server.py .
COPY admin.py .

ENV PATH="/app/tools:${PATH}"
ENV PORT=8080

EXPOSE 8080

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--timeout", "120", "--workers", "2", "--limit-request-line", "0", "--limit-request-field_size", "0", "server:app"]
