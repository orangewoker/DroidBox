#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/android-runtime"
DIST="$ROOT/dist/android-runtime"
VERSION="9.0-r2-droidbox.1"
ISO_NAME="android-x86_64-9.0-r2.iso"
ISO_URL="https://downloads.sourceforge.net/project/android-x86/Release%209.0/$ISO_NAME"
ISO_SHA1="1cc85b5ed7c830ff71aecf8405c7281a9c995aa0"
ASSET="DroidBox-Android-x86_64-$VERSION-runtime.zip"

rm -rf "$WORK" "$DIST"
mkdir -p "$WORK/iso" "$WORK/root/android/data" "$WORK/package" "$DIST"
curl -fL --retry 8 --retry-delay 5 "$ISO_URL" -o "$WORK/$ISO_NAME"
echo "$ISO_SHA1  $WORK/$ISO_NAME" | sha1sum -c -

7z x -y "$WORK/$ISO_NAME" \
  -o"$WORK/iso" kernel initrd.img ramdisk.img system.sfs >/dev/null
for file in kernel initrd.img ramdisk.img system.sfs; do
  test -f "$WORK/iso/$file"
done

cp "$WORK/iso/ramdisk.img" "$WORK/root/android/"
cp "$WORK/iso/system.sfs" "$WORK/root/android/"
truncate -s 16G "$WORK/system.raw"
mkfs.ext4 -F -L DroidBoxAndroid -d "$WORK/root" "$WORK/system.raw" >/dev/null
qemu-img convert -p -f raw -O qcow2 -c "$WORK/system.raw" "$WORK/package/system.qcow2"
cp "$WORK/iso/kernel" "$WORK/package/kernel"
cp "$WORK/iso/initrd.img" "$WORK/package/initrd.img"

IMAGE_SHA="$(sha256sum "$WORK/package/system.qcow2" | awk '{print $1}')"
IMAGE_SIZE="$(stat -c %s "$WORK/package/system.qcow2")"
cat > "$WORK/package/runtime.json" <<EOF
{
  "id": "android-x86_64-pie",
  "version": "$VERSION",
  "architecture": "x86_64",
  "downloadURL": "https://github.com/orangewoker/DroidBox/releases/download/android-runtime-v1/$ASSET",
  "sha256": "$IMAGE_SHA",
  "size": $IMAGE_SIZE,
  "license": "Apache-2.0 AND GPL-2.0-or-later",
  "minimumAppVersion": "1.3.0",
  "qemuArguments": [
    "-L", "{qemu}",
    "-machine", "q35",
    "-accel", "tcg,tb-size=128",
    "-cpu", "max",
    "-smp", "2",
    "-m", "{memoryMB}",
    "-kernel", "{runtime}/kernel",
    "-initrd", "{runtime}/initrd.img",
    "-append", "root=/dev/ram0 androidboot.selinux=permissive SRC=/android DATA=/android/data quiet nomodeset vga=788",
    "-drive", "file={overlay},if=none,id=system,format=qcow2,cache=unsafe",
    "-device", "virtio-blk-pci,drive=system",
    "-vga", "std",
    "-device", "qemu-xhci,id=usb",
    "-device", "usb-tablet,bus=usb.0",
    "-device", "usb-kbd,bus=usb.0",
    "-netdev", "user,id=net0,hostfwd=tcp:127.0.0.1:{adbPort}-:5555",
    "-device", "virtio-net-pci,netdev=net0",
    "-qmp", "tcp:127.0.0.1:{qmpPort},server=on,wait=off",
    "-vnc", "127.0.0.1:{vncDisplay}",
    "-no-reboot"
  ]
}
EOF

(cd "$WORK/package" && zip -9 -qry "$DIST/$ASSET" .)
(cd "$DIST" && sha256sum "$ASSET" > "$ASSET.sha256")
python3 - "$DIST/$ASSET" <<'PY'
import json, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    names = set(archive.namelist())
    assert {"runtime.json", "system.qcow2", "kernel", "initrd.img"} <= names
    manifest = json.loads(archive.read("runtime.json"))
    assert manifest["architecture"] == "x86_64"
print("Android Runtime ZIP verified.")
PY
