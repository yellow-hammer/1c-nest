# Клиент 1С:Предприятия для Linux: конфигуратор, толстый и тонкий клиенты, ibcmd, ibsrv и сервер.
# Дистрибутив скачивается при сборке, учётная запись releases.1c.ru передаётся секретами из переменных
# ONEC_LOGIN и ONEC_PASSWORD:
#   docker build --secret id=ONEC_LOGIN --secret id=ONEC_PASSWORD --build-arg ONEC_VERSION=<версия> \
#     -t client:<версия> client
# Каталог со скачанным дистрибутивом (setup-full-<версия>-x86_64.run) подставляется вместо скачивания:
#   docker build --build-context distr=<каталог> --build-arg ONEC_VERSION=<версия> -t client:<версия> client
# Цель runtime собирается без платформы: окружение, пользователь и дисплей.
# Контейнер стартует от root; 1c-nest-display запускает команду под владельцем рабочего каталога.

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
RUN --mount=type=bind,source=deps.sh,target=/tmp/deps.sh \
    bash /tmp/deps.sh install "${ONEC_VERSION:?}"
RUN --mount=type=bind,from=distr,target=/mnt/distr <<'EOF'
installer=$(find /mnt/distr -type f -name "setup-full-${ONEC_VERSION}-x86_64.run" | head -1)
if [ -z "$installer" ]; then
	echo "В дистрибутиве нет setup-full-${ONEC_VERSION}-x86_64.run" >&2
	exit 1
fi
install -m 0755 "$installer" /tmp/setup-full.run
/tmp/setup-full.run --mode unattended --enable-components server,client_full,ru
rm -f /tmp/setup-full.run
EOF
RUN <<'EOF'
dir=/opt/1cv8/x86_64/${ONEC_VERSION}
for bin in ibcmd ibsrv 1cv8 1cv8c; do
	[ -x "$dir/$bin" ] || { echo "Установщик не поставил $dir/$bin" >&2; ls -la "$dir" >&2; exit 1; }
done
# Установщики агента клиентского приложения для других систем и документация
rm -rf "$dir/ExtDst" "$dir/docs" "$dir"/readme*
# Своя libstdc++ платформы старше системной, которую требует WebKitGTK
rm -f "$dir"/libstdc++.so.6*
# Сборок wxWidgets может быть две, под WebKitGTK 4.0 и 4.1: в образе стоит 4.0
if [ -e "$dir/libwx_gtk3u-3.0.so.0.1.0.wk41" ]; then
	ln -sfn libwx_gtk3u-3.0.so.0.1.0 "$dir/libwx_gtk3u-3.0.so.0"
	rm -f "$dir/libwx_gtk3u-3.0.so.0.1.0.wk41"
fi
if [ -e "$dir/webkit2_extu-3.0.so.wk41" ]; then
	[ -L "$dir/webkit2ext/webkit2_extu-3.0.so" ] && ln -sfn ../webkit2_extu-3.0.so "$dir/webkit2ext/webkit2_extu-3.0.so"
	rm -f "$dir/webkit2_extu-3.0.so.wk41"
fi
mkdir -p /opt/1cv8/conf
printf '\nDisableUnsafeActionProtection=.*\n' >>/opt/1cv8/conf/conf.cfg
ln -sfn "$dir" /opt/1cv8/current
EOF

FROM ${BASE_IMAGE} AS runtime
ARG ONEC_VERSION
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
RUN --mount=type=bind,source=deps.sh,target=/tmp/deps.sh \
    bash /tmp/deps.sh runtime "${ONEC_VERSION:?}"
RUN groupadd -r -g 999 grp1cv8 \
 && useradd -r -u 999 -g grp1cv8 -m -d /home/usr1cv8 -s /bin/bash usr1cv8 \
 && install -d -o usr1cv8 -g grp1cv8 /var/1C/licenses /workspace
COPY --chmod=0755 rootfs/usr/local/bin/ /usr/local/bin/
ENV LANG=ru_RU.UTF-8 \
    LC_ALL=ru_RU.UTF-8 \
    NO_AT_BRIDGE=1 \
    PATH=/opt/1cv8/current:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
WORKDIR /workspace
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["bash"]

FROM runtime AS client
ARG ONEC_VERSION
COPY --from=install /opt/1cv8 /opt/1cv8
# Системных библиотек должно хватать всем программам и модулям платформы
RUN <<'EOF'
cd /opt/1cv8/current
missing=$(find . -maxdepth 1 -type f \( -name '*.so*' -o -perm -u+x \) -print0 |
	LD_LIBRARY_PATH=$PWD xargs -0 -n1 sh -c 'ldd "$0" 2>/dev/null | sed -n "s|.* => not found|$0: &|p"')
if [ -n "$missing" ]; then
	echo "$missing" >&2
	exit 1
fi
ibcmd --version
EOF
ENV ONEC_VERSION=${ONEC_VERSION}
LABEL org.opencontainers.image.title="1C:Enterprise ${ONEC_VERSION}" \
      org.opencontainers.image.version="${ONEC_VERSION}"
