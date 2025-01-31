#!/usr/bin/env bash

# Build bootable full disk image containing the initial system image.

set -eo pipefail

function usage() {
    cat <<EOF

Usage:
  build-disk-image -o outfile -v version -x execdir [-t dev] [-p password]

  Build whole disk of IC guest OS VM image.

  -o outfile: Name of output file; mandatory
  -v version: The version written into the image; mandatory
  -x execdir: Set executable source dir. Will take all required IC executables
       from source directory and install it into the correct location before
       building the image; mandatory
  -t image type: The type of image to build. Must be either "dev" or "prod".
     If nothing is specified, defaults to building "prod" image.
  -p password: Set root password for console access. This is only allowed
     for "dev" images

EOF
}

BUILD_TYPE=prod
while getopts "o:t:v:p:x:" OPT; do
    case "${OPT}" in
        o)
            OUT_FILE="${OPTARG}"
            ;;
        t)
            BUILD_TYPE="${OPTARG}"
            ;;
        v)
            VERSION="${OPTARG}"
            ;;
        p)
            ROOT_PASSWORD="${OPTARG}"
            ;;
        x)
            EXEC_SRCDIR="${OPTARG}"
            ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
done

# Preparatory steps and temporary build directory.
BASE_DIR=$(dirname "${BASH_SOURCE[0]}")/..

TOOL_DIR="${BASE_DIR}/../../toolchains/sysimage/"

TMPDIR=$(mktemp -d -t build-image-XXXXXXXXXXXX)
trap "rm -rf $TMPDIR" exit

# Validate and process arguments

if [ "${OUT_FILE}" == "" ]; then
    usage >&2
    exit 1
fi

if [ "${BUILD_TYPE}" != "dev" -a "${BUILD_TYPE}" != "prod" ]; then
    echo "Unknown build type: ${BUILD_TYPE}" >&2
    exit 1
fi

if [ "${ROOT_PASSWORD}" != "" -a "${BUILD_TYPE}" != "dev" ]; then
    echo "Root password is valid only for build type 'dev'" >&2
    exit 1
fi

if [ "${VERSION}" == "" ]; then
    echo "Version needs to be specified for build to succeed" >&2
    usage >&2
    exit 1
fi

if [ "${EXEC_SRCDIR}" == "" ]; then
    echo "Execdir needs to be specified for build to succeed" >&2
    usage >&2
    exit 1
fi

BASE_IMAGE=$(cat "${BASE_DIR}/rootfs/docker-base.${BUILD_TYPE}")

# HACK: build required system binaries
make -C ${BASE_DIR}/src infogetty prestorecon

# Compute arguments for actual build stage.

declare -a IC_EXECUTABLES=(orchestrator replica canister_sandbox sandbox_launcher vsock_agent state-tool ic-consensus-pool-util ic-crypto-csp ic-regedit ic-recovery ic-btc-adapter ic-canister-http-adapter)
declare -a INSTALL_EXEC_ARGS=()
for IC_EXECUTABLE in "${IC_EXECUTABLES[@]}"; do
    INSTALL_EXEC_ARGS+=("${EXEC_SRCDIR}/${IC_EXECUTABLE}:/opt/ic/bin/${IC_EXECUTABLE}:0755")
done
INSTALL_EXEC_ARGS+=("${BASE_DIR}/src/infogetty:/opt/ic/bin/infogetty:0755")
INSTALL_EXEC_ARGS+=("${BASE_DIR}/src/prestorecon:/opt/ic/bin/prestorecon:0755")

if [ "${BUILD_TYPE}" == "dev" ]; then
    INSTALL_EXEC_ARGS+=("${BASE_DIR}/allow_console_root:/etc/allow_console_root:0644")
fi

echo "${VERSION}" >"${TMPDIR}/version.txt"

# Build all pieces and assemble the disk image.

