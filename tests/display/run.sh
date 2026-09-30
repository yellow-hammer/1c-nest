#!/bin/bash
# Проверка образов без платформы 1С: OneScript и vanessa-runner, обёртка дисплея, VNC.
# Запуск из корня репозитория: bash tests/display/run.sh
set -u
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/../.." || exit 1

T=1c-nest-test
X=$T/display
V=$T/display-vnc
MARK=$(mktemp -d)
chmod 777 "$MARK"
# Docker Desktop под Git Bash монтирует пути Windows
MARK_MOUNT=$MARK
if command -v cygpath >/dev/null; then
	MARK_MOUNT=$(cygpath -w "$MARK")
fi
pass=0
fail=0

ok() {
	pass=$((pass + 1))
	echo "✓ $1"
}

bad() {
	fail=$((fail + 1))
	echo "✗ $1: $2"
}

check() {
	if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "ожидалось [$3], получено [$2]"; fi
}

ms() {
	date +%s%3N
}

# Те же слои, что у образов vrunner, поверх клиента без платформы
build() {
	docker build -q --target runtime --build-arg ONEC_VERSION=8.3.27.1 -t $T/runtime client &&
		docker build -q --build-arg BASE_IMAGE=$T/runtime -t $T/runtime-vnc vnc &&
		docker build -q --build-arg BASE_IMAGE=$T/runtime -t $T/onescript onescript &&
		docker build -q --build-arg BASE_IMAGE=$T/runtime --build-arg ONESCRIPT_VERSION=1.9.4 -t $T/onescript1 onescript &&
		docker build -q --build-arg BASE_IMAGE=$T/runtime-vnc -t $T/onescript-vnc onescript &&
		docker build -q --build-arg BASE_IMAGE=$T/onescript -t $T/vrunner vrunner &&
		docker build -q --build-arg BASE_IMAGE=$T/onescript1 --build-arg VRUNNER_VERSION=2.6.1 -t $T/vrunner2 vrunner &&
		docker build -q --build-arg BASE_IMAGE=$T/onescript-vnc -t $T/vnc vrunner &&
		docker build -q --build-arg BASE=$T/vrunner -t $X tests/display &&
		docker build -q --build-arg BASE=$T/vnc -t $V tests/display
}
build >/dev/null || {
	echo 'Сборка не удалась'
	exit 1
}

echo '--- OneScript и vanessa-runner'
check vrunner3-version "$(docker run --rm $T/vrunner --version 2>&1 | tail -1)" 3.0.2
check vrunner2-version "$(docker run --rm $T/vrunner2 version 2>&1 | tail -1)" 2.6.1
check vrunner3-russian "$(docker run --rm --entrypoint /bin/sh $T/vrunner -c \
	'printf "А = 1 / 0;\n" >/tmp/e.os; oscript /tmp/e.os 2>&1 | grep -c "Ошибка в строке"')" 1
check user "$(docker run --rm --entrypoint /usr/local/bin/1c-nest-display $T/vrunner id -un)" usr1cv8

echo '--- свой Xvfb'
out=$(docker run --rm $X check)
check private-display "$(echo "$out" | head -1 | cut -c1-9)" 'DISPLAY=:'
check private-xdpyinfo "$(echo "$out" | grep -c 'name of display')" 1
check home "$(echo "$out" | head -1 | sed 's/.*HOME=\([^ ]*\).*/\1/')" /home/usr1cv8
docker run --rm $X check 3 >/dev/null
check exit-code $? 3
check version-bypass "$(docker run --rm --entrypoint sh $X -c 'vrunner --version; pgrep -c Xvfb')" "$(printf '3.0.2\n0')"
check sequence-cleanup "$(docker run --rm --entrypoint /bin/sh $X -c \
	'vrunner check >/dev/null && vrunner check >/dev/null; pgrep -c Xvfb; ls /tmp | grep -c 1c-nest-xvfb')" "$(printf '0\n0')"
docker run --rm --entrypoint /bin/sh $X -c 'vrunner check 5 >/dev/null && vrunner check >/dev/null'
check sequence-stops-on-failure $? 5
check concurrent-displays "$(docker run --rm --entrypoint /bin/sh $X -c \
	'for i in 1 2 3 4 5 6; do vrunner check >/tmp/o$i 2>&1 & done; wait; head -qn1 /tmp/o* | cut -d" " -f1 | sort -u | wc -l')" 6
check stdin "$(echo 'из хоста' | docker run --rm -i $X stdin)" 'stdin: из хоста'
check dbus-off "$(docker run --rm --entrypoint /usr/local/bin/1c-nest-display $X sh -c 'echo $DBUS_SESSION_BUS_ADDRESS')" disabled:

echo '--- владелец рабочего каталога'
check owner-switch "$(docker run --rm --entrypoint /bin/sh $X -c \
	'mkdir /tmp/p && chown 1000:1000 /tmp/p && cd /tmp/p && vrunner check | head -1 | cut -d" " -f2-3')" \
	'HOME=/tmp/1c-nest-home-1000 uid=1000'
check owner-root "$(docker run --rm -w /tmp $X check | head -1 | cut -d' ' -f3)" uid=0
check owner-off "$(docker run --rm -e ONEC_NEST_AS_OWNER=0 --entrypoint /bin/sh $X -c \
	'mkdir /tmp/p && chown 1000:1000 /tmp/p && cd /tmp/p && vrunner check | head -1 | cut -d" " -f3')" uid=0

