#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if find "$root" -path "$root/.git" -prune -o -type l -print -quit | read -r link; then
  printf 'error: symbolic link found: %s\n' "$link" >&2
  exit 1
fi

while IFS= read -r -d '' file; do
  rel=${file#"$root"/}
  case "$rel" in
    LICENSE|README.md|SHA256SUMS|audit/FUNCTIONAL-VERIFICATION.txt|audit/KNOWN-INPUTS.sha256|audit/STAGING-AUDIT.txt|audit/audit-stage.sh|kernels/boost/bzImage|kernels/boost/config|kernels/vanilla/bzImage|kernels/vanilla/config|scripts/run-boost-functional.sh|scripts/run-vanilla-functional.sh|scripts/verify-evaluation-config.sh|tests/zswap-boost-functional-init.c|tests/zswap-vanilla-functional-init.c)
      ;;
    *)
      printf 'error: unexpected file: %s\n' "$rel" >&2
      exit 1
      ;;
  esac
done < <(find "$root" -path "$root/.git" -prune -o -type f -print0)

"$root/scripts/verify-evaluation-config.sh" "$root/kernels/boost/config"
"$root/scripts/verify-evaluation-config.sh" "$root/kernels/vanilla/config"

if command -v shasum >/dev/null; then
  checksum=(shasum -a 256)
else
  checksum=(sha256sum)
fi
(
  cd "$root"
  "${checksum[@]}" -c audit/KNOWN-INPUTS.sha256
  "${checksum[@]}" -c SHA256SUMS
)
printf 'private binary staging audit passed\n'
