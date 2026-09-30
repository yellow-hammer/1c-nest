# check=skip=InvalidDefaultArgInFrom
# Окна клиента 1С в браузере: слой поверх образа client или собранного на нём.
#   docker build --build-arg BASE_IMAGE=<образ> -t client-vnc:<версия> vnc
# Команды через 1c-nest-display идут на общий дисплей контейнера, его видно в noVNC на порту 6080
# и в VNC на порту 5900.

ARG BASE_IMAGE

FROM ${BASE_IMAGE}
# Из пакета novnc берётся только статика: страницы отдаёт x11vnc
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends x11vnc fluxbox hsetroot \
 && cd /tmp \
 && apt-get download novnc \
 && dpkg-deb -x novnc_*.deb /tmp/novnc \
 && mv /tmp/novnc/usr/share/novnc /usr/share/novnc \
 && rm -rf /tmp/novnc /tmp/novnc_*.deb /var/lib/apt/lists/*
COPY --chmod=0644 index.vnc /usr/share/novnc/index.vnc
ENV ONEC_NEST_VNC=1
EXPOSE 5900 6080
