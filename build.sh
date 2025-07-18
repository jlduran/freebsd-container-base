#!/bin/sh

# SPDX-License-Identifier: MIT

# build.sh: Build FreeBSD container images from base

# Use curl, fetch or wget to DOWNLOAD
CURL="curl -s"      # macOS
FETCH="fetch -qo -" # FreeBSD
WGET="wget -qO -"   # Linux (mostly)

# Print an error message and exit
# $*: error message
err() {
	echo "Error: $*" >&2
	exit 1
}

# Check prerequisites
check_prerequisites()
{
	buildah --version > /dev/null || err "Please install buildah."
	tar --version | grep bsdtar > /dev/null || err "Please install BSD tar."
}

# Set the downloader command
# $1: downloader
set_downloader()
{
	case "$1" in
		"curl")
			DOWNLOAD="$CURL"
			;;
		"fetch")
			DOWNLOAD="$FETCH"
			;;
		"wget")
			DOWNLOAD="$WGET"
			;;
	esac
}

# Check if the system has a proper downloader:
# currently curl, fetch or wget are accepted
check_downloader()
{
	for _cmd in curl fetch wget; do
		if [ -x "/usr/bin/${_cmd}" ] || \
		    [ -x "/usr/local/bin/${_cmd}" ]; then
			set_downloader $_cmd
			break
		fi
	done

	if [ -z "$DOWNLOAD" ]; then
		err "Please install curl or wget."
	fi
}

# Get the appropriate architecture name
# $1: machine type
get_arch()
{
	case "$1" in
		amd64) echo amd64 ;;
		arm64) echo aarch64 ;;
		*) err "Machine type ${1} not supported" ;;
	esac
}

# Get the full FreeBSD version
# $1: short version
get_full_version()
{
	case "$1" in
		15.0) echo 15.0-CURRENT ;;
		14.3) echo 14.3-RELEASE ;;
		*) err "Version ${1} not supported" ;;
	esac
}

# Get the base URL for downloading the tar file
# $1: short version
get_base_url()
{
	case "$1" in
		15.0) echo snapshots ;;
		14.3) echo releases ;;
		*) err "Version ${1} not supported" ;;
	esac
}

# XXX Remove stuff we don't need
# $1: base root directory
prune_base()
{
	base_root="$1"

	rm -rf "${base_root:?}/boot/*"
	rm -rf "${base_root:?}/boot/dtb/*"
	rm -rf "${base_root:?}/boot/fonts/*"
	rm -rf "${base_root:?}/boot/images/*"
	rm -rf "${base_root:?}/boot/lua/*"
	rm -rf "${base_root:?}/etc/freebsd-update.conf"
	rm -rf "${base_root:?}/etc/hosts"
	rm -rf "${base_root:?}/etc/mail/*.sample"
	rm -rf "${base_root:?}/rescue"
	rm -rf "${base_root:?}/usr/sbin/freebsd-update"
	rm -rf "${base_root:?}/usr/share/bsdconfig/*"
	rm -rf "${base_root:?}/usr/share/doc"
	rm -rf "${base_root:?}/usr/share/examples"
	rm -rf "${base_root:?}/usr/share/games/fortune/*"
	rm -rf "${base_root:?}/usr/share/man"
	rm -rf "${base_root:?}/usr/share/misc"
	rm -rf "${base_root:?}/usr/share/openssl/man"
	rm -rf "${base_root:?}/usr/share/sendmail/"
	rm -rf "${base_root:?}/usr/tests/*"
	rm -rf "${base_root:?}/var/db/etcupdate"
	rm -rf "${base_root:?}/var/db/freebsd-update/*"
	rm -rf "${base_root:?}/var/yp/*"
}

# Usage instructions
usage() {
	printf 'Build FreeBSD container images from base\n\n'
	printf 'Usage:\n'
	printf '  %s [-hl] [-c cpu] [-f version] [-r registry]\n\n' "$0"
	printf 'Options:\n'
	printf '  -c cpu        CPU type: amd64 or arm64\n'
	printf '                (Default: amd64)\n'
	printf '  -f version    FreeBSD version: 15.0, 14.3\n'
	printf '                (Default: 15.0)\n'
	printf '  -h            Help: display this usage message\n'
	printf '  -l            Tag the image as latest\n'
	printf '  -r registry   Registry path: terminated with /\n'
	printf '                (Default: none)\n'
	exit 1
}

# Get options
while getopts "c:f:hlr:" opt; do
	case "$opt" in
		c)
			cpu=${OPTARG}
			;;
		f)
			version=${OPTARG}
			;;
		l)
			latest=1
			;;
		r)
			registry=${OPTARG}
			;;
		h|?)
			usage
			;;
	esac
done

# Debug output
set -ex

# Defaults
if [ -z "$cpu" ]; then
	cpu="amd64" # TODO arm64
fi
if [ -z "$version" ]; then
	version="15.0"
fi
if [ -z "$latest" ]; then
	latest=0
fi

# Error checking
if [ "$cpu" != "amd64" ] && [ "$cpu" != "arm64" ]; then
	err "Invalid CPU type"
fi

# Download FreeBSD base
# XXX multi-arch
tmp_dir=$(mktemp -d /tmp/base.XXXXXXX)
check_downloader
arch="$(get_arch "$cpu")"
full_version="$(get_full_version "$version")"
base_url=$(get_base_url "$version")
$DOWNLOAD "https://download.freebsd.org/${base_url}/${cpu}/${arch}/${full_version}/base.txz" > "${tmp_dir}/base.txz"

# Build the container from scratch
oci_container_id=$(buildah from scratch)
if [ -z "$oci_container_id" ]; then
	err "Invalid OCI container ID"
fi

# Mount the container
base_root=$(buildah mount "$oci_container_id")
if [ -z "$base_root" ]; then
	err "Unable to mount the OCI container"
fi

# Untar base to the mounted container
# XXX can we --exclude the prune_base list?
tar -xvf "${tmp_dir}/base.txz" -C "$base_root"

# Prepare the container
cp -p "${base_root}/etc/termcap.small" "${base_root}/usr/share/misc/termcap"
prune_base "$base_root"

# Unmount and commit the container
buildah unmount "$oci_container_id" # XXX Trap cleanup
buildah config \
	--annotation "org.opencontainers.image.ref.name=freebsd" \
	--annotation "org.opencontainers.image.version=${version}" \
	--arch "$cpu" \
	--cmd "/bin/sh" \
	--os freebsd \
	"$oci_container_id"
# XXX current GH Actions Runner buildah version does not support:
# --identity-label=false --omit-history=true
# XXX Add --sign-by
buildah commit \
	--rm \
	"$oci_container_id" "${registry}freebsd-${cpu}:${version}"
# XXX Also tag with a more FreeBSD-esque name? 15.0-CURRENT, 14.3-RELEASE?
if [ "$latest" -eq 1 ]; then
	buildah tag "${registry}freebsd-${cpu}:${version}" "${registry}freebsd-${cpu}:latest"
fi

# Cleanup
rm -fr "$tmp_dir"
