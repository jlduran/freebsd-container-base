#!/bin/sh
set -ex

err() {
	echo "Error: $*" >&2
	exit 1
}

# TODO parse args
# - arch
# - freebsd_version
# - latest?

# Do we have buildah?
buildah --version > /dev/null || err "Please install buildah"

# TODO Do we have podman?
# TODO Choose a downloader (wget, curl, fetch, ftp, etc.)

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
curl https://download.freebsd.org/snapshots/arm64/aarch64/15.0-CURRENT/base.txz -o "${tmp_dir}/base.txz"
tar -xvf "${tmp_dir}/base.txz" -C "$base_root"
rm -fr "$tmp_dir"

# Use termcap.small
cp -p "${base_root}/etc/termcap.small" "${base_root}/usr/share/misc/termcap"

# XXX Remove stuff we don't need
rm -rf "${base_root}/etc/hosts"
rm -rf "${base_root}/rescue"
rm -rf "${base_root}/usr/share/docs"
rm -rf "${base_root}/usr/share/examples"
rm -rf "${base_root}/usr/share/man"
rm -rf "${base_root}/usr/share/openssl/man"
rm -rf "${base_root}/usr/tests"
rm -rf "${base_root}/var/db/etcupdate"

# Unmount and commit the container
buildah unmount "$oci_container_id"
buildah commit --rm "$oci_container_id" freebsd:15.0

# Tag and push the container to ghcr.io
# buildah push ...
