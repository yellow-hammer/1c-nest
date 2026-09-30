#!/bin/bash
# Проверка собранных образов перед публикацией. Лицензия 1С не нужна.
#   smoke.sh <файл со списком образов от build.sh>
# Загрузчик ищет сборки на releases.1c.ru, если заданы ONEC_LOGIN и ONEC_PASSWORD.
# shellcheck disable=SC2016 # команды для контейнера раскрываются в нём
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
list=${1:?файл со списком образов}
failed=0
runs=0

pass() {
	echo "✓ $1"
}

fail() {
	echo "✗ $1"
	[ -n "${2:-}" ] && printf '%s\n' "$2" | tail -40 | sed 's/^/    /'
	failed=1
}

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

# Служба в контейнере: $1 - название, $2 - ожидаемый фрагмент вывода, $3 - команда проверки,
# которая повторяется в контейнере до успеха; дальше docker run -d
serves() {
	local name=$1 pattern=$2 probe=$3 out container
	shift 3
	runs=$((runs + 1))
	container="1c-nest-smoke-$$-$runs"
	if ! docker run -d --name "$container" "$@" >/dev/null; then
		fail "$name"
		return
	fi
	out=$(timeout 300 docker exec "$container" sh -c "for i in \$(seq 1 60); do $probe && exit 0; sleep 2; done; exit 1" 2>&1)
	if grep -qiE "$pattern" <<<"$out"; then
		pass "$name"
	else
		fail "$name" "$out
--- docker logs
$(docker logs "$container" 2>&1)"
	fi
	docker rm -f "$container" >/dev/null 2>&1
}

onescript() {
	local image=$1 version=${1##*:}
	expect "$image: версия" "^${version//./\\.}" "$image" oscript -version
	expect "$image: кириллица" '^1$' "$image" sh -c \
		'printf "А = 1 / 0;\n" >/tmp/e.os; oscript /tmp/e.os 2>&1 | grep -c "Ошибка в строке"'
	expect "$image: opm" '^[0-9]+\.[0-9]+\.[0-9]+$' "$image" opm --version
}

downloader() {
	local image=$1
	expect "$image: справка" 'onec-download latest' "$image" help
	if [ -n "${ONEC_LOGIN:-}" ] && [ -n "${ONEC_PASSWORD:-}" ]; then
		expect "$image: последняя сборка 8.3.27" '^8\.3\.27\.[0-9]+$' -e ONEC_LOGIN -e ONEC_PASSWORD \
			"$image" latest platform 8.3.27
	fi
}

server() {
	local image=$1 version=$2
	expect "$image: ibcmd --version" "${version//./\\.}" "$image" ibcmd --version
	serves "$image: ragent и ras" '^cluster +:' 'rac cluster list localhost:1545' "$image"
	serves "$image: crserver" ':1542 ' 'ss -ltn | grep ":1542 "' "$image" crserver
	expect "$image: ibsrv отвечает по HTTP" '^[1-5][0-9][0-9]$' "$image" bash -c '
		ibcmd infobase create --db-path=/tmp/ib >/dev/null || exit 1
		ibsrv --db-path=/tmp/ib --data=/tmp/data --port=8314 >/tmp/ibsrv.log 2>&1 &
		for i in $(seq 1 60); do
			code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8314/) && [ "$code" != 000 ] && { echo "$code"; exit 0; }
			sleep 1
		done
		cat /tmp/ibsrv.log; exit 1'
}

client() {
	local image=$1 version=$2
	expect "$image: ibcmd --version" "${version//./\\.}" "$image" ibcmd --version
	expect "$image: ibcmd: файловая база" 'ok$' "$image" bash -c \
		'ibcmd infobase create --db-path=/tmp/ib >/dev/null && test -f /tmp/ib/1Cv8.1CD && echo ok'
	# Без лицензии конфигуратор доходит до её проверки: значит, клиентские библиотеки на месте
	expect "$image: конфигуратор под Xvfb" 'лиценз|licen' -w /tmp "$image" bash -c '
		ibcmd infobase create --db-path=/tmp/ib >/dev/null || exit 1
		timeout 300 1c-nest-display 1cv8 DESIGNER /F/tmp/ib /DisableStartupDialogs /DisableStartupMessages /Out /tmp/out.log
		echo "код: $?"; cat /tmp/out.log'
}

