#!/bin/bash
# Публикация образов в ghcr.io.
#   publish.sh <файл со списком образов от build.sh> <версия> [линейка]
# С линейкой каждый образ получает и её тег: vrunner:8.3.27.2342-vnc -> vrunner:8.3.27-vnc.
# Перед отправкой каждый пакет проверяется: без входа он должен быть недоступен,
# иначе образы с платформой 1С стали бы публичными.
set -euo pipefail
shopt -s inherit_errexit

list=${1:?файл со списком образов}
version=${2:?версия}
line=${3:-}
mapfile -t images <"$list"

private_or_die() {
	local repo=$1 path=${1#ghcr.io/} code
	printf 'FROM scratch\nLABEL org.opencontainers.image.source=%s\nCOPY <<EOF /visibility-check\nno 1C content\nEOF\n' \
		"${IMAGE_SOURCE:?}" | docker build -q -t "$repo:visibility-check" - >/dev/null
	docker push -q "$repo:visibility-check" >/dev/null
	for try in 1 2 3; do
		code=$(curl -s -o /dev/null -w '%{http_code}' "https://ghcr.io/token?scope=repository:$path:pull&service=ghcr.io" || true)
		case $code in
		401 | 403)
			echo "$path: без входа недоступен"
			return 0
			;;
		200)
			echo "::error::Пакет $path доступен без входа, публикация остановлена"
			exit 1
			;;
		esac
		sleep $((try * 10))
	done
	echo "::error::Доступность пакета $path без входа не проверилась (ответ $code), публикация остановлена"
	exit 1
}

for repo in $(printf '%s\n' "${images[@]}" | sed 's/:[^:/]*$//' | sort -u); do
	private_or_die "$repo"
done

for image in "${images[@]}"; do
	docker push -q "$image"
	if [ -n "$line" ]; then
		tag=${image##*:}
		alias="${image%:*}:$line${tag#"$version"}"
		docker tag "$image" "$alias"
		docker push -q "$alias"
	fi
done
