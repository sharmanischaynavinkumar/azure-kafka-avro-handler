# Use the official Azure Functions Python base image
FROM mcr.microsoft.com/azure-functions/python:4-python3.11

RUN set -x

USER root

# Set environment variables for development
ENV AzureFunctionsJobHost__Logging__Console__IsEnabled=true

# Install system dependencies
RUN apt-get update && apt-get install -y \
    procps \
    net-tools \
    docker.io \
    docker-compose \
    build-essential \
    jq \
    curl \
    wget \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install Azure Functions Core Tools
RUN curl -sSL https://packages.microsoft.com/keys/microsoft.asc | apt-key add - \
    && echo "deb [arch=amd64] https://packages.microsoft.com/debian/11/prod bullseye main" > /etc/apt/sources.list.d/microsoft.list \
    && apt-get update \
    && apt-get install -y azure-functions-core-tools-4

# Copy only requirements files for dependency installation (optimization for layer caching)
COPY requirements.txt requirements_dev.txt ./

# Virtual environment by updating PATH
ENV VIRTUAL_ENV="/workspaces/venv"
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Create virtual environment and install all Python dependencies in one layer
RUN python -m venv $VIRTUAL_ENV \
    && . $VIRTUAL_ENV/bin/activate \
    && python -m pip install --no-cache-dir --upgrade pip setuptools wheel \
    && pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir -r requirements_dev.txt \
    && pip list

RUN set +x