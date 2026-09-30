#!/bin/bash
# Проверка собранных образов перед публикацией. Лицензия 1С не нужна.
#   smoke.sh platform <версия>   платформа и vrunner во всех вариантах
#   smoke.sh edt <версия>        1C:EDT
# Имена образов: $IMAGE_PREFIX/<образ>:<тег>, по умолчанию 1c-nest/...
# shellcheck disable=SC2016 # команды для контейнера раскрываются в нём
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
prefix=${IMAGE_PREFIX:-1c-nest}
failed=0

pass() {
	echo "✓ $1"
}

fail() {
	echo "✗ $1"
	[ -n "${2:-}" ] && printf '%s\n' "$2" | tail -40 | sed 's/^/    /'
	failed=1
}

runs=0

# $1 - название, $2 - ожидаемый фрагмент вывода (регулярное выражение), дальше docker run
expect() {
	local name=$1 pattern=$2 out container
	shift 2
	runs=$((runs + 1))
	container="1c-nest-smoke-$$-$runs"
	out=$(timeout 600 docker run --rm --name "$container" "$@" 2>&1)
	docker rm -f "$container" >/dev/null 2>&1
	if grep -qiE "$pattern" <<<"$out"; then
		pass "$name"
	else
		fail "$name" "$out"
	fi
}

platform() {
	local version=$1
	local p="$prefix/platform:$version" v="$prefix/vrunner:$version"

	expect 'ibcmd --version' "${version//./\\.}" "$p" ibcmd --version
	expect 'ibcmd: файловая база' 'ok$' "$p" bash -c \
		'ibcmd infobase create --db-path=/tmp/ib >/dev/null && test -f /tmp/ib/1Cv8.1CD && echo ok'
	expect 'ibsrv отвечает по HTTP' '^[1-5][0-9][0-9]$' "$p" bash -c '
		ibcmd infobase create --db-path=/tmp/ib >/dev/null || exit 1
		ibsrv --db-path=/tmp/ib --data=/tmp/data --port=8314 >/tmp/ibsrv.log 2>&1 &
		for i in $(seq 1 60); do
			code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8314/) && [ "$code" != 000 ] && { echo "$code"; exit 0; }
			sleep 1
		done
		cat /tmp/ibsrv.log; exit 1'
	# Без лицензии конфигуратор доходит до её проверки: значит, клиентские библиотеки на месте
	expect 'конфигуратор под Xvfb' 'лиценз|licen' -w /tmp "$p" bash -c '
		ibcmd infobase create --db-path=/tmp/ib >/dev/null || exit 1
		timeout 300 1c-nest-display 1cv8 DESIGNER /F/tmp/ib /DisableStartupDialogs /DisableStartupMessages /Out /tmp/out.log
		echo "код: $?"; cat /tmp/out.log'

	expect 'vrunner 3: версия' '^3\.' "$v" --version
	expect 'vrunner 3: база конфигуратором' 'ok$' --entrypoint /bin/sh "$v" -c \
		'vrunner infobase init --ibconnection /F/tmp/ib && test -f /tmp/ib/1Cv8.1CD && echo ok'
	expect 'vrunner 3: база через ibcmd' 'ok$' --entrypoint /bin/sh "$v" -c \
		'vrunner infobase init --ibcmd --ibconnection /F/tmp/ib && test -f /tmp/ib/1Cv8.1CD && echo ok'
	expect 'vrunner 2: версия' '^2\.' "$v-vrunner2" version
	expect 'vrunner 2: база конфигуратором' 'ok$' --entrypoint /bin/sh "$v-vrunner2" -c \
		'vrunner init-dev --ibconnection /F/tmp/ib && test -f /tmp/ib/1Cv8.1CD && echo ok'
	expect 'vrunner 2: база через ibcmd' 'ok$' --entrypoint /bin/sh "$v-vrunner2" -c \
		'vrunner init-dev --ibcmd --ibconnection /F/tmp/ib && test -f /tmp/ib/1Cv8.1CD && echo ok'

	# Запуск конфигуратора с окном заканчивается, когда он закрылся
	expect 'VNC: запуск конфигуратора завершается вместе с ним' 'запуск завершился' --entrypoint /bin/bash "$v-vnc" -c '
		vrunner infobase init --ibcmd --ibconnection /F/tmp/ib >/dev/null || exit 1
		timeout 180 vrunner run designer --ibconnection /F/tmp/ib
		rc=$?
		echo "код $rc"
		[ "$rc" != 124 ] && echo "запуск завершился"'

	local vnc
	for vnc in "$v-vnc" "$v-vrunner2-vnc"; do
		expect "noVNC: ${vnc##*:}" '^200$' --entrypoint /usr/local/bin/1c-nest-display "$vnc" bash -c '
			for i in $(seq 1 50); do
				code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:6080/) && [ "$code" = 200 ] && { echo 200; exit 0; }
				sleep 0.2
			done
			exit 1'
	done
}

edt() {
	local version=$1
	local e="$prefix/edt:$version"
	# До 2025.1 вместо номера версии печатается заготовка, строка Build есть всегда
	expect '1cedtcli -version' "^${version//./\\.}|^Build: " "$e" -version
	expect '1cedtcli: версии платформы' '8\.3\.27' "$e" -data /tmp/ws -timeout 600 -command platform-versions
	expect '1cedtcli: импорт и экспорт' 'ok$' -v "$root/tests/fixtures/empty-cf:/src:ro" --entrypoint /bin/sh "$e" -c '
		1cedtcli -data /tmp/ws -timeout 900 -command import --configuration-files /src --project /tmp/p/Пустая || exit 1
		1cedtcli -data /tmp/ws -timeout 900 -command export --project /tmp/p/Пустая --configuration-files /tmp/xml || exit 1
		test -f /tmp/xml/Configuration.xml && echo ok'
}

case ${1:-} in
platform) platform "${2:?версия}" ;;
edt) edt "${2:?версия}" ;;
*)
	echo 'Использование: smoke.sh platform|edt <версия>' >&2
	exit 1
	;;
esac
exit "$failed"
