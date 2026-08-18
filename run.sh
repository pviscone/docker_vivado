#!/bin/sh -e
set -u

mkdir -p ~/.Xilinx/Vivado
mkdir -p ~/.config/Xilinx

DRYRUN="${1:-}"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
xhost +SI:localuser:$(id -un)

USER="$(whoami)"

die() {
  echo "FAILED! $@."
  exit 1
}

# =========================
# HARD-CODED VALUES
# =========================
DOCKERDIR="docker"
DOWNLOADDIR="download"

# These must match your Dockerfile ARG/requirements if you rebuild elsewhere.
# Based on your docker images output:
IMAGE_REPO="vivado-2025.2"
IMAGE_TAG="202607201036"
IMAGE_REF="${IMAGE_REPO}:${IMAGE_TAG}"
CONTAINER_ID="$(docker images -q "${IMAGE_REF}" | head -n 1 || true)"

# If you want the build branch to also be hardcoded, set VERSION and the expected bin pattern.
VERSION="202607201036"

TOPDIR="$(pwd)"

# =========================
# MAIN
# =========================
# Keep your git-branch guard
if [ -d ".git" ]; then
  if [ "main" = "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)" ]; then
    die "THIS IS MAIN, PLEASE CHANGE TO ONE OF THE GIT BRANCHES"
  fi
fi

# Decide whether to build or run
if [ -z "${CONTAINER_ID}" ]; then
  # container is not around, build
  DATE="$(date +%Y%m%d%H%M)"

  # Still require creds at build time (hardcoding them would be unsafe)
  : "${XILINXMAIL:?provide env var XILINXMAIL (login email for xilinx)}"
  : "${XILINXLOGIN:?provide env var XILINXLOGIN (password for the xilinx login)}"

  cd "${TOPDIR}/${DOCKERDIR}"
  test -f "${TOPDIR}/${DOWNLOADDIR}"/*_Unified_SDI_${VERSION}_*_Lin64.bin || \
    die "No *_Unified_${VERSION}_*_Lin64.bin file provided in '${TOPDIR}/${DOWNLOADDIR}'"

  cp "${TOPDIR}/${DOWNLOADDIR}/"*"_Unified_SDI_${VERSION}_"*"_Lin64.bin" "${TOPDIR}/${DOCKERDIR}/build_context/"

  cd "${TOPDIR}/${DOCKERDIR}"
  docker build \
    --network host \
    --tag "${IMAGE_REF}" \
    --build-arg UID="${HOST_UID}" \
    --build-arg GID="${HOST_GID}" \
    --build-arg USER="${USER}" \
    --build-arg XILINXMAIL="${XILINXMAIL}" \
    --build-arg XILINXLOGIN="${XILINXLOGIN}" \
    ./build_context

  # Update CONTAINER_ID after build
  CONTAINER_ID="$(docker images -q "${IMAGE_REF}" | head -n 1 || true)"
  [ -n "${CONTAINER_ID}" ] || die "Build finished but image '${IMAGE_REF}' not found"
fi

# container around, start
cd "${TOPDIR}/${DOCKERDIR}"

# Keep your .env behavior (hardcoded image run)
APP="/bin/bash"
if [ ! -e ".env" ]; then
  APP=""
  echo "UID=$(id -u)" > .env
  echo "GID=$(id -g)" >> .env
  echo
  echo "Preparing docker images - please re-run this script to enter the container image!"
fi

# If APP is empty, we just run the container without extra command to use image default
if [ -n "${APP}" ]; then
  docker run \
    --rm \
    --net host \
    --name "${IMAGE_REPO}" \
    -u "${HOST_UID}:${HOST_GID}" \
    -it \
    --privileged \
    -e USER="${USER}" \
    -e DISPLAY="${DISPLAY}" \
    -e XAUTHORITY=/tmp/.Xauthority \
    -e QT_X11_NO_MITSHM=1 \
    -e QT_QPA_PLATFORM=xcb \
    -e _JAVA_AWT_WM_NONREPARENTING=1 \
    -e _JAVA_OPTIONS="-Dsun.java2d.xrender=false -Dsun.java2d.pmoffscreen=false -Dsun.java2d.opengl=false" \
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
    -v "${XAUTHORITY}:/tmp/.Xauthority:ro" \
    --env-file .env \
    --group-add 20 \
    --mount type=bind,source=./build_configs,target=/home/"${USER}"/configs \
    -v /dev/bus/usb:/dev/bus/usb \
    -v "${HOME}/.gitconfig":/home/"${USER}"/.gitconfig:ro \
    -v "${HOME}/.ssh":/home/"${USER}"/.ssh \
    -v ./workspace:/home/"${USER}"/workspace \
    -v "${HOME}/.Xilinx":/home/"${USER}"/.Xilinx \
    -v "${HOME}/.config/Xilinx":/home/"${USER}"/.config/Xilinx \
    -v /home/"${USER}":/home/localhost \
    "${IMAGE_REF}" \
    "${APP}"
else
  docker run \
    --rm \
    --net host \
    --name "${IMAGE_REPO}" \
    -u "${HOST_UID}:${HOST_GID}" \
    -it \
    --privileged \
    -e USER="${USER}" \
    -e DISPLAY="${DISPLAY}" \
    -e XAUTHORITY=/tmp/.Xauthority \
    -e QT_X11_NO_MITSHM=1 \
    -e QT_QPA_PLATFORM=xcb \
    -e _JAVA_AWT_WM_NONREPARENTING=1 \
    -e _JAVA_OPTIONS="-Dsun.java2d.xrender=false -Dsun.java2d.pmoffscreen=false -Dsun.java2d.opengl=false" \
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
    -v "${XAUTHORITY}:/tmp/.Xauthority:ro" \
    --env-file .env \
    --group-add 20 \
    --mount type=bind,source=./build_configs,target=/home/"${USER}"/configs \
    -v /dev/bus/usb:/dev/bus/usb \
    -v "${HOME}/.gitconfig":/home/"${USER}"/.gitconfig:ro \
    -v "${HOME}/.ssh":/home/"${USER}"/.ssh \
    -v ./workspace:/home/"${USER}"/workspace \
    -v "${HOME}/.Xilinx":/home/"${USER}"/.Xilinx \
    -v "${HOME}/.config/Xilinx":/home/"${USER}"/.config/Xilinx \
    -v /home/"${USER}":/home/localhost \
    "${IMAGE_REF}"
fi

exit 0
