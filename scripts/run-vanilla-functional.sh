#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'usage: %s --kernel PATH --workdir NEW_PATH [--kernel-args ARGS]\n' "$0" >&2
  exit 2
}

kernel=
kernel_args=
workdir=

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kernel)
      kernel=${2:-}
      shift 2
      ;;
    --kernel-args)
      kernel_args=${2:-}
      shift 2
      ;;
    --workdir)
      workdir=${2:-}
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$kernel" && -n "$workdir" ]] || usage
[[ "$kernel_args" != *$'\n'* && "$kernel_args" != *$'\r'* ]] || usage
qemu=${QEMU:-qemu-system-x86_64}
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
init_source="$script_dir/../tests/zswap-vanilla-functional-init.c"

for command in "$qemu" qemu-img cpio gzip gcc ldd install timeout sha256sum tr; do
  command -v "$command" >/dev/null
done

test -r /dev/kvm
test -f "$kernel"
test -f "$init_source"
test ! -e "$workdir"

mkdir -p "$workdir"/{initramfs,logs}
initroot="$workdir/initramfs"
initrd="$workdir/zswap-vanilla-functional-initramfs.cpio.gz"
swapdisk="$workdir/zswap-vanilla-functional-swap.raw"
seriallog="$workdir/logs/serial.log"
qemulog="$workdir/logs/qemu.log"
result="$workdir/zswap-vanilla-functional-result.txt"

gcc -Os -s -Wall -Wextra -Werror -o "$initroot/init" "$init_source"
chmod 0755 "$initroot/init"
mkdir -p "$initroot"/{dev,proc,sys}

while IFS= read -r line; do
  library=
  case "$line" in
    *" => "/?*)
      library=${line#* => }
      library=${library%% *}
      ;;
    [[:space:]]/*)
      library=${line#?}
      library=${library%% *}
      ;;
    /*)
      library=${line%% *}
      ;;
  esac
  [[ -z "$library" ]] || install -D -m 0755 "$library" "$initroot$library"
done < <(LC_ALL=C ldd "$initroot/init")

(
  cd "$initroot"
  find . -print0 | cpio --null -o -H newc | gzip -9 > "$initrd"
)

qemu-img create -f raw "$swapdisk" 256M >/dev/null

timeout --signal=TERM --kill-after=10s 180s "$qemu" \
  -name zswap-atc26-vanilla-functional,process=zswap-atc26-vanilla-functional \
  -enable-kvm \
  -machine q35,accel=kvm \
  -cpu host \
  -smp 1 \
  -m 2G \
  -nodefaults \
  -no-reboot \
  -display none \
  -monitor none \
  -serial "file:$seriallog" \
  -kernel "$kernel" \
  -initrd "$initrd" \
  -append "console=ttyS0 rdinit=/init panic=-1 $kernel_args" \
  -drive "if=none,id=swap0,format=raw,file=$swapdisk,cache=writeback" \
  -device virtio-blk-pci,drive=swap0 \
  -net none \
  > "$qemulog" 2>&1

normalized_serial="$workdir/logs/serial.normalized.log"
tr -d '\r' < "$seriallog" > "$normalized_serial"

has_marker() {
  local marker=$1
  local line

  while IFS= read -r line; do
    [[ "$line" == "$marker" ]] && return 0
  done < "$normalized_serial"
  return 1
}

has_text() {
  local expected=$1
  local line

  while IFS= read -r line; do
    [[ "$line" == *"$expected"* ]] && return 0
  done < "$normalized_serial"
  return 1
}

read_delta() {
  local marker=$1
  local line
  local value

  while IFS= read -r line; do
    case "$line" in
      "$marker":[1-9]*)
        value=${line#"$marker:"}
        [[ "$value" =~ ^[1-9][0-9]*$ ]] || return 1
        printf '%s\n' "$value"
        return 0
        ;;
    esac
  done < "$normalized_serial"
  return 1
}

contains_failure() {
  local file=$1
  local line

  shopt -s nocasematch
  while IFS= read -r line; do
    case "$line" in
      *"kernel panic"*|*"oops:"*|*"bug:"*|*"call trace:"*)
        shopt -u nocasematch
        return 0
        ;;
    esac
  done < "$file"
  shopt -u nocasematch
  return 1
}

for marker in VANILLA_FUNCTIONAL:BOOTED VANILLA_FUNCTIONAL:ZSWAP_ENABLED VANILLA_FUNCTIONAL:DEBUGFS_READY VANILLA_FUNCTIONAL:SWAP_ENABLED VANILLA_FUNCTIONAL:PASS; do
  has_marker "$marker"
done
has_text 'zswap: loaded using pool lz4/zbud'
store_delta=$(read_delta VANILLA_FUNCTIONAL:STORE_DELTA)
load_delta=$(read_delta VANILLA_FUNCTIONAL:LOAD_DELTA)
data_pages=$(read_delta VANILLA_FUNCTIONAL:DATA_VERIFIED)
[[ "$store_delta" == 16384 && "$load_delta" == 16384 && "$data_pages" == 16384 ]]
if contains_failure "$normalized_serial" || contains_failure "$qemulog"; then
  printf 'error: kernel failure found in KVM logs\n' >&2
  exit 1
fi

kernel_hash=$(sha256sum "$kernel")
initrd_hash=$(sha256sum "$initrd")
swapdisk_hash=$(sha256sum "$swapdisk")
kernel_digest=${kernel_hash%% *}
initrd_digest=${initrd_hash%% *}
swapdisk_digest=${swapdisk_hash%% *}
{
  printf '%s  %s\n' "$kernel_digest" 'zswap-vanilla-functional-bzImage'
  printf '%s  %s\n' "$initrd_digest" 'zswap-vanilla-functional-initramfs.cpio.gz'
  printf '%s  %s\n' "$swapdisk_digest" 'zswap-vanilla-functional-swap.raw'
} > "$workdir/inputs.sha256"
{
  printf 'vanilla_functional_result=pass\n'
  printf 'guest_resources=1-vcpu,2-GiB\n'
  printf 'guest_network=none\n'
  printf 'kernel_args=%s\n' "$kernel_args"
  printf 'runtime_pool=lz4/zbud\n'
  printf 'timeout_seconds=180\n'
  printf 'swap_image=256-MiB-raw-virtio\n'
  printf 'zswap_sysfs=/sys/module/zswap/parameters/enabled\n'
  printf 'swap_device=virtio:/dev/vda\n'
  printf 'swap_size=262140-KiB\n'
  printf 'frontswap_store_counter=%s\n' "$store_delta"
  printf 'frontswap_load_counter=%s\n' "$load_delta"
  printf 'zswap_writeback_delta=0\n'
  printf 'data_integrity=all-16384-pages-verified\n'
  printf 'scope=single-core-vanilla-zswap-store-load-and-data-integrity-only\n'
  printf 'limitations=no-concurrency-fork-cow-oom-performance-production-or-iaa-claim\n'
  printf 'input_hashes:\n'
  printf '%s  %s\n' "$kernel_digest" 'zswap-vanilla-functional-bzImage'
  printf '%s  %s\n' "$initrd_digest" 'zswap-vanilla-functional-initramfs.cpio.gz'
  printf '%s  %s\n' "$swapdisk_digest" 'zswap-vanilla-functional-swap.raw'
} > "$result"
printf 'vanilla functional test passed; logs retained in %s\n' "$workdir/logs"
