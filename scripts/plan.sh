#!/bin/bash
# План сборки в CI: какие версии собирать и публиковать ли.
# Переменные среды:
#   EVENT          событие: workflow_dispatch, schedule, push, pull_request
#   REF            ветка запуска
#   PLATFORM, EDT  линейки или точные версии через пробел; пусто - из versions.json, "-" - не собирать
#   PUBLISH        публиковать ли при workflow_dispatch; публикуются только образы из main
#   NEW_ONLY       true - пропустить версии, которые уже опубликованы (по расписанию всегда);
#                  нужен вход в ghcr.io
#   BASE, HEAD     коммиты запроса на слияние: собираются только образы, чьи файлы изменились.
#                  Для push BASE - коммит последней успешной публикации (нужен gh с GH_TOKEN)
# В $GITHUB_OUTPUT: platform и edt (JSON-массивы {version, line}), publish.
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

# Какие образы затрагивают изменения; без базы - все
affected() {
	local files
	if [ -z "${BASE:-}" ] || ! files=$(git -c core.quotePath=false diff --name-only "$BASE...${HEAD:-HEAD}" 2>/dev/null); then
		echo 'platform edt'
		return
	fi
	local platform=0 edt=0 file
	while IFS= read -r file; do
		case $file in
		platform/* | vrunner/*) platform=1 ;;
		edt/* | tests/fixtures/*) edt=1 ;;
		scripts/* | tests/smoke.sh | versions.json | .github/workflows/images.yml | .github/actions/*)
			platform=1
			edt=1
			;;
		esac
	done <<<"$files"
	[ "$platform" = 1 ] && printf 'platform '
	[ "$edt" = 1 ] && printf 'edt'
	echo
}

# Опубликована ли версия целиком: последний тег, который отправляет публикация
published() {
	local kind=$1 version=$2 prefix image
	prefix="ghcr.io/${GITHUB_REPOSITORY,,}"
	case $kind in
	platform) image="$prefix/vrunner:$version-vrunner2-vnc" ;;
	edt) image="$prefix/edt:$version" ;;
	esac
	docker manifest inspect "$image" >/dev/null 2>&1
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
			version=$(bash scripts/distr.sh latest "$kind" "$item")
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
publish=false
new_only=${NEW_ONLY:-false}
case $EVENT in
schedule)
	publish=true
	new_only=true
	;;
workflow_dispatch)
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
	scope=$(affected)
	[[ $scope == *platform* ]] || platform=-
	[[ $scope == *edt* ]] || edt=-
	;;
esac

platform=$(resolve platform "$platform")
edt=$(resolve edt "$edt")
{
	echo "platform=$platform"
	echo "edt=$edt"
	echo "publish=$publish"
} >>"${GITHUB_OUTPUT:-/dev/stdout}"