echo '--- пользователь без записи в passwd'
out=$(docker run --rm --user 1000:1000 $X check)
check user-home "$(echo "$out" | head -1 | sed 's/.*HOME=\([^ ]*\).*/\1/')" /tmp/1c-nest-home-1000
check user-home-write "$(echo "$out" | grep -c 'home writable')" 1
check user-name "$(docker run --rm --user 1234:1234 --entrypoint /usr/local/bin/1c-nest-display $X sh -c 'whoami; echo $HOME')" \
	"$(printf 'onec\n/tmp/1c-nest-home-1234')"

echo '--- --no-wait'
t=$(ms)
out=$(docker run --rm $V gui 5 --no-wait 2>&1 >/dev/null)
d=$(($(ms) - t))
if [ "$d" -lt 4000 ]; then ok "отпущенного клиента не ждёт (${d} мс)"; else bad no-wait "${d} мс"; fi
check no-wait-hint "$(echo "$out" | grep -c 'закроется вместе с контейнером')" 1
t=$(ms)
docker run --rm $V gui 3 >/dev/null 2>&1
d=$(($(ms) - t))
if [ "$d" -ge 3000 ]; then ok "ждёт клиента, запущенного без --no-wait (${d} мс)"; else bad wait "${d} мс"; fi

echo '--- сигналы'
stop_case() {
	local name=$1 how=$2 t code
	shift 2
	docker run -d --name "nest-$name" -v "$MARK_MOUNT:/mark" "$@" >/dev/null
	sleep 3
	t=$(ms)
	case $how in
	TERM) docker stop -t 10 "nest-$name" >/dev/null ;;
	*) docker kill -s "$how" "nest-$name" >/dev/null && docker wait "nest-$name" >/dev/null ;;
	esac
	code=$(docker inspect -f '{{.State.ExitCode}}' "nest-$name")
	docker rm -f "nest-$name" >/dev/null
	echo "$code;$(($(ms) - t));$(tr '\n' '|' 2>/dev/null <"$MARK/$name")"
}
stop_check() {
	local name=$1 want=$2 code dur marks
	shift 2
	IFS=';' read -r code dur marks <<<"$(stop_case "$name" "$@")"
	check "$name (${dur} мс)" "$code $marks" "$want"
}
stop_check term-tini '143 started|TERM received|graceful done|' TERM $X term 60 /mark/term-tini
stop_check orphan-client '143 vrunner started client|client TERM|client graceful done|' TERM $X orphan /mark/orphan-client
stop_check wrapper-pid1 '143 started|TERM received|graceful done|' TERM --entrypoint vrunner $X term 60 /mark/wrapper-pid1
for sig in INT HUP; do
	IFS=';' read -r code dur _ <<<"$(stop_case "sig-$sig" "$sig" $X gui 60)"
	want=$([ $sig = INT ] && echo 130 || echo 129)
	if [ "$code" = "$want" ] && [ "$dur" -lt 5000 ]; then ok "$sig (${dur} мс)"; else bad "$sig" "$code, ${dur} мс"; fi
done

echo '--- VNC'
docker rm -f nest-vnc >/dev/null 2>&1
docker run -d --name nest-vnc -p 127.0.0.1:6080:6080 -p 127.0.0.1:5900:5900 $V gui 120 >/dev/null
for _ in $(seq 1 40); do
	[ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:6080/)" = 200 ] && break
	sleep 0.5
done
check vnc-root "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:6080/)" 200
check vnc-port-substituted "$(curl -s http://localhost:6080/ | grep -c "port: '5900'")" 1
check vnc-html "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:6080/vnc.html)" 200
check vnc-rfb "$(curl -s --max-time 2 telnet://localhost:5900 | head -c 12)" 'RFB 003.008'
check vnc-websocket "$(curl -s -i --max-time 2 -H 'Origin: http://localhost:6080' -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
	-H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' -H 'Sec-WebSocket-Protocol: binary' \
	http://localhost:5900/ | head -1 | tr -d '\r')" 'HTTP/1.1 101 Switching Protocols'
check vnc-no-popup "$(docker exec nest-vnc sh -c 'pgrep -c xmessage')" 0
docker rm -f nest-vnc >/dev/null
check vnc-sequence-reuse "$(docker run --rm --entrypoint /bin/sh $V -c \
	'vrunner check >/dev/null 2>&1 && vrunner check >/dev/null 2>&1; echo $(pgrep -c Xvfb) $(pgrep -c x11vnc)')" '1 1'
check vnc-concurrent "$(docker run --rm --entrypoint /bin/sh $V -c \
	'for i in 1 2 3 4; do vrunner check >/tmp/o$i 2>&1 & done; wait; echo $(pgrep -c Xvfb) $(pgrep -c x11vnc)')" '1 1'
check vnc-user "$(docker run --rm --user 1000:1000 $V check 2>/dev/null | head -1 | cut -d' ' -f1)" DISPLAY=:0

rm -rf "$MARK"
echo "Итого: пройдено $pass, не пройдено $fail"
[ "$fail" -eq 0 ]
