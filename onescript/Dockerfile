# OneScript слоем поверх образа на Ubuntu или Debian, по умолчанию поверх Ubuntu 22.04:
#   docker build -t onescript:2.1.0 onescript
#   docker build --build-arg BASE_IMAGE=<образ> --build-arg ONESCRIPT_VERSION=1.9.4 -t <тег> onescript
# OneScript 2 ставится самодостаточной сборкой, 1.9 - пакетом с mono. В обоих случаях каталог
# OneScript - /opt/onescript, opm ставит библиотеки в /opt/onescript/lib, а команды в /opt/onescript/bin.
# Для версий, которых нет в списке ниже, нужна контрольная сумма: --build-arg ONESCRIPT_SHA256=<sha256>.

ARG BASE_IMAGE=ubuntu:22.04

FROM ${BASE_IMAGE}
ARG ONESCRIPT_VERSION=2.1.0
ARG ONESCRIPT_SHA256=
# opm из пакета OneScript 1.9 не разбирает packagedef новых библиотек
ARG OPM_VERSION=1.7.1
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
# Сообщения OneScript на русском, а без UTF-8 unzip портит кириллические имена каталогов библиотек.
# Язык базового образа сохраняется
ENV LANG=${LANG:-ru_RU.UTF-8} \
    ONESCRIPT_HOME=/opt/onescript \
    OSCRIPTBIN=/opt/onescript/bin \
    PATH=/opt/onescript/bin:${PATH}
RUN <<'EOF'
declare -A known=(
	[2.1.0]=548dfaff7a389e7c64b7e60ca26c7e4b086de83fe3b67f4b9059bb036f8508fc
	[1.9.4]=1ad0974cd63a3868c9c730716e1364ad75de751105bf67fe218fb2a9d5697a8c
)
sha=${ONESCRIPT_SHA256:-${known[$ONESCRIPT_VERSION]:-}}
if [ -z "$sha" ]; then
	echo "Для OneScript $ONESCRIPT_VERSION нужна контрольная сумма: --build-arg ONESCRIPT_SHA256=<sha256>" >&2
	exit 1
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl
if [ "$LANG" = ru_RU.UTF-8 ] && ! locale -a | grep -qx 'ru_RU.utf8'; then
	apt-get install -y --no-install-recommends locales
	localedef -i ru_RU -c -f UTF-8 -A /usr/share/locale/locale.alias ru_RU.UTF-8
fi
case $ONESCRIPT_VERSION in
1.*)
	curl -fsSL -o /tmp/onescript.deb \
		"https://github.com/EvilBeaver/OneScript/releases/download/v${ONESCRIPT_VERSION}/onescript-engine_${ONESCRIPT_VERSION}_all.deb"
	echo "$sha  /tmp/onescript.deb" | sha256sum -c -
	# У mono своё хранилище сертификатов: без ca-certificates-mono opm не открывает https
	apt-get install -y --no-install-recommends ca-certificates-mono /tmp/onescript.deb
	rm /tmp/onescript.deb
	ln -s /usr/share/oscript "$ONESCRIPT_HOME"
	opm install "opm@$OPM_VERSION"
	;;
*)
	# Самодостаточной сборке .NET нужна ICU из системы
	icu=$(apt-cache pkgnames libicu | grep -E '^libicu[0-9]+$' | sort -V | tail -1)
	apt-get install -y --no-install-recommends unzip "${icu:?В системе нет пакета libicu}"
	curl -fsSL -o /tmp/onescript.zip \
		"https://oscript.io/downloads/${ONESCRIPT_VERSION//./_}/OneScript-${ONESCRIPT_VERSION}-linux-x64.zip"
	echo "$sha  /tmp/onescript.zip" | sha256sum -c -
	mkdir -p "$ONESCRIPT_HOME"
	unzip -q /tmp/onescript.zip -d "$ONESCRIPT_HOME"
	rm /tmp/onescript.zip
	chmod +x "$ONESCRIPT_HOME/bin/oscript" "$ONESCRIPT_HOME/bin/opm" "$ONESCRIPT_HOME/bin/createdump"
	;;
esac
rm -rf /var/lib/apt/lists/*
oscript -version
EOF
LABEL org.opencontainers.image.title="OneScript ${ONESCRIPT_VERSION}"
