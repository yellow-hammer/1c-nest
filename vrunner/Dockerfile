# check=skip=InvalidDefaultArgInFrom
# vanessa-runner поверх образа платформы: ENTRYPOINT vrunner, дисплей клиенту 1С поднимается сам.
#   docker build --build-arg BASE_IMAGE=<образ платформы> --target <цель> -t <тег> vrunner
# Цели:
#   vrunner   - vanessa-runner 3 на OneScript 2
#   vrunner2  - vanessa-runner 2 на OneScript 1.9
#   vnc       - окна клиента в браузере; поверх цели из FLAVOR (vrunner или vrunner2)

ARG BASE_IMAGE
ARG FLAVOR=vrunner

FROM ubuntu:22.04 AS onescript
ARG ONESCRIPT_VERSION=2.1.0
ARG ONESCRIPT_SHA256=548dfaff7a389e7c64b7e60ca26c7e4b086de83fe3b67f4b9059bb036f8508fc
ARG VRUNNER_VERSION=3.0.2
ARG ADD_VERSION=6.8.0
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
# Без UTF-8 unzip портит кириллические имена каталогов библиотек
ENV LANG=C.UTF-8 \
    OSCRIPTBIN=/usr/local/libexec/1c-nest \
    PATH=/opt/onescript/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl unzip libicu70 \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /tmp/onescript.zip \
      "https://oscript.io/downloads/${ONESCRIPT_VERSION//./_}/OneScript-${ONESCRIPT_VERSION}-linux-x64.zip" \
 && echo "${ONESCRIPT_SHA256}  /tmp/onescript.zip" | sha256sum -c - \
 && mkdir -p /opt/onescript "$OSCRIPTBIN" \
 && unzip -q /tmp/onescript.zip -d /opt/onescript \
 && rm /tmp/onescript.zip \
 && chmod +x /opt/onescript/bin/oscript /opt/onescript/bin/opm /opt/onescript/bin/createdump \
 && oscript -version
RUN opm install vanessa-runner@${VRUNNER_VERSION} \
 && opm install add@${ADD_VERSION} \
 && printf '#!/bin/sh\nexec /opt/onescript/bin/oscript /opt/onescript/lib/vanessa-runner/src/main.os "$@"\n' \
      >"$OSCRIPTBIN/vrunner" \
 && chmod 755 "$OSCRIPTBIN/vrunner" \
 && "$OSCRIPTBIN/vrunner" --version

FROM ${BASE_IMAGE} AS vrunner
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libicu70 \
 && rm -rf /var/lib/apt/lists/*
COPY --from=onescript /opt/onescript /opt/onescript
COPY --from=onescript /usr/local/libexec/1c-nest /usr/local/libexec/1c-nest
COPY --chmod=0755 rootfs/usr/local/bin/ /usr/local/bin/
ENV PATH=/opt/onescript/bin:${PATH}
RUN vrunner --version
ENTRYPOINT ["/usr/bin/tini", "--", "vrunner"]

FROM ${BASE_IMAGE} AS vrunner2
ARG ONESCRIPT_VERSION=1.9.4
ARG ONESCRIPT_SHA256=1ad0974cd63a3868c9c730716e1364ad75de751105bf67fe218fb2a9d5697a8c
ARG OPM_VERSION=1.7.1
ARG VRUNNER_VERSION=2.6.1
ARG ADD_VERSION=6.8.0
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
# У mono своё хранилище сертификатов: без ca-certificates-mono opm не открывает https
RUN curl -fsSL -o /tmp/onescript.deb \
      "https://github.com/EvilBeaver/OneScript/releases/download/v${ONESCRIPT_VERSION}/onescript-engine_${ONESCRIPT_VERSION}_all.deb" \
 && echo "${ONESCRIPT_SHA256}  /tmp/onescript.deb" | sha256sum -c - \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates-mono /tmp/onescript.deb \
 && rm -rf /var/lib/apt/lists/* /tmp/onescript.deb \
 && oscript -version
# opm из пакета OneScript не разбирает packagedef vanessa-runner: сначала новый opm
RUN opm install opm@${OPM_VERSION} \
 && mkdir -p /usr/local/libexec/1c-nest \
 && OSCRIPTBIN=/usr/local/libexec/1c-nest opm install vanessa-runner@${VRUNNER_VERSION} \
 && OSCRIPTBIN=/usr/local/libexec/1c-nest opm install add@${ADD_VERSION} \
 && printf '#!/bin/sh\nexec oscript /usr/share/oscript/lib/vanessa-runner/src/main.os "$@"\n' \
      >/usr/local/libexec/1c-nest/vrunner \
 && chmod 755 /usr/local/libexec/1c-nest/vrunner
COPY --chmod=0755 rootfs/usr/local/bin/ /usr/local/bin/
RUN vrunner version
ENTRYPOINT ["/usr/bin/tini", "--", "vrunner"]

FROM ${FLAVOR} AS vnc
# Из пакета novnc берётся только статика: страницы отдаёт x11vnc
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends x11vnc fluxbox hsetroot \
 && cd /tmp \
 && apt-get download novnc \
 && dpkg-deb -x novnc_*.deb /tmp/novnc \
 && mv /tmp/novnc/usr/share/novnc /usr/share/novnc \
 && rm -rf /tmp/novnc /tmp/novnc_*.deb /var/lib/apt/lists/*
COPY --chmod=0644 novnc/index.vnc /usr/share/novnc/index.vnc
ENV ONEC_NEST_VNC=1
EXPOSE 5900 6080
