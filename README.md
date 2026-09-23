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

The imported kernel hashes were verified in an isolated KVM Functional run on 2026-09-23 with LZ4/zbud; see `audit/FUNCTIONAL-VERIFICATION.txt`. Raw evidence remains private and outside this candidate.

## Requirements

- x86-64 Linux host with KVM access.
- QEMU, GCC, CPIO, gzip, `qemu-img`, `timeout`, and SHA-256 tooling.

## Verify inputs

```bash
shasum -a 256 -c audit/KNOWN-INPUTS.sha256
shasum -a 256 -c SHA256SUMS
# On hosts without shasum, use: sha256sum -c <manifest>
./audit/audit-stage.sh
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

## License and source access

The kernel binary content is accompanied by the GPL-2.0 license in `LICENSE`. Binary delivery for this AE deployment is authorized by the artifact authors. Source code is not included here; requesters needing source access may obtain it under a separately executed NDA.

## Support

Use the artifact evaluation channel for setup or Functional-validation questions. Do not include credentials, private host details, or raw logs in support requests.
