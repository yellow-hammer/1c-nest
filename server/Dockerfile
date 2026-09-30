# Сервер 1С:Предприятия для Linux: агент кластера с сервером администрирования, сервер хранилища
# конфигураций, ibcmd, ibsrv и модули веб-сервера. Клиентов и конфигуратора нет.
# Дистрибутив скачивается при сборке, учётная запись releases.1c.ru передаётся секретами из переменных
# ONEC_LOGIN и ONEC_PASSWORD:
#   docker build --secret id=ONEC_LOGIN --secret id=ONEC_PASSWORD --build-arg ONEC_VERSION=<версия> \
#     -t server:<версия> server
# Каталог со скачанным дистрибутивом (setup-full-<версия>-x86_64.run) подставляется вместо скачивания:
#   docker build --build-context distr=<каталог> --build-arg ONEC_VERSION=<версия> -t server:<версия> server
# Команды контейнера описаны в 1c-nest-server.

ARG DOWNLOADER_IMAGE=ghcr.io/yellow-hammer/1c-nest/downloader:latest
ARG BASE_IMAGE=ubuntu:22.04

FROM ${DOWNLOADER_IMAGE} AS distr
ARG ONEC_VERSION
RUN --mount=type=secret,id=ONEC_LOGIN,env=ONEC_LOGIN,required=true \
    --mount=type=secret,id=ONEC_PASSWORD,env=ONEC_PASSWORD,required=true \
    onec-download platform "${ONEC_VERSION:?}" /distr

FROM ${BASE_IMAGE} AS install
ARG ONEC_VERSION
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
RUN --mount=type=bind,from=distr,target=/mnt/distr <<'EOF'
installer=$(find /mnt/distr -type f -name "setup-full-${ONEC_VERSION:?}-x86_64.run" | head -1)
if [ -z "$installer" ]; then
	echo "В дистрибутиве нет setup-full-${ONEC_VERSION}-x86_64.run" >&2
	exit 1
fi
install -m 0755 "$installer" /tmp/setup-full.run
# Клиент установщик ставит и без просьбы
/tmp/setup-full.run --mode unattended --enable-components server,ws,config_storage_server,ru \
	--disable-components client_full
rm -f /tmp/setup-full.run
EOF
RUN <<'EOF'
dir=/opt/1cv8/x86_64/${ONEC_VERSION}
for bin in ragent rmngr rphost ras rac ibcmd ibsrv crserver webinst; do
	[ -x "$dir/$bin" ] || { echo "Установщик не поставил $dir/$bin" >&2; exit 1; }
done
if [ -e "$dir/1cv8" ] || [ -e "$dir/1cv8c" ]; then
	echo 'Установщик поставил клиент' >&2
	exit 1
fi
rm -rf "$dir/ExtDst" "$dir/docs" "$dir"/readme*
# Своя libstdc++ платформы старше системной
rm -f "$dir"/libstdc++.so.6*
ln -sfn "$dir" /opt/1cv8/current
EOF

FROM ${BASE_IMAGE} AS server
ARG ONEC_VERSION
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl locales tzdata procps iproute2 tini \
      fontconfig fonts-dejavu-core libgsf-1-114 libodbc1 \
 && rm -rf /var/lib/apt/lists/* \
 && localedef -i ru_RU -c -f UTF-8 -A /usr/share/locale/locale.alias ru_RU.UTF-8
RUN groupadd -r -g 999 grp1cv8 \
 && useradd -r -u 999 -g grp1cv8 -m -d /home/usr1cv8 -s /bin/bash usr1cv8 \
 && install -d -o usr1cv8 -g grp1cv8 /home/usr1cv8/.1cv8 /var/1C/licenses
COPY --chmod=0755 rootfs/usr/local/bin/ /usr/local/bin/
COPY --from=install /opt/1cv8 /opt/1cv8
# Системных библиотек должно хватать всем программам и модулям сервера
RUN <<'EOF'
cd /opt/1cv8/current
missing=$(find . -maxdepth 1 -type f \( -name '*.so*' -o -perm -u+x \) -print0 |
	LD_LIBRARY_PATH=$PWD xargs -0 -n1 sh -c 'ldd "$0" 2>/dev/null | sed -n "s|.* => not found|$0: &|p"')
if [ -n "$missing" ]; then
	echo "$missing" >&2
	exit 1
fi
./ibcmd --version
EOF
ENV LANG=ru_RU.UTF-8 \
    LC_ALL=ru_RU.UTF-8 \
    PATH=/opt/1cv8/current:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    ONEC_VERSION=${ONEC_VERSION}
LABEL org.opencontainers.image.title="1C:Enterprise server ${ONEC_VERSION}" \
      org.opencontainers.image.version="${ONEC_VERSION}"
EXPOSE 1540 1541 1542 1545 1560-1591
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "1c-nest-server"]
CMD ["ragent"]
