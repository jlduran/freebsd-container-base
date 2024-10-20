#!/bin/sh
set -ex

# Use curl, fetch or wget to DOWNLOAD
CURL="curl -s"      # macOS
FETCH="fetch -qo -" # FreeBSD
WGET="wget -qO -"   # Linux (mostly)

err() {
	echo "Error: $*" >&2
	exit 1
}

# TODO parse args
# - arch
# - freebsd_version
# - latest?

# Check prerequisites
check_prerequisites()
{
	buildah --version > /dev/null || err "Please install buildah."
	podman --version > /dev/null || err "Please install podman."
	tar --version | grep bsdtar > /dev/null || err "Please install BSD tar."
}

# Download invocation
# $1: command
download_invocation()
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
			download_invocation $_cmd
			break
		fi
	done

	if [ -z "$DOWNLOAD" ]; then
		err "Please install curl or wget."
	fi
}


# XXX Remove stuff we don't need
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

# Build container from scratch
oci_container_id=$(buildah from scratch)
if [ -z "$oci_container_id" ]; then
	err "Invalid OCI container ID"
fi

# Mount the container
base_root=$(buildah mount "$oci_container_id")
if [ -z "$base_root" ]; then
	err "Unable to mount the OCI container"
fi

# Download FreeBSD base
# XXX multi-arch
tmp_dir=$(mktemp -d /tmp/base.XXXXXXX)
check_downloader
$DOWNLOAD https://download.freebsd.org/snapshots/arm64/aarch64/15.0-CURRENT/base.txz > "${tmp_dir}/base.txz"
tar -xvf "${tmp_dir}/base.txz" -C "$base_root"
rm -fr "$tmp_dir"

# Use termcap.small
cp -p "${base_root}/etc/termcap.small" "${base_root}/usr/share/misc/termcap"

prune_base "$base_root"

# Unmount and commit the container
buildah unmount "$oci_container_id"
buildah commit --rm "$oci_container_id" freebsd:15.0