# If specified, and ONLY on dev, add an additional layer to the built image,
# containing an extra certificate.
if [ "${BUILD_TYPE}" == "dev" -a "${DEV_ROOT_CA}" != "" ]; then
    EXTRA_DOCKERFILE=("--extra-dockerfile" "${BASE_DIR}/rootfs/Dockerfile.dev" "--extra-vars" "DEV_ROOT_CA=$(cat ${DEV_ROOT_CA})")
fi
"${TOOL_DIR}"/docker_tar.py -o "${TMPDIR}/rootfs-tree.tar" "${EXTRA_DOCKERFILE[@]}" -- \
    --build-arg ROOT_PASSWORD="${ROOT_PASSWORD}" \
    --build-arg BASE_IMAGE="${BASE_IMAGE}" \
    "${BASE_DIR}/rootfs"
"${TOOL_DIR}"/docker_tar.py -o "${TMPDIR}/boot-tree.tar" "${BASE_DIR}/bootloader"
"${TOOL_DIR}"/build_vfat_image.py -o "${TMPDIR}/partition-esp.tar" -s 100M -p boot/efi -i "${TMPDIR}/boot-tree.tar"
"${TOOL_DIR}"/build_vfat_image.py -o "${TMPDIR}/partition-grub.tar" -s 100M -p boot/grub -i "${TMPDIR}/boot-tree.tar" \
    "${BASE_DIR}/grub.cfg:/boot/grub/grub.cfg:644" \
    "${BASE_DIR}/grubenv:/boot/grub/grubenv:644"
"${TOOL_DIR}"/build_ext4_image.py -o "${TMPDIR}/partition-config.tar" -s 100M
tar xOf "${TMPDIR}"/rootfs-tree.tar --occurrence=1 etc/selinux/default/contexts/files/file_contexts >"${TMPDIR}/file_contexts"
"${TOOL_DIR}"/build_ext4_image.py --strip-paths /run /boot -o "${TMPDIR}/partition-root-unsigned.tar" -s 3G -i "${TMPDIR}/rootfs-tree.tar" -S "${TMPDIR}/file_contexts" \
    "${INSTALL_EXEC_ARGS[@]}" \
    "${TMPDIR}/version.txt:/opt/ic/share/version.txt:0644"
"${TOOL_DIR}"/verity_sign.py -i "${TMPDIR}/partition-root-unsigned.tar" -o "${TMPDIR}/partition-root.tar" -r "${TMPDIR}/partition-root-hash"
sed -e s/ROOT_HASH/$(cat "${TMPDIR}/partition-root-hash")/ <"${BASE_DIR}/extra_boot_args.template" >"${TMPDIR}/extra_boot_args"
"${TOOL_DIR}"/build_ext4_image.py -o "${TMPDIR}/partition-boot.tar" -s 1G -i "${TMPDIR}/rootfs-tree.tar" -S "${TMPDIR}/file_contexts" -p boot/ \
    "${TMPDIR}/version.txt:/boot/version.txt:0644" \
    "${TMPDIR}/extra_boot_args:/boot/extra_boot_args:0644"
"${TOOL_DIR}"/build_disk_image.py -o "${TMPDIR}/disk.img.tar" -p "${BASE_DIR}/scripts/partitions.csv" \
    ${TMPDIR}/partition-esp.tar \
    ${TMPDIR}/partition-grub.tar \
    ${TMPDIR}/partition-config.tar \
    ${TMPDIR}/partition-boot.tar \
    ${TMPDIR}/partition-root.tar

# For compatibility with previous use of this script, provide the raw
# image as output from this program.
OUT_DIRNAME="$(dirname "${OUT_FILE}")"
OUT_BASENAME="$(basename "${OUT_FILE}")"
tar xf "${TMPDIR}/disk.img.tar" --transform="s/disk.img/${OUT_BASENAME}/" -C "${OUT_DIRNAME}"
# increase size a bit, for immediate qemu use (legacy)
truncate --size 50G "${OUT_FILE}"
