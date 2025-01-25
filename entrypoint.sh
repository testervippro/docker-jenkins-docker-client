#!/usr/bin/env bash

# docker run -it -e JENKINS_USER=$(id -u) --rm -p 8080:8080 -p 50000:50000 -v $HOME/.jenkins:/var/jenkins_home -v /var/run/docker.sock:/var/run/docker.sock --name jenkins jenkins/jenkins:jdk17

DOCKER_SOCKET=/var/run/docker.sock
DOCKER_GROUP=docker

echo "Currently running as $(id). Switching to user with UID ${JENKINS_USER}."

# Check if the Docker socket exists
if [ -S ${DOCKER_SOCKET} ]; then
    # Create the jenkins user if it doesn't exist
    if ! id -u ${JENKINS_USER} > /dev/null 2>&1; then
        echo "Creating jenkins user with UID ${JENKINS_USER}."
        userdel jenkins 2>/dev/null || true
        adduser --uid ${JENKINS_USER} --disabled-password --gecos "" jenkins
    fi

    # Add the docker group and assign it to the jenkins user
    DOCKER_GID=$(stat -c '%g' ${DOCKER_SOCKET})
    if ! getent group ${DOCKER_GROUP} > /dev/null 2>&1; then
        echo "Creating docker group with GID ${DOCKER_GID}."
        groupadd --gid ${DOCKER_GID} ${DOCKER_GROUP}
    fi

    echo "Adding jenkins user to docker group."
    usermod -aG ${DOCKER_GROUP} jenkins
fi

# Configuration as Code (JCasC) setup
if [[ -v JENKINS_CAC ]]; then
    echo "Configuration as Code enabled."
    export JAVA_OPTS=-Djenkins.install.runSetupWizard=false
    export CASC_JENKINS_CONFIG=/var/jenkins_home/config.yaml

    # Install plugins if plugins.txt exists
    if [ -f /provisioning/plugins.txt ]; then
        echo "Installing plugins from /provisioning/plugins.txt."
        /bin/jenkins-plugin-cli --plugin-file /provisioning/plugins.txt
    fi

    # Copy default config if config.yaml doesn't exist
    if [ ! -e /var/jenkins_home/config.yaml ]; then
        echo "Configuration as Code: Installing default config."
        cp /provisioning/config.yaml /var/jenkins_home/config.yaml
    fi
fi

# If running as root, switch to the jenkins user
if [ "$EUID" -eq 0 ]; then
    echo "Starting /usr/local/bin/jenkins.sh as ${JENKINS_USER}."
    exec su-exec ${JENKINS_USER} /usr/local/bin/jenkins.sh
else
    echo "Already running as a non-root user. Starting Jenkins directly."
    exec /usr/local/bin/jenkins.sh
fi