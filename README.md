# Zswap Boost ATC'26 Artifact Evaluation

This repository provides an artifact evaluation package for Functional verification of Zswap Boost and vanilla zswap kernel binaries. It lets evaluators verify LZ4/zbud configuration and runtime selection, Boost compression/decompression counters, vanilla store/load and no-writeback behavior, swapoff cleanup, and 16,384-page data integrity with isolated KVM runners.

## Scope

The artifact demonstrates:

- Boost control enablement and compression/decompression counter progress;
- vanilla zswap store/load progress with no writeback and swapoff cleanup;
- runtime LZ4/zbud pool selection;
- 16,384-page data integrity for both kernel ABIs.

The tests do **not** establish performance, concurrency, fork/COW behavior, OOM resilience, production suitability, hardware offload behavior, or reproduction of paper results.

## Binary images

- `kernels/boost/bzImage` and its resolved configuration.
- `kernels/vanilla/bzImage` and its resolved configuration.
- KVM Functional test harnesses for the Boost and vanilla kernel ABIs.

The kernel hashes were verified in an isolated KVM Functional run on 2026-09-23 with LZ4/zbud; see `FUNCTIONAL-VERIFICATION.txt`.

## Archived release

- Version: `1.0.0`
- Zenodo DOI: `10.5281/zenodo.23221535`
- Executable-artifact baseline: Git commit `73804baa929740759c987fda75f17fa3ecbaf7c8`

The Zenodo archive preserves the exact kernel binaries, resolved configurations, KVM runners, tests, and verification evidence evaluated for the ATC '26 Available and Functional badges.

## Requirements

- x86-64 Linux host with KVM access.
- QEMU, GCC, CPIO, gzip, `qemu-img`, `timeout`, and SHA-256 tooling.

## Verify inputs

```bash
shasum -a 256 -c SHA256SUMS
# On hosts without shasum, use: sha256sum -c SHA256SUMS
./scripts/verify-evaluation-config.sh kernels/boost/config
./scripts/verify-evaluation-config.sh kernels/vanilla/config
```

## Functional validation

Use a new work directory for each run:

```bash
./scripts/run-boost-functional.sh \
  --kernel kernels/boost/bzImage \
  --workdir /new/workdir/boost \
  --kernel-args 'zswap.compressor=lz4 zswap.zpool=zbud'

./scripts/run-vanilla-functional.sh \
  --kernel kernels/vanilla/bzImage \
  --workdir /new/workdir/vanilla \
  --kernel-args 'zswap.compressor=lz4 zswap.zpool=zbud'
```

Each runner uses one vCPU, 2 GiB guest memory, no guest network, a new 256 MiB virtio swap device, and a 180-second timeout. The Boost test checks its control and store/load counters and 16,384-page data integrity. The vanilla test checks store/load, no writeback, swapoff cleanup, and 16,384-page data integrity.

## License and package boundary

The kernel binary content is accompanied by the GPL-2.0 license in `LICENSE`. The only source-form files in this package are the public Functional test harnesses; the Zswap Boost kernel implementation is provided only in the compiled kernel binary, with no kernel source code or patch included.

## Support

Use the artifact evaluation channel for setup or Functional-validation questions.
