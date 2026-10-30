# Pterodactyl / Pelican Java yolk with an Azul Zulu JDK (the CRaC build where Azul has one).
# The base is Azul's own image, pinned by digest. The rest keeps the pelican-eggs/yolks java contract:
# tini -g as PID 1, /entrypoint.sh evals STARTUP, user "container", workdir /home/container, STOPSIGNAL SIGINT.
# The build stops when tini, entrypoint.sh or the JDK differ from what the build args expect.
ARG ZULU_IMAGE=docker.io/azul/zulu-openjdk:25.0.4.1-25.36-jdk-crac@sha256:8c4ae0cd57b893516042f073f1c4487a9e3653d371ae3cc142ba0fa9d8321991
FROM ${ZULU_IMAGE}

# The java -version line that this JDK must print (for example "Zulu25.36+205-CRaC-CA").
ARG ZULU_EXPECT=Zulu25.36+205-CRaC-CA
# tini 0.19.0-1 from the Ubuntu archive, the same bytes as in ghcr.io/parkervcp/yolks:java_25.
ARG TINI_SHA256=274f2bed211788a4fcb52d14f93ab6e7c44528493b56af5812a1cfe8ae1d2064
# pelican-eggs/yolks entrypoint.sh, unchanged.
ARG ENTRYPOINT_SHA256=ed1c41275861bcfe704bf18754f5fd087e125b9672e8eca563486c3312099578

LABEL org.opencontainers.image.source="https://github.com/valhallamcio/yolks"
LABEL org.opencontainers.image.description="Pterodactyl Java yolks with Azul Zulu (CRaC builds for 17, 21 and 25)"
LABEL org.opencontainers.image.licenses=MIT

# libnuma1: server flags often carry -XX:+UseNUMA, and the JVM disables NUMA without it (README: seccomp note).
# /opt/java/openjdk: the Temurin yolk path. Azul installs the JDK in a versioned dir. The link keeps old tool
# paths working, and JAVA_HOME keeps the versioned path.
RUN set -eux \
 && apt-get update -y \
 && apt-get install -y --no-install-recommends curl lsof ca-certificates openssl git tar sqlite3 fontconfig tzdata \
    iproute2 libfreetype6 tini=0.19.0-1 zip unzip jq libnuma1 locales \
 && locale-gen en_US.UTF-8 \
 && rm -rf /var/lib/apt/lists/* \
 && echo "${TINI_SHA256}  /usr/bin/tini" | sha256sum -c - \
 && java -version 2>&1 | grep -F -- "${ZULU_EXPECT}" \
 && mkdir -p /opt/java \
 && if [ ! -e /opt/java/openjdk ]; then ln -s "$JAVA_HOME" /opt/java/openjdk; fi \
 && useradd -m -d /home/container -s /bin/bash container

ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

COPY --chmod=755 ./entrypoint.sh /entrypoint.sh
RUN echo "${ENTRYPOINT_SHA256}  /entrypoint.sh" | sha256sum -c -

USER container
ENV USER=container HOME=/home/container
WORKDIR /home/container

STOPSIGNAL SIGINT

ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
