#!/bin/bash
# Системные пакеты платформы на Ubuntu 22.04.
#   deps.sh install <версия>  - для установщика
#   deps.sh runtime <версия>  - для работы сервера, клиентов и конфигуратора
set -eo pipefail

stage=${1:?install или runtime}
version=${2:?версия платформы}
export DEBIAN_FRONTEND=noninteractive

# До 8.3.24 платформа несёт свой WebKit1, и установщик проверяет его зависимости
webkit1=0
if dpkg --compare-versions "$version" lt 8.3.24; then
	webkit1=1
fi

packages=(ca-certificates curl)
if [ "$stage" = runtime ]; then
	packages+=(
		locales tzdata procps iproute2
		fontconfig fonts-dejavu-core
		libwebkit2gtk-4.0-37 libglu1-mesa libsm6 libxxf86vm1 libcups2 libgsf-1-114 libodbc1
		xvfb xauth dbus-x11 tini libnss-wrapper
	)
fi
if [ "$webkit1" = 1 ]; then
	packages+=(
		libgtk-3-0 libharfbuzz-icu0 libgstreamer1.0-0 libgstreamer-plugins-base1.0-0
		gstreamer1.0-plugins-good gstreamer1.0-plugins-bad libsecret-1-0 libsoup2.4-1
		libsqlite3-0 libegl1 libxrender1 libxfixes3 libxslt1.1 geoclue-2.0
	)
fi

apt-get update
apt-get install -y --no-install-recommends "${packages[@]}"

if [ "$webkit1" = 1 ]; then
	# В 22.04 пакета нет, берётся из 20.04
	curl -fsSL -o /tmp/libenchant1c2a.deb \
		http://archive.ubuntu.com/ubuntu/pool/universe/e/enchant/libenchant1c2a_1.6.0-11.3build1_amd64.deb
	echo '61fcfff6f79c871350b1c2f674bdf6f1cc19e9e808687f7abb005cdfc19264a6  /tmp/libenchant1c2a.deb' | sha256sum -c -
	apt-get install -y --no-install-recommends /tmp/libenchant1c2a.deb
	rm -f /tmp/libenchant1c2a.deb
fi

if [ "$stage" = runtime ]; then
	localedef -i ru_RU -c -f UTF-8 -A /usr/share/locale/locale.alias ru_RU.UTF-8
	install -d -m 1777 /tmp/.X11-unix
fi

rm -rf /var/lib/apt/lists/*
