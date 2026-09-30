# 1C:EDT с консолью 1cedtcli, без графики: ENTRYPOINT 1cedtcli.
# Дистрибутив скачивается при сборке, учётная запись releases.1c.ru передаётся секретами из переменных
# ONEC_LOGIN и ONEC_PASSWORD:
#   docker build --secret id=ONEC_LOGIN --secret id=ONEC_PASSWORD --build-arg EDT_VERSION=<версия> \
#     -t edt:<версия> edt
# Каталог с распакованным офлайн-дистрибутивом для Linux (с 1ce-installer-cli) подставляется вместо скачивания:
#   docker build --build-context distr=<каталог> --build-arg EDT_VERSION=<версия> -t edt:<версия> edt

ARG DOWNLOADER_IMAGE=ghcr.io/yellow-hammer/1c-nest/downloader:latest
ARG BASE_IMAGE=ubuntu:22.04

FROM ${DOWNLOADER_IMAGE} AS distr
ARG EDT_VERSION
RUN --mount=type=secret,id=ONEC_LOGIN,env=ONEC_LOGIN,required=true \
    --mount=type=secret,id=ONEC_PASSWORD,env=ONEC_PASSWORD,required=true \
    onec-download edt "${EDT_VERSION:?}" /distr

# Установщикам до 2025.1 нужна Java в системе
FROM eclipse-temurin:17-jdk-jammy AS install
ARG EDT_VERSION
ARG WARMUP=1
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
# libgtk-3-0 нужна и без дисплея: без неё EDT не поднимает контекст проекта и экспорт висит до -timeout
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libgtk-3-0 locales unzip \
 && rm -rf /var/lib/apt/lists/* \
 && localedef -i ru_RU -c -f UTF-8 -A /usr/share/locale/locale.alias ru_RU.UTF-8
ENV LANG=ru_RU.UTF-8 LC_ALL=ru_RU.UTF-8

# Установщик пишет рядом с собой: дистрибутив подключается на запись, изменения отбрасываются
RUN --mount=type=bind,from=distr,target=/mnt/distr,rw <<'EOF'
installer=$(find /mnt/distr -type f -name 1ce-installer-cli | head -1)
if [ -z "$installer" ]; then
	echo 'В дистрибутиве нет 1ce-installer-cli' >&2
	exit 1
fi
cd "$(dirname "$installer")"
chmod -R u+x .
./1ce-installer-cli install all --ignore-hardware-checks --ignore-signature-warnings
EOF

RUN --mount=type=bind,source=1cedtcli.in,target=/mnt/1cedtcli.in <<'EOF'
components=/opt/1C/1CE/components
du -sh "$components"/*

# Каталог EDT - тот, где больше всего модулей: у 1C:EDT Start свой bundles.info на несколько модулей
bundles=$(find "$components" -path "*/1c-edt-${EDT_VERSION:?}*/configuration/org.eclipse.equinox.simpleconfigurator/bundles.info" \
	-printf '%s %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
if [ -z "$bundles" ]; then
	echo "EDT ${EDT_VERSION} не найдена в $components" >&2
	exit 1
fi
edt_home=$(dirname "$(dirname "$(dirname "$bundles")")")
cli=$(find "$edt_home" -maxdepth 2 -type f \( -name 1cedtcli -o -name 1cedtcli.sh \) | head -1)
if [ -z "$cli" ]; then
	echo "В $edt_home нет 1cedtcli" >&2
	exit 1
fi
chmod a+x "$cli"
ln -sfn "$edt_home" /opt/1C/1CE/edt
sed "s|@CLI@|$(realpath --relative-to="$edt_home" "$cli")|" /mnt/1cedtcli.in >/usr/local/bin/1cedtcli
chmod 755 /usr/local/bin/1cedtcli

