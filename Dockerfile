

# Stage 2: Docker Compose and Jenkins setup
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

    # Stage 1: Build base image with browsers, drivers, and JDK

    
# Stage 3: Jenkins setup
# Use the Jenkins JDK17 base image
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
    unzip \
    gnupg \
    libgtk-3-0 \
    libx11-xcb1 \
    libdbus-glib-1-2 \
    libxt6 \
    libnss3 \
    libasound2 \
    bzip2 \
    wget \
    && curl -fsSL -o /usr/local/bin/su-exec https://github.com/tianon/gosu/releases/download/1.16/gosu-amd64 \
    && chmod +x /usr/local/bin/su-exec \
    && rm -rf /var/lib/apt/lists/*

# Firefox installation
ARG FIREFOX_VERSION=134.0.2
ARG GECKODRIVER_VERSION=v0.35.0
RUN wget -q -O /tmp/firefox.tar.bz2 https://download-installer.cdn.mozilla.net/pub/firefox/releases/$FIREFOX_VERSION/linux-x86_64/en-US/firefox-$FIREFOX_VERSION.tar.bz2 \
    && tar xjf /tmp/firefox.tar.bz2 -C /opt \
    && rm /tmp/firefox.tar.bz2 \
    && mv /opt/firefox /opt/firefox-$FIREFOX_VERSION \
    && ln -s /opt/firefox-$FIREFOX_VERSION/firefox /usr/bin/firefox

# Geckodriver installation
RUN wget -q -O /tmp/geckodriver.tar.gz https://github.com/mozilla/geckodriver/releases/download/$GECKODRIVER_VERSION/geckodriver-$GECKODRIVER_VERSION-linux64.tar.gz \
    && tar xzf /tmp/geckodriver.tar.gz -C /opt \
    && rm /tmp/geckodriver.tar.gz \
    && mv /opt/geckodriver /opt/geckodriver-$GECKODRIVER_VERSION \
    && ln -s /opt/geckodriver-$GECKODRIVER_VERSION /usr/bin/geckodriver

# Google Chrome and ChromeDriver
ARG CHROME_VERSION=132.0.6834.83
ARG CHROME_URL=https://storage.googleapis.com/chrome-for-testing-public/${CHROME_VERSION}/linux64/chrome-linux64.zip
ARG CHROMEDRIVER_URL=https://storage.googleapis.com/chrome-for-testing-public/${CHROME_VERSION}/linux64/chromedriver-linux64.zip
RUN mkdir -p /opt/chrome \
    && curl -sSL $CHROME_URL -o /tmp/chrome.zip \
    && unzip /tmp/chrome.zip -d /opt/chrome \
    && rm /tmp/chrome.zip \
    && ln -s /opt/chrome/chrome-linux64/chrome /usr/bin/google-chrome \
    && mkdir -p /opt/chromedriver \
    && curl -sSL $CHROMEDRIVER_URL -o /tmp/chromedriver.zip \
    && unzip /tmp/chromedriver.zip -d /opt/chromedriver \
    && rm /tmp/chromedriver.zip \
    && ln -s /opt/chromedriver/chromedriver-linux64/chromedriver /usr/bin/chromedriver

# Install Microsoft Edge WebDriver
RUN mkdir -p /opt/msedgedriver \
    && curl -sSL https://msedgedriver.azureedge.net/132.0.2957.115/edgedriver_linux64.zip -o /tmp/msedgedriver.zip \
    && unzip /tmp/msedgedriver.zip -d /opt/msedgedriver \
    && rm /tmp/msedgedriver.zip \
    && chmod +x /opt/msedgedriver/msedgedriver \
    && ln -s /opt/msedgedriver/msedgedriver /usr/bin/msedgedriver

# Install Microsoft Edge Browser
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/edge stable main" > /etc/apt/sources.list.d/microsoft-edge.list \
    && apt-get update && apt-get install -y microsoft-edge-stable \
    && rm -rf /var/lib/apt/lists/*

# Install Docker from official source
RUN curl -fsSL https://download.docker.com/linux/static/stable/x86_64/docker-20.10.17.tgz | tar xvz -C /tmp/ \
    && mv /tmp/docker/docker /usr/bin/docker \
    && rm -rf /tmp/docker

# Copy the docker-compose binary from the 'cmps' stage
COPY --from=cmps /usr/local/bin/docker-compose /usr/bin/docker-compose

# Copy plugins.txt and config.yaml for Jenkins provisioning
COPY plugins.txt config.yaml /provisioning/

# Copy the custom entrypoint script and make it executable
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

# Use tini to handle signals and then execute the Jenkins entrypoint script
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
