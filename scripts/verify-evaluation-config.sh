#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: %s /path/to/kernel-config\n' "$0" >&2
  exit 2
fi

config=$1
test -f "$config"

has_line() {
  local expected=$1
  local line

  while IFS= read -r line; do
    [[ "$line" == "$expected" ]] && return 0
  done < "$config"
  return 1
}

for expected in CONFIG_ZSWAP=y CONFIG_ZBUD=y CONFIG_CRYPTO_LZ4=y CONFIG_LZ4_COMPRESS=y CONFIG_LZ4_DECOMPRESS=y; do
  has_line "$expected" || {
    printf 'missing required configuration: %s\n' "$expected" >&2
    exit 1
  }
done

printf 'evaluation LZ4 configuration prerequisites verified: %s\n' "$config"