# Нативные библиотеки платформы бывают упакованы в jar: при запуске OSGi распаковывает их
# в configuration, и копий в образе становится две. Такие модули распаковываются в каталоги заранее
awk -F, '$1 ~ /natives\.library/ && $3 ~ /\.jar$/ { print $3 }' "$bundles" | while IFS= read -r location; do
	path=${location#file:}
	case $path in
	/*) ;;
	*) path="$edt_home/$path" ;;
	esac
	unzip -q "$path" -d "${path%.jar}"
	rm "$path"
	sed -i "s|,$location,|,${location%.jar},|" "$bundles"
done
if awk -F, '$1 ~ /natives\.library/ && $3 ~ /\.jar$/ { found = 1 } END { exit !found }' "$bundles"; then
	echo 'В bundles.info остались нативные модули в jar' >&2
	exit 1
fi

# Java 17: из поставки (EDT 2025.1 и новее ставит свою), иначе Temurin этого этапа
jdk=$(find "$components" -mindepth 3 -maxdepth 4 -type f -path '*/bin/java' | grep -i jdk | head -1 || true)
checker=
if [ -n "$jdk" ]; then
	jdk=$(dirname "$(dirname "$jdk")")
else
	jdk="$components/temurin-jdk-17"
	cp -a /opt/java/openjdk "$jdk"
	# В Temurin нет JavaFX, которого требует проверка окружения EDT
	checker=-DenvironmentChecker.disable=true
fi
if ! "$jdk/bin/java" -version 2>&1 | grep -q 'version "17'; then
	echo "$jdk - не Java 17" >&2
	"$jdk/bin/java" -version
	exit 1
fi

# 1cedt.ini: своя Java (каталог bin, запуск через JNI), куча по памяти контейнера
# (-Xmx из -vmargs 1cedtcli идёт позже и перекрывает её) и домашний каталог:
# у пользователя без записи в /etc/passwd Java считает домом "?" в текущем каталоге
ini="$edt_home/1cedt.ini"
sed -i 's/\r$//' "$ini"
awk -v vm="$jdk/bin" -v checker="$checker" '
	skip { skip = 0; next }
	$0 == "-vm" { skip = 1; next }
	$0 == "-vmargs" && !done {
		print "-vm"; print vm; print; print "-Duser.home=/tmp"
		if (checker != "") print checker
		done = 1; next
	}
	/^-Xmx/ { print "-XX:MaxRAMPercentage=75"; next }
	{ print }
' "$ini" >"$ini.new"
mv "$ini.new" "$ini"
cat "$ini"

# Кэш OSGi собирается при сборке образа, а не в каждом контейнере
if [ "$WARMUP" = 1 ]; then
	if ! timeout 1200 /usr/local/bin/1cedtcli -data /tmp/warmup-ws -timeout 900 -command help >/tmp/warmup.log 2>&1; then
		tail -50 /tmp/warmup.log
		exit 1
	fi
	rm -rf /tmp/warmup-ws /tmp/warmup.log /tmp/1cedt* /root/.eclipse
fi
# Контейнер могут запустить с --user: области конфигурации нужна запись
chmod -R a+rwX "$edt_home/configuration"

du -sh "$components"/* "$edt_home/configuration"
EOF

FROM ${BASE_IMAGE}
ARG EDT_VERSION
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates libgtk-3-0 locales tini \
 && rm -rf /var/lib/apt/lists/* \
 && localedef -i ru_RU -c -f UTF-8 -A /usr/share/locale/locale.alias ru_RU.UTF-8
# Без UTF-8 Java не открывает пути с кириллицей
ENV LANG=ru_RU.UTF-8 \
    LC_ALL=ru_RU.UTF-8 \
    EDT_VERSION=${EDT_VERSION}
COPY --from=install /opt/1C /opt/1C
COPY --from=install /usr/local/bin/1cedtcli /usr/local/bin/1cedtcli
RUN 1cedtcli -version
LABEL org.opencontainers.image.title="1C:EDT ${EDT_VERSION}" \
      org.opencontainers.image.version="${EDT_VERSION}"
WORKDIR /workspace
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/1cedtcli"]
CMD ["-help"]
