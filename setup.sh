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
if [ -z "${CONTAINER}" ]; then
	## container is not around, build
	DATE="$(date +%Y%m%d%H%M)"
	if [ -z "${XILINXMAIL}" ]; then
		die "pls, provide an env variable XILINXMAIL (login email for xilinx)"
	fi
	if [ -z "${XILINXLOGIN}" ]; then
		die "pls, provide an env variable XILINXLOGIN (password for the xilinx login, under with the email '$XILINXLOGIN')"
	fi

	test -f ${TOPDIR}/${DOWNLOADDIR}/*_Unified_SDI_${VERSION}_*_Lin64.bin || die "No *_Unified_${VERSION}_*_Lin64.bin file provided in '${TOPDIR}/${DOWNLOADDIR}'"

	mv ${TOPDIR}/${DOWNLOADDIR}/*_Unified_SDI_${VERSION}_*_Lin64.bin "${TOPDIR}/${DOCKERDIR}/build_context/"

	cd "$DOCKERDIR"
	docker build \
		--tag ${IMAGE}:${DATE} \
		--build-arg UID=${HOST_UID} \
		--build-arg GID=${HOST_GID} \
		--build-arg USER=${USER} \
		--build-arg XILINXMAIL=${XILINXMAIL} \
		--build-arg XILINXLOGIN=${XILINXLOGIN} \
		./build_context
	cd "${TOPDIR}/${DOCKERDIR}"

else
	## container around, start
	cd "${DOCKERDIR}"
	APP="/bin/bash"
	if [ ! -e .env ]; then
		APP=""
		echo "UID=$(id -u)" > .env
		echo "GID=$(id -g)" >> .env
		echo
		echo "Preparing docker images - please re-run this script to enter the container image!"
	fi

	docker run \
		--rm \
		--net host \
		--name ${IMAGE} \
		-u ${HOST_UID}:${HOST_GID} \
		-it \
		--privileged \
		-e USER \
		-e DISPLAY=$DISPLAY \
		-e XAUTHORITY=/tmp/.Xauthority \
		-e QT_X11_NO_MITSHM=1 \
		-e QT_QPA_PLATFORM=xcb \
		-e _JAVA_AWT_WM_NONREPARENTING=1 \
		-e _JAVA_OPTIONS="-Dsun.java2d.xrender=false -Dsun.java2d.pmoffscreen=false -Dsun.java2d.opengl=false" \
		-v /tmp/.X11-unix:/tmp/.X11-unix:rw \
		-v $XAUTHORITY:/tmp/.Xauthority:ro \
		--env-file .env \
		--group-add 20 \
		--mount type=bind,source=./build_configs,target=/home/$USER/configs \
		-v ~/.gitconfig:/home/${USER}/.gitconfig:ro \
		-v ~/.ssh:/home/${USER}/.ssh \
		-v ./workspace:/home/${USER}/workspace \
		-v ~/.Xilinx:/home/${USER}/.Xilinx \
		-v ~/.config/Xilinx:/home/${USER}/.config/Xilinx \
		-v /home/${USER}:/home/localhost \
		${CONTAINER} \
		${APP}

	exit 0
fi

echo "READY."

