# AMD low-latency tuning — bare-metal benchmark, 2026-09-20

**Host:** AWS `c7a.metal-48xl` spot, us-east-1b (`i-0598402c957b4a6ff`), 2 × AMD EPYC 9R14
(Genoa, 96 physical cores each, SMT disabled by AWS), 384 GiB, Rocky Linux 9.8,
kernel 5.14.0-687.15.1.el9_8, tuned 2.27.0. No BIOS access (EC2), so guide §6.1 was not applied.

**Isolated cores:** 8–15 = one CCD (shared L3 id 8). **Profile:** `amd-cpu-partitioning`
(this repo's templated copy of the guide's tuned profile) + irqbalance `--oneshot`.

**Measurement:** `sysjitter --runtime 300 --cores 8-15 300` (300 ns threshold), per guide §3.7.

## Result

| per core | baseline | tuned (profile + kernel cmdline) |
|---|---|---|
| interruptions / s | ~1,000 (1 kHz tick) | 2–6 |
| mean interruption | 2.6–3.1 µs | 0.32–0.41 µs |
| p99 | 7.5–8.9 µs | 0.36–0.44 µs |
| max | 178–363 µs | 0.38–0.46 µs on cores 8,10,12,14,15; single events of 8.8 µs (core 9), 20.6 µs (13), 47.5 µs (11) |
| CPU time lost to interruptions | ~0.26 % | 0.000 % |
| threads resident on the cores | 88 (incl. `irq/AMD-Vi`, `irq/pciehp`, unbound kworkers) | 36 (only per-CPU kthreads: migration, ksoftirqd, idle_inject, cpuhp, 4 kworkers) |

Totals over the 8 cores, 5 minutes: **2,420,211 → 11,053 interruptions; worst max 363 µs → 47 µs.**

Files: `baseline/`, `tuned/` (sysjitter + context), `verify.txt`, `compare.txt`.

### Intermediate: runtime-only tuning (`tuned-runtime-only/`)
First reboot came up **without** the kernel args (see below). tuned's runtime plugins alone
(scheduler affinity, irqbalance ban, workqueue masks, sysctls) cut the worst max 363 → 54 µs but
left the 1 kHz tick: interruption count unchanged. The kernel cmdline (`nohz_full`, `isolcpus`,
`rcu_nocbs`, `processor.max_cstate=0`, …) is what removes the ~1,000/s.

## Findings that changed the code

1. **Cloud-image BLS / machine-id gap.** Rocky AMI BLS entries are named with the image-build
   machine-id; cloud-init regenerates `/etc/machine-id` on first boot. tuned's
   `92-tuned.install` hook only patches `$(cat /etc/machine-id)-*.conf`, so `$tuned_params`
   never reached the boot entry and `tuned-adm profile` reported success. The role now re-runs
   the hook per actual entry prefix and fails if `$tuned_params` is still missing.
2. Spot capacity for `c7a.metal-48xl` is AZ-dependent (placement score 1 in us-east-1f, 3 in
   a/b/c/d); the provider silently retries `InsufficientInstanceCapacity`. Added a 12-minute
   create timeout.
3. `delegate_to: localhost` runs from Ansible's temp dir — results paths are now absolute.

## Environment caveats
- The account's default VPC had a deleted IGW (blackhole default route) — restored manually
  during the run. SSH from the workstation was tunnelled through an EC2 Instance Connect Endpoint.
- Remaining single-event outliers (cores 9/11/13) are candidates for the guide's chapter 5
  osnoise/ftrace approach and for BIOS-level settings unavailable on EC2.
