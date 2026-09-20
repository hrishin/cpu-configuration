# Bare-metal benchmark harness

Spins up a **spot `c7a.metal-48xl`** (2 × AMD EPYC 9R14, 96c/192t, 384 GiB) on Rocky Linux 9,
measures jitter with sysjitter before and after applying the AMD tuned profile, and prints a
per-core comparison.

Cost: spot ~$2-4/hr depending on AZ (us-east-1f was cheapest at $1.96/hr when checked on 2026-09-20; pin with `-var availability_zone=us-east-1f`), ~$9.85/hr on-demand. A 5-minute-run cycle is ~45 min wall clock (metal boot ×2).
**Destroy the instance when done.**

## Prerequisites

- `terraform` ≥ 1.5, `aws` CLI with credentials for the target account, `ansible`
- An SSH key pair (default `~/.ssh/id_ed25519{,.pub}`; override with `-var ssh_public_key_path=...`)
- Default VPC in the region

## Run

```bash
cd test/terraform
terraform init
terraform apply                      # -var use_spot=false for on-demand; -var availability_zone=us-east-1c to pin
cd ../..
test/run-benchmark.sh                # or: test/run-benchmark.sh --apply  (does the apply for you)
SYSJITTER_RUNTIME=3600 test/run-benchmark.sh --from baseline   # 1 h runs per guide 3.7
terraform -chdir=test/terraform destroy
```

Phases: `install` → `baseline` → `tune` (profile + reboot) → `verify` → `tuned` → `compare`.
Resume any phase with `--from <phase>`. Results land in `test/results/<timestamp>/`:

```
baseline/context.txt   cmdline, tuned state, lscpu topology, threads on the isolated cores
baseline/sysjitter.txt
tuned/context.txt
tuned/sysjitter.txt
verify.txt
compare.txt            per-core int_n / mean / p99 / p99.99 / max, baseline vs tuned
```

## Host-specific settings

`test/inventory/group_vars/bench.yml` overrides the repo defaults for this box:
`isolated_cores: 8-15` (one CCD on socket 0), `nosmt` on the cmdline (no BIOS access on EC2 to
disable SMT), automatic reboot, legacy pin scripts off. Check `context.txt`'s `lscpu -e` output
and adjust `isolated_cores` if the cores don't share one L3.

## What you can and can't conclude

- Bare metal → real C-states, `amd_pstate`, IOMMU, PCIe ASPM and per-CCD L3, so the kernel-side
  tuning is exercised for real.
- No BIOS access → the guide's §6.1 settings (NPS, DF C-states, APBDIS, determinism) are not
  applied; expect residual jitter the guide's lab numbers don't show.
- EPYC 9R14 is Genoa (9004 / Zen 4), not Turin (9005 / Zen 5).
