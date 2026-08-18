#!/bin/sh -e
mkdir -p ~/.Xilinx/Vivado
mkdir -p ~/.config/Xilinx

DRYRUN="${1}"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

export DISPLAY=${DISPLAY:-:0}
export XAUTHORITY=${XAUTHORITY:-$HOME/.Xauthority}
xhost +SI:localuser:$(id -un)

USER="$(whoami)"

die()
{
	echo "FAILED! $@."
	exit 1
}

## MAIN
if [ -d ".git" ]; then
	## if this is a git repo, check if we're on branch "main", then abort
	if [ "main" = "$( git rev-parse --abbrev-ref HEAD )" ]; then
		die "THIS IS MAIN, PLEASE CHANGE TO ONE OF THE GIT BRANCHES"
	fi
fi

test -z "${DOCKERDIR}" && DOCKERDIR="docker"
test -z "${DOWNLOADDIR}" && DOWNLOADDIR="download"
TOPDIR="$(pwd)"
IMAGE="$( grep "^FROM" -HIrn ${DOCKERDIR}/build_context/Dockerfile | awk '{ print $NF }' )"
VERSION="$( echo ${IMAGE} | awk -F'-' '{ if ($NF == "nightly") {print $(NF-1)} else {print $NF} }' )"
CONTAINER="$( docker images -q ${IMAGE} 2> /dev/null )" || true

## container is not around, build
DATE="$(date +%Y%m%d%H%M)"
if [ -z "${XILINXMAIL}" ]; then
	die "pls, provide an env variable XILINXMAIL (login email for xilinx)"
fi
if [ -z "${XILINXLOGIN}" ]; then
	die "pls, provide an env variable XILINXLOGIN (password for the xilinx login, under with the email '$XILINXLOGIN')"
fi

test -f ${TOPDIR}/${DOWNLOADDIR}/*_Unified_${VERSION}_*_Lin64.bin || die "No *_Unified_${VERSION}_*_Lin64.bin file provided in '${TOPDIR}/${DOWNLOADDIR}'"

cp ${TOPDIR}/${DOWNLOADDIR}/*_Unified_${VERSION}_*_Lin64.bin "${TOPDIR}/${DOCKERDIR}/build_context/"

cd "$DOCKERDIR"
docker build \
	--network host \
	--tag ${IMAGE}:${DATE} \
	--build-arg UID=${HOST_UID} \
	--build-arg GID=${HOST_GID} \
	--build-arg USER=${USER} \
	--build-arg XILINXMAIL=${XILINXMAIL} \
	--build-arg XILINXLOGIN=${XILINXLOGIN} \
	./build_context
cd "${TOPDIR}/${DOCKERDIR}"

echo "READY."