novnc() {
	local image=$1
	expect "$image: noVNC" '^200$' --entrypoint /usr/local/bin/1c-nest-display "$image" bash -c '
		for i in $(seq 1 50); do
			code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:6080/) && [ "$code" = 200 ] && { echo 200; exit 0; }
			sleep 0.2
		done
		exit 1'
}

client_vnc() {
	local image=$1
	novnc "$image"
	# Запуск конфигуратора с окном заканчивается, когда он закрылся
	expect "$image: запуск конфигуратора завершается вместе с ним" 'запуск завершился' -w /tmp "$image" bash -c '
		ibcmd infobase create --db-path=/tmp/ib >/dev/null || exit 1
		timeout 180 1c-nest-display 1cv8 DESIGNER /F/tmp/ib /DisableStartupDialogs /DisableStartupMessages /Out /tmp/out.log
		rc=$?
		echo "код $rc"
		[ "$rc" != 124 ] && echo "запуск завершился"'
}

vrunner() {
	local image=$1 tag=${1##*:}
	case $tag in
	*-vrunner2*)
		expect "$image: версия" '^2\.' "$image" version
		expect "$image: база конфигуратором" 'ok$' --entrypoint /bin/sh "$image" -c \
			'vrunner init-dev --ibconnection /F/tmp/ib && test -f /tmp/ib/1Cv8.1CD && echo ok'
		expect "$image: база через ibcmd" 'ok$' --entrypoint /bin/sh "$image" -c \
			'vrunner init-dev --ibcmd --ibconnection /F/tmp/ib && test -f /tmp/ib/1Cv8.1CD && echo ok'
		;;
	*)
		expect "$image: версия" '^3\.' "$image" --version
		expect "$image: база конфигуратором" 'ok$' --entrypoint /bin/sh "$image" -c \
			'vrunner infobase init --ibconnection /F/tmp/ib && test -f /tmp/ib/1Cv8.1CD && echo ok'
		expect "$image: база через ibcmd" 'ok$' --entrypoint /bin/sh "$image" -c \
			'vrunner infobase init --ibcmd --ibconnection /F/tmp/ib && test -f /tmp/ib/1Cv8.1CD && echo ok'
		;;
	esac
	case $tag in
	*-vnc)
		novnc "$image"
		case $tag in
		*-vrunner2*) ;;
		*)
			expect "$image: запуск конфигуратора завершается вместе с ним" 'запуск завершился' \
				--entrypoint /bin/bash "$image" -c '
				vrunner infobase init --ibcmd --ibconnection /F/tmp/ib >/dev/null || exit 1
				timeout 180 vrunner run designer --ibconnection /F/tmp/ib
				rc=$?
				echo "код $rc"
				[ "$rc" != 124 ] && echo "запуск завершился"'
			;;
		esac
		;;
	esac
}

edt() {
	local image=$1 version=$2
	# До 2025.1 вместо номера версии печатается заготовка, строка Build есть всегда
	expect "$image: 1cedtcli -version" "^${version//./\\.}|^Build: " "$image" -version
	expect "$image: версии платформы" '8\.3\.27' "$image" -data /tmp/ws -timeout 600 -command platform-versions
	expect "$image: импорт и экспорт" 'ok$' -v "$root/tests/fixtures/empty-cf:/src:ro" --entrypoint /bin/sh "$image" -c '
		1cedtcli -data /tmp/ws -timeout 900 -command import --configuration-files /src --project /tmp/p/Пустая || exit 1
		1cedtcli -data /tmp/ws -timeout 900 -command export --project /tmp/p/Пустая --configuration-files /tmp/xml || exit 1
		test -f /tmp/xml/Configuration.xml && echo ok'
}

mapfile -t images <"$list"
for image in "${images[@]}"; do
	[ -n "$image" ] || continue
	repo=${image%:*}
	tag=${image##*:}
	case ${repo##*/} in
	onescript) onescript "$image" ;;
	downloader) downloader "$image" ;;
	server) server "$image" "${tag%%-*}" ;;
	client) client "$image" "${tag%%-*}" ;;
	client-vnc) client_vnc "$image" ;;
	vrunner) vrunner "$image" ;;
	edt) edt "$image" "$tag" ;;
	*) fail "$image: нет проверок" ;;
	esac
done
exit "$failed"
