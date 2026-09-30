#!/bin/bash
# Публикация образов в ghcr.io.
#   publish.sh <файл со списком образов от build.sh> [<версия> <линейка>]
# С линейкой каждый образ получает и её тег: vrunner:8.3.27.2342-vnc -> vrunner:8.3.27-vnc.
# Пакеты onescript и downloader открытые: в их образах не должно быть файлов 1С.
# Остальные пакеты перед отправкой проверяются: без входа они должны быть недоступны,
# иначе образы с платформой 1С стали бы публичными.
set -euo pipefail
shopt -s inherit_errexit

list=${1:?файл со списком образов}
version=${2:-}
line=${3:-}
public=' onescript downloader '
mapfile -t images <"$list"

is_public() {
	[[ $public == *" ${1##*/} "* ]]
}

# Код ответа ghcr.io на анонимный запрос к пакету: 200 - открыт, 401 и 403 - закрыт
anonymous() {
	curl -s -o /dev/null -w '%{http_code}' "https://ghcr.io/token?scope=repository:${1#ghcr.io/}:pull&service=ghcr.io" || true
}

private_or_die() {
	local repo=$1 code
	printf 'FROM scratch\nLABEL org.opencontainers.image.source=%s\nCOPY <<EOF /visibility-check\nno 1C content\nEOF\n' \
		"${IMAGE_SOURCE:?}" | docker build -q -t "$repo:visibility-check" - >/dev/null
	docker push -q "$repo:visibility-check" >/dev/null
	for try in 1 2 3; do
		code=$(anonymous "$repo")
		case $code in
		401 | 403)
			echo "${repo#ghcr.io/}: без входа недоступен"
			return 0
			;;
		200)
			echo "::error::Пакет ${repo#ghcr.io/} доступен без входа, публикация остановлена"
			exit 1
			;;
		esac
		sleep $((try * 10))
	done
	echo "::error::Доступность пакета ${repo#ghcr.io/} без входа не проверилась (ответ $code), публикация остановлена"
	exit 1
}

no_1c_or_die() {
	local image=$1
	if ! docker run --rm --entrypoint /bin/sh "$image" -c 'test ! -e /opt/1cv8 && test ! -e /opt/1C && test ! -e /distr'; then
		echo "::error::В открытом образе $image есть файлы 1С, публикация остановлена"
		exit 1
	fi
}

repos=$(printf '%s\n' "${images[@]}" | sed 's/:[^:/]*$//' | sort -u)
for repo in $repos; do
	if ! is_public "$repo"; then
		private_or_die "$repo"
	fi
done
for image in "${images[@]}"; do
	if is_public "${image%:*}"; then
		no_1c_or_die "$image"
	fi
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

for repo in $repos; do
	if is_public "$repo" && [ "$(anonymous "$repo")" != 200 ]; then
		echo "::notice::Пакет ${repo#ghcr.io/} пока закрыт: в его настройках нужна видимость Public"
	fi
done
