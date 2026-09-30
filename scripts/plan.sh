#!/bin/bash
# План сборки в CI: какие кубики и версии собирать и публиковать ли.
# Переменные среды:
#   EVENT             событие: workflow_dispatch, schedule, push, pull_request
#   REF               ветка запуска
#   PLATFORM, EDT     линейки или точные версии через пробел; пусто - из versions.json, "-" - не собирать
#   TOOLS             собирать ли onescript и downloader при workflow_dispatch
#   PUBLISH           публиковать ли при workflow_dispatch; публикуются только образы из main
#   NEW_ONLY          true - пропустить версии, которые уже опубликованы (по расписанию всегда);
#                     нужен вход в ghcr.io
#   BASE, HEAD        коммиты запроса на слияние: собираются изменённые кубики и то, что на них построено.
#                     Для push BASE - коммит последней успешной публикации (нужен gh с GH_TOKEN)
#   DOWNLOADER_IMAGE  образ загрузчика для поиска сборок линеек, учётная запись в ONEC_LOGIN и ONEC_PASSWORD
# В $GITHUB_OUTPUT: changed (кубики через пробел или all), tools, platform и edt (JSON-массивы
# {version, line}), publish.
set -euo pipefail
shopt -s inherit_errexit

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

last_published() {
	local sha
	sha=$(gh run list -R "$GITHUB_REPOSITORY" --workflow images.yml --branch main --event push \
		--status success --limit 1 --json headSha --jq '.[0].headSha // ""' 2>/dev/null) || return 0
	if [ -n "$sha" ] && git merge-base --is-ancestor "$sha" "${HEAD:-HEAD}" 2>/dev/null; then
		echo "$sha"
	fi
}

# Изменённые кубики через пробел; без базы и при изменении общих файлов - all
affected() {
	local files file cubes=()
	if [ -z "${BASE:-}" ] || ! files=$(git -c core.quotePath=false diff --name-only "$BASE...${HEAD:-HEAD}" 2>/dev/null); then
		echo all
		return
	fi
	while IFS= read -r file; do
		case $file in
		server/* | client/* | vnc/* | onescript/* | downloader/* | vrunner/* | edt/*) cubes+=("${file%%/*}") ;;
		tests/fixtures/*) cubes+=(edt) ;;
		scripts/* | tests/smoke.sh | versions.json | .github/workflows/images.yml)
			echo all
			return
			;;
		esac
	done <<<"$files"
	[ ${#cubes[@]} -eq 0 ] || printf '%s\n' "${cubes[@]}" | sort -u | paste -sd ' '
}

has() {
	[[ " $changed " == *" all "* ]] && return 0
	local cube
	for cube in "$@"; do
		[[ " $changed " == *" $cube "* ]] && return 0
	done
	return 1
}

# Опубликована ли версия целиком: первый и последний образы, которые отправляет публикация
published() {
	local kind=$1 version=$2 prefix image
	prefix="ghcr.io/${GITHUB_REPOSITORY,,}"
	case $kind in
	platform) set -- "$prefix/server:$version" "$prefix/vrunner:$version-vrunner2-vnc" ;;
	edt) set -- "$prefix/edt:$version" ;;
	esac
	for image; do
		docker manifest inspect "$image" >/dev/null 2>&1 || return 1
	done
}

# $1 - platform или edt, $2 - запрошенное; печатает JSON-массив {version, line}
resolve() {
	local kind=$1 requested=$2 exact item version line result='[]'
	case $kind in
	platform) exact='^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' ;;
	edt) exact='^[0-9]{4}\.[0-9]+\.[0-9]+$' ;;
	esac
	if [ -z "$requested" ]; then
		requested=$(jq -r --arg kind "$kind" '.[$kind] | join(" ")' versions.json)
	fi
	[ "$requested" = - ] && requested=
	for item in $requested; do
		if [[ $item =~ $exact ]]; then
			version=$item
			line=
		else
			version=$(docker run --rm -e ONEC_LOGIN -e ONEC_PASSWORD "${DOWNLOADER_IMAGE:?}" latest "$kind" "$item")
			line=$item
		fi
		if [ "$new_only" = true ] && published "$kind" "$version"; then
			echo "$kind $item: $version уже опубликована" >&2
			continue
		fi
		echo "$kind $item: $version" >&2
		result=$(jq -c --arg v "$version" --arg l "$line" '. + [{version: $v, line: $l}] | unique_by(.version)' <<<"$result")
	done
	echo "$result"
}

platform=${PLATFORM:-}
edt=${EDT:-}
changed=all
tools=false
publish=false
new_only=${NEW_ONLY:-false}
case $EVENT in
schedule)
	publish=true
	new_only=true
	;;
workflow_dispatch)
	tools=${TOOLS:-false}
	if [ "${PUBLISH:-false}" = true ]; then
		if [ "${REF:-}" = refs/heads/main ]; then
			publish=true
		else
			echo '::notice::Публикуются только образы из main, эта сборка только проверяется'
		fi
	fi
	;;
*)
	if [ "$EVENT" = push ]; then
		publish=true
		BASE=$(last_published)
	fi
	changed=$(affected)
	has onescript downloader && tools=true
	has server client vnc onescript vrunner || platform=-
	has edt || edt=-
	;;
esac
echo "Кубики: ${changed:-нет}" >&2

platform=$(resolve platform "$platform")
edt=$(resolve edt "$edt")
{
	echo "changed=$changed"
	echo "tools=$tools"
	echo "platform=$platform"
	echo "edt=$edt"
	echo "publish=$publish"
} >>"${GITHUB_OUTPUT:-/dev/stdout}"
