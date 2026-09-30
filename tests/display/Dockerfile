# Образ vrunner с поддельным vrunner и X-программами вместо 1С
ARG BASE
FROM ${BASE}
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends x11-utils x11-apps \
 && rm -rf /var/lib/apt/lists/*
COPY --chmod=0755 fake-vrunner /usr/local/libexec/1c-nest/fake-vrunner
ENV ONEC_NEST_VRUNNER=/usr/local/libexec/1c-nest/fake-vrunner
