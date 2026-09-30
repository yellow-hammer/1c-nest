# check=skip=InvalidDefaultArgInFrom
# vanessa-runner и Vanessa-ADD: слой поверх образа с клиентом 1С и OneScript (слой onescript).
#   docker build --build-arg BASE_IMAGE=<образ> -t vrunner:<тег> vrunner
# vanessa-runner 3 нужен OneScript 2, vanessa-runner 2 - OneScript 1.9:
#   docker build --build-arg BASE_IMAGE=<образ с OneScript 1.9> --build-arg VRUNNER_VERSION=2.6.1 -t <тег> vrunner
# ENTRYPOINT vrunner, дисплей клиенту 1С поднимается сам.

ARG BASE_IMAGE

FROM ${BASE_IMAGE}
ARG VRUNNER_VERSION=3.0.2
ARG ADD_VERSION=6.8.0
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
# Команда vrunner от opm заменяется своей: вызов через 1c-nest-display
RUN <<'EOF'
export OSCRIPTBIN=/usr/local/libexec/1c-nest
mkdir -p "$OSCRIPTBIN"
opm install "vanessa-runner@$VRUNNER_VERSION"
opm install "add@$ADD_VERSION"
printf '#!/bin/sh\nexec %s %s/lib/vanessa-runner/src/main.os "$@"\n' \
	"$(command -v oscript)" "${ONESCRIPT_HOME:?Нужен образ со слоем onescript}" >"$OSCRIPTBIN/vrunner"
chmod 755 "$OSCRIPTBIN/vrunner"
EOF
COPY --chmod=0755 rootfs/usr/local/bin/ /usr/local/bin/
RUN case $VRUNNER_VERSION in 2.*) vrunner version ;; *) vrunner --version ;; esac
LABEL org.opencontainers.image.title="vanessa-runner ${VRUNNER_VERSION}"
ENTRYPOINT ["/usr/bin/tini", "--", "vrunner"]
