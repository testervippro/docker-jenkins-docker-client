# Build Stage for Docker Compose
FROM python:3.10-alpine3.19 AS cmps
RUN apk -U --no-cache add \
   make gcc musl-dev libffi-dev openssl-dev zlib-dev \
   git \
   rust cargo && \
   pip install pycrypto

ARG compose_version=1.29.2

RUN git clone --depth 1 --branch ${compose_version} https://github.com/docker/compose.git /code/compose

RUN cd /code/compose && \
    sed -i "s/PyYAML==5.4.1/PyYAML>=5.3,<7/g" requirements.txt && \
    pip --no-cache-dir install -r requirements.txt -r requirements-dev.txt --ignore-installed && \
    git rev-parse --short HEAD > compose/GITSHA

RUN git clone --depth 1 --single-branch --branch v5.13.2 https://github.com/pyinstaller/pyinstaller.git /tmp/pyinstaller \
    && cd /tmp/pyinstaller/bootloader \
    && CFLAGS="-Wno-stringop-overflow -Wno-stringop-truncation" python3 ./waf configure --no-lsb all \
    && pip install .. \
    && rm -Rf /tmp/pyinstaller

RUN cd /code/compose && \
    pyinstaller --clean docker-compose.spec && \
    mv dist/docker-compose /usr/local/bin/docker-compose && \
    chmod +x /usr/local/bin/docker-compose

# Jenkins Stage
FROM jenkins/jenkins:jdk17

LABEL maintainer="trion development GmbH <info@trion.de>"

# Set environment variables for Jenkins
ENV JENKINS_USER=jenkins CASC_JENKINS_CONFIG=/var/jenkins_home/config.yaml

# Set user to root for package installation
USER root

# Install tini, su-exec, and other necessary dependencies
RUN apt-get update && \
    apt-get install -y tini \
    passwd \
    curl \
    && curl -fsSL -o /usr/local/bin/su-exec https://github.com/tianon/gosu/releases/download/1.16/gosu-amd64 \
    && chmod +x /usr/local/bin/su-exec \
    && rm -rf /var/lib/apt/lists/*

# Use tini to handle signals and then execute the Jenkins entrypoint script
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]

# Copy the docker-compose binary from the 'cmps' stage
COPY --from=cmps /usr/local/bin/docker-compose /usr/bin/docker-compose

# Install Docker from official source
RUN curl -fsSL https://download.docker.com/linux/static/stable/x86_64/docker-20.10.17.tgz | tar xvz -C /tmp/ \
    && mv /tmp/docker/docker /usr/bin/docker \
    && rm -rf /tmp/docker

# Copy plugins.txt and config.yaml for Jenkins provisioning
COPY plugins.txt config.yaml /provisioning/

# Copy the custom entrypoint script and make it executable
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh