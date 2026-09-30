#!/bin/bash
# Сборка образов из кубиков.
#   build.sh tools               onescript 2.1.0 и 1.9.4, downloader
#   build.sh platform <версия>   server, client, client-vnc и vrunner во всех вариантах
#   build.sh edt <версия>        1C:EDT
# Дистрибутив скачивается при сборке с учётной записью из ONEC_LOGIN и ONEC_PASSWORD загрузчиком
# DOWNLOADER_IMAGE (без него загрузчик собирается из репозитория) или берётся из каталога DISTR.
# CHANGED - изменённые кубики через пробел (server client vnc onescript vrunner) или all, по умолчанию all.
# Неизменённые образы, на которых строятся изменённые, берутся из реестра, а если их там нет, собираются.
# Имена образов: $IMAGE_PREFIX/<образ>:<тег>, по умолчанию 1c-nest/...
# Собранные образы печатаются по одному в строке.
set -euo pipefail
shopt -s inherit_errexit

root=$(cd "$(dirname "$0")/.." && pwd)
prefix=${IMAGE_PREFIX:-1c-nest}
changed=" ${CHANGED:-all} "
onescript=2.1.0
onescript_legacy=1.9.4
vrunner_legacy=2.6.1

labels=()
if [ -n "${IMAGE_SOURCE:-}" ]; then
	labels+=(--label "org.opencontainers.image.source=$IMAGE_SOURCE")
fi
if [ -n "${IMAGE_REVISION:-}" ]; then
	labels+=(--label "org.opencontainers.image.revision=$IMAGE_REVISION")
fi

stages=()
# shellcheck disable=SC2317,SC2329 # вызывается из trap
cleanup() {
	[ ${#stages[@]} -eq 0 ] || docker image rm "${stages[@]}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Образ, который публикуется
build() {
	local tag=$1 meta=()
	shift
	if [[ ${tag##*:} =~ ^[0-9] ]]; then
		meta=(--label "org.opencontainers.image.version=${tag##*:}")
	fi
	docker build "${labels[@]}" "${meta[@]}" -t "$tag" "$@" >&2
	echo "$tag"
}

# Промежуточный образ цепочки
stage() {
	local tag=$1
	shift
	docker build -t "$tag" "$@" >&2
	stages+=("$tag")
}

changed() {
	[[ $changed == *" all "* || $changed == *" $1 "* ]]
}

# Образ есть локально или скачан из реестра
available() {
	docker image inspect "$1" >/dev/null 2>&1 || docker pull -q "$1" >/dev/null 2>&1
}

# Аргументы сборки образов со стадией distr
distr=()
distr_args() {
	[ ${#distr[@]} -eq 0 ] || return 0
	if [ -n "${DISTR:-}" ]; then
		distr=(--build-context "distr=$DISTR")
		return 0
	fi
	if [ -z "${ONEC_LOGIN:-}" ] || [ -z "${ONEC_PASSWORD:-}" ]; then
		echo 'Нужен дистрибутив: каталог в DISTR или учётная запись releases.1c.ru в ONEC_LOGIN и ONEC_PASSWORD' >&2
		exit 1
	fi
	if [ -z "${DOWNLOADER_IMAGE:-}" ]; then
		stage 1c-nest-build/onescript "$root/onescript"
		stage 1c-nest-build/downloader --build-arg BASE_IMAGE=1c-nest-build/onescript "$root/downloader"
		DOWNLOADER_IMAGE=1c-nest-build/downloader
	fi
	distr=(--build-arg "DOWNLOADER_IMAGE=$DOWNLOADER_IMAGE" --secret id=ONEC_LOGIN --secret id=ONEC_PASSWORD)
}

tools() {
	build "$prefix/onescript:$onescript" "$root/onescript"
	build "$prefix/onescript:$onescript_legacy" --build-arg ONESCRIPT_VERSION="$onescript_legacy" "$root/onescript"
	build "$prefix/downloader:latest" --build-arg BASE_IMAGE="$prefix/onescript:$onescript" "$root/downloader"
}

# vanessa-runner 3 и 2 поверх образа $2; $3 дописывается к тегам
vrunners() {
	local version=$1 base=$2 suffix=$3
	stage "1c-nest-build/onescript:$version$suffix" --build-arg BASE_IMAGE="$base" "$root/onescript"
	build "$prefix/vrunner:$version$suffix" \
		--build-arg BASE_IMAGE="1c-nest-build/onescript:$version$suffix" "$root/vrunner"
	stage "1c-nest-build/onescript-legacy:$version$suffix" --build-arg BASE_IMAGE="$base" \
		--build-arg ONESCRIPT_VERSION="$onescript_legacy" "$root/onescript"
	build "$prefix/vrunner:$version-vrunner2$suffix" \
		--build-arg BASE_IMAGE="1c-nest-build/onescript-legacy:$version$suffix" \
		--build-arg VRUNNER_VERSION="$vrunner_legacy" "$root/vrunner"
}

platform() {
	local version=$1
	local server="$prefix/server:$version" client="$prefix/client:$version" vnc="$prefix/client-vnc:$version"
	local runner=0 new_client=0 new_vnc=0
	if changed onescript || changed vrunner; then
		runner=1
	fi

	if changed server; then
		distr_args
		build "$server" "${distr[@]}" --build-arg ONEC_VERSION="$version" "$root/server"
	fi
	if changed client || { { changed vnc || [ $runner = 1 ]; } && ! available "$client"; }; then
		distr_args
		build "$client" "${distr[@]}" --build-arg ONEC_VERSION="$version" "$root/client"
		new_client=1
	fi
	if [ $new_client = 1 ] || changed vnc || { [ $runner = 1 ] && ! available "$vnc"; }; then
		build "$vnc" --build-arg BASE_IMAGE="$client" "$root/vnc"
		new_vnc=1
	fi
	if [ $new_client = 1 ] || [ $runner = 1 ]; then
		vrunners "$version" "$client" ''
	fi
	if [ $new_vnc = 1 ] || [ $runner = 1 ]; then
		vrunners "$version" "$vnc" -vnc
	fi
}

edt() {
	local version=$1
	distr_args
	build "$prefix/edt:$version" "${distr[@]}" --build-arg EDT_VERSION="$version" "$root/edt"
}

case ${1:-} in
tools) tools ;;
platform) platform "${2:?версия}" ;;
edt) edt "${2:?версия}" ;;
*)
	echo 'Использование: build.sh tools | platform <версия> | edt <версия>' >&2
	exit 1
	;;
esac
