# Загрузчик дистрибутивов 1С с releases.1c.ru: yard и onec-download поверх образа onescript.
# Файлов 1С в образе нет.
#   docker build --build-arg BASE_IMAGE=<образ onescript> -t downloader downloader
#   docker run --rm -e ONEC_LOGIN -e ONEC_PASSWORD -v "$PWD/distr:/distr" downloader platform 8.3.27.2342 /distr
# Этим образом скачивают дистрибутив образы с платформой и EDT, см. стадию distr в их Dockerfile.

ARG BASE_IMAGE=ghcr.io/yellow-hammer/1c-nest/onescript:2.1.0

FROM ${BASE_IMAGE}
ARG YARD_VERSION=1.14.0
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends jq unzip \
 && rm -rf /var/lib/apt/lists/*
# Хаб пакетов иногда не отвечает
RUN for try in 1 2 3; do \
      timeout 600 opm install "yard@${YARD_VERSION}" && break; \
      [ "$try" = 3 ] && exit 1; \
      sleep 30; \
    done \
 && yard --version
COPY --chmod=0755 onec-download /usr/local/bin/onec-download
LABEL org.opencontainers.image.title="yard ${YARD_VERSION}" \
      org.opencontainers.image.version="${YARD_VERSION}"
ENTRYPOINT ["onec-download"]
CMD ["help"]
