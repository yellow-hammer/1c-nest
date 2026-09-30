#!/bin/bash
# Сборка образов из каталога дистрибутива (см. distr.sh).
#   build.sh platform <версия> <каталог>  платформа и vrunner во всех вариантах
#   build.sh edt <версия> <каталог>       1C:EDT
# Имена образов: $IMAGE_PREFIX/<образ>:<тег>, по умолчанию 1c-nest/...
# Собранные образы печатаются по одному в строке.
set -euo pipefail
shopt -s inherit_errexit

root=$(cd "$(dirname "$0")/.." && pwd)
prefix=${IMAGE_PREFIX:-1c-nest}
labels=()
if [ -n "${IMAGE_SOURCE:-}" ]; then
	labels+=(--label "org.opencontainers.image.source=$IMAGE_SOURCE")
fi
if [ -n "${IMAGE_REVISION:-}" ]; then
	labels+=(--label "org.opencontainers.image.revision=$IMAGE_REVISION")
fi

build() {
	local tag=$1
	shift
	docker build "${labels[@]}" -t "$tag" "$@" >&2
	echo "$tag"
}

platform() {
	local version=$1 distr=$2
	local base="$prefix/platform:$version"
	build "$base" --build-context distr="$distr" --build-arg ONEC_VERSION="$version" "$root/platform"
	build "$prefix/vrunner:$version" --build-arg BASE_IMAGE="$base" --target vrunner "$root/vrunner"
	build "$prefix/vrunner:$version-vrunner2" --build-arg BASE_IMAGE="$base" --target vrunner2 "$root/vrunner"
	build "$prefix/vrunner:$version-vnc" --build-arg BASE_IMAGE="$base" --target vnc \
		--build-arg FLAVOR=vrunner "$root/vrunner"
	build "$prefix/vrunner:$version-vrunner2-vnc" --build-arg BASE_IMAGE="$base" --target vnc \
		--build-arg FLAVOR=vrunner2 "$root/vrunner"
}

edt() {
	local version=$1 distr=$2
	build "$prefix/edt:$version" --build-context distr="$distr" --build-arg EDT_VERSION="$version" "$root/edt"
}

case ${1:-} in
platform) platform "${2:?версия}" "${3:?каталог дистрибутива}" ;;
edt) edt "${2:?версия}" "${3:?каталог дистрибутива}" ;;
*)
	echo 'Использование: build.sh platform|edt <версия> <каталог дистрибутива>' >&2
	exit 1
	;;
esac
