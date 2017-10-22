#!/usr/bin/env bash

set -eu

# Parameters
IMAGE_DEVICE_NAME='Acer Chromebook 13 (CB5-311)'
RECOVERY_CONF_URL='https://dl.google.com/dl/edgedl/chromeos/recovery/recovery.conf'

function step {
	echo '==>' "$*"
}

if [ 0 -ne $(id -u) ]
then
    echo 'Please run this script as root.'
    exit 1
fi

CURL_BIN="$(which curl)"
if [ ! -x "$CURL_BIN" ]
then
	echo 'Please install curl.'
	exit 1
fi

step '==> Initializing...'

# Check if we can ping google.com
if ! ping -c 1 'google.com' &> /dev/null
then
	echo 'Make sure that you have a working internet connection'
	exit 1
fi

# Get image URL
FOUND_DEVICE=0
DEVICE_NAME=''
RECOVERY_URL=''
RECOVERY_FILE_NAME=''
RECOVERY_SHA1=''

while read line
do
	if [ -z "${line/name=*/}" -a "x" != "x${line}" ]
	then
		DEVICE_NAME="${line/name=/}"
	fi

	if [ "$DEVICE_NAME" == "$IMAGE_DEVICE_NAME" ]
	then
		FOUND_DEVICE=1
		if [ 'x' == "x${line}" ]; then
			# block is finished
			break
		fi

		case "${line/=*}" in
			url)
				RECOVERY_URL="${line/*=/}"
				;;
			file)
				RECOVERY_FILE_NAME="${line/*=/}"
				;;
			sha1)
				RECOVERY_SHA1="${line/*=/}"
				;;
		esac
	fi
done <<< "$("$CURL_BIN" "$RECOVERY_CONF_URL" 2>/dev/null)"

if [ 0 -eq ${FOUND_DEVICE:=0} ]
then
	echo 'Could not find device'
	exit 1
fi

step "Using device: ${DEVICE_NAME}"

# Download latest ChromeOS recovery image
if [ -z "$RECOVERY_URL" ]
then
	echo 'Cannot find url to download from.'
	exit 1
fi

RECOVERY_IMG_TMP_DIR="$(mktemp -d -t cros_recovery.XXXXXX)"
RECOVERY_ZIP_FILE="${RECOVERY_IMG_TMP_DIR:?}/${RECOVERY_URL##*/}"
RECOVERY_BIN_FILE="${RECOVERY_IMG_TMP_DIR:?}/${RECOVERY_FILE_NAME##*/}"

step "Downloading ${RECOVERY_URL} to ${RECOVERY_ZIP_FILE}"

rm -vf "${RECOVERY_ZIP_FILE:?}"
"$CURL_BIN" -# -L -S -o "${RECOVERY_ZIP_FILE:?}" "$RECOVERY_URL"

# Check downloaded file
step 'Checking downloaded image checksum'
FILE_SHA1="$(sha1sum "$RECOVERY_ZIP_FILE" | sed -e 's/\ .*//')"
if [ "$RECOVERY_SHA1" != "$FILE_SHA1" ]
then
	echo 'Image checksum does not match'
	echo '     is:' "$FILE_SHA1"
	echo ' should:' "$RECOVERY_SHA1"
	exit 2
fi
echo 'Image checksum matches'

# Extract recovery image
step "Extracting ${RECOVERY_ZIP_FILE}"
if ! unzip "${RECOVERY_ZIP_FILE:?}" "$RECOVERY_FILE_NAME" -d "${RECOVERY_IMG_TMP_DIR:?}"
then
	echo 'Extracting recovery image failed'
	exit 2
fi
rm -fv "${RECOVERY_ZIP_FILE:?}"

# Mount recovery image as loop device
step 'Setting up loop device...'
LOOP_DEV="$(losetup --read-only --find --show --partscan "${RECOVERY_BIN_FILE}")"

if [ -e "${LOOP_DEV}p*" ]
then
	echo "No partitions for ${LOOP_DEV}".
	exit 2
fi

# Mount ROOT-A
ROOTA_PART_NUM=3

while ! cgpt show "$LOOP_DEV" -i "$ROOTA_PART_NUM" -l 2>/dev/null | grep -P '^ROOT-A' &> /dev/null
do
    echo -e "Partition ${ROOTA_PART_NUM} of this recovery image is not ROOT-A\n"
    cgpt show "$LOOP_DEV"
    read -e -p "Which partition number is ROOT-A? (0-9) " -n 1 ROOTA_PART_NUM
done

step "Selected partition ${ROOTA_PART_NUM} as ROOT-A"

ROOTA_PART="${LOOP_DEV}p${ROOTA_PART_NUM}"
ROOTA_TMP_MNT="$(mktemp -d)"

step "Mounting ${ROOTA_PART} to ${ROOTA_TMP_MNT}"
mount -o ro -t ext4 "$ROOTA_PART" "$ROOTA_TMP_MNT"

# Extract pepperflash
REL_PEPFLASH_PATH='opt/google/chrome/pepper'
PEPFLASH_VERSION="$(sed -n -e 's/^VERSION="\([0-9\.r\-]*\)"/\1/p' "${ROOTA_TMP_MNT}/${REL_PEPFLASH_PATH}/pepper-flash.info")"
PEPFLASH_TARGET="$(mktemp --suffix=".${PEPFLASH_VERSION}.tar.gz" -t pepflash.XXXXXX)"

step 'Creating archive...'
tar -C "$ROOTA_TMP_MNT" -cvzf "${PEPFLASH_TARGET:?}" "$REL_PEPFLASH_PATH"

step 'Cleaning up...'
umount "${ROOTA_TMP_MNT:?}"
losetup --detach "$LOOP_DEV"
rm -frv "${RECOVERY_IMG_TMP_DIR:?}"

echo -e "\n\nCreated archive: ${PEPFLASH_TARGET}"
