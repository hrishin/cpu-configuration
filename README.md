# Ansible Playbook for AMD EPYC 9005 Low-Latency CPU Configuration

Implements the OS-side tuning from AMD's **"Low Latency Tuning for AMD EPYC 9005 CPU
Powered Servers"** (publication 73314, rev 1.0, Sept 2026) as Ansible roles. The guide
delivers its tuning as a **TuneD profile** (`amd-cpu-partitioning`); this repo templates
the profile files embedded in that PDF so the isolated-core list, sysctls and kernel
command line come from one set of variables.

The playbook automates:

1. **Dependencies** - `libbpf-tools`, `bpftrace`, `trace-cmd`, `perf`, `kernel-tools` (cpupower), `hwloc` (lstopo), and `sysjitter` built from source
2. **AMD tuned profile** (guide ch. 3) - deploys and activates `amd-cpu-partitioning`, which owns the kernel command line, sysctls, workqueue masks, irqbalance banned CPUs and systemd CPU affinity
3. **irqbalance oneshot** (guide 3.4) - irqbalance cleans cores once per boot then exits so manual IRQ steering sticks
4. **Optional extras** - Solarflare `sfcaffinity_config` hook (3.4), per-core `cpupower` frequency limits (2.4), L3 cache allocation via resctrl (2.6), network sysctls (3.5), `mitigations=off` / `selinux=0` (3.3)
5. **Legacy housekeeping** - `pin_housekeeping.sh`, `set_irq_affinity.sh`, `trace_jitter.sh` and the `pin-housekeeping` service (the pre-tuned grubby/sysctl.d path is still available but off by default)

## Prerequisites

- Ansible on the control node
- RHEL 9 (guide tested on 9.7) or compatible target with root/sudo
- **BIOS configured per guide section 6.1** - this cannot be automated; see [BIOS settings](#bios-settings-guide-61) below
- A reboot after the first run (kernel command line changes)

## Quick Start

```bash
# 1. Set your CPU layout (group_vars/all.yml): isolated_cores / hk_cpus
# 2. Apply
ansible-playbook -i inventory.example configure-housekeeping.yml --limit remote
# 3. Reboot (or set amd_reboot_after_apply: true)
# 4. Validate
ansible-playbook -i inventory.example verify-tuning.yml --limit remote -e sysjitter_runtime=60
```

## Role Structure

- **install-dependencies** - packages + sysjitter build
- **configure-amd-low-latency** - tuned profile, irqbalance, Solarflare, cpufreq, resctrl
  - `tasks/tuned.yml`, `irqbalance.yml`, `solarflare.yml`, `cpufreq.yml`, `resctrl.yml`
  - `templates/tuned.conf.j2`, `script.sh.j2`, `00-tuned-pre-udev.sh.j2`, `cpu-partitioning-variables.conf.j2` (from the PDF attachments)
- **configure-housekeeping** - legacy grubby boot args, sysctl.d, pin scripts and service

## Configuration via Group Variables

Configuration is managed through `group_vars/`:

- `group_vars/all.yml` - defaults for all hosts
- `group_vars/local.yml` - local/test hosts (tuned profile disabled to avoid bootloader changes)
- `group_vars/remote.yml` - production hosts

### CPU layout

```yaml
isolated_cores: "2-11,14-23"                # nohz_full / rcu_nocbs / isolcpus
no_balance_cores: "{{ isolated_cores }}"    # isolcpus=nohz,managed_irq,domain,<cores>; "" to skip
hk_cpus: "0,1,12,13"                        # housekeeping cores (legacy scripts, irqaffinity fallback)
```

Keep isolated cores within one CCD / NUMA node local to the NIC (guide 2.2, 2.6). Check
with `lstopo` or `cat /sys/class/net/<if>/device/numa_node` and
`lscpu -e=CPU,CORE,SOCKET,NODE,CACHE`.

### Role and component flags

```yaml
install_dependencies_enabled: true
configure_amd_low_latency_enabled: true
configure_housekeeping_enabled: true

amd_tuned_profile_enabled: true      # deploy + activate amd-cpu-partitioning
amd_irqbalance_oneshot: true         # IRQBALANCE_ARGS="--oneshot"
amd_reboot_after_apply: false        # reboot when the profile changed

# Legacy path - tuned owns these now, keep off unless amd_tuned_profile_enabled is false
configure_housekeeping_kernel_boot_args: false
configure_housekeeping_sysctl: false
configure_housekeeping_scripts: true
configure_housekeeping_service: true
```

### What the tuned profile applies

Kernel command line (guide 3.3):

```
nohz=on isolcpus=nohz,managed_irq,domain,<no_balance_cores> nohz_full=<isolated_cores>
rcu_nocbs=<isolated_cores> rcu_nocb_poll tuned.non_isolcpus=<mask> processor.max_cstate=0
amd_pstate=passive mce=ignore_ce nowatchdog nosoftlockup nmi_watchdog=0
transparent_hugepage=never pcie_aspm=off audit=0 amd_iommu=off iommu=off iomem=relaxed nomodeset
```

plus whatever the inherited `network-latency` profile adds (`skew_tick=1`, `tsc=reliable`, ...).

Sysctls: `vm.nr_hugepages=5000`, `kernel.hung_task_timeout_secs=600`, `kernel.numa_balancing=0`,
`kernel.timer_migration=1`, `kernel.sched_autogroup_enabled=0`, `vm.stat_interval=300`,
`vm.swappiness=0`, `vm.zone_reclaim_mode=0`, `vm.min_free_kbytes=1024000`.

Also: workqueue and writeback cpumasks, `machinecheck*/ignore_ce=1`, systemd `CPUAffinity`,
irqbalance banned CPUs, scheduler thread isolation, KSM disabled, dracut pre-udev hook.

### Optional tuning knobs

```yaml
# Security trade-offs (guide 3.3 note)
amd_tuned_cmdline_disable_mitigations: false   # mitigations=off
amd_tuned_cmdline_disable_selinux: false       # selinux=0
amd_tuned_cmdline_extra: []                    # anything else to append

# Sysctl overrides / network buffers (guide 3.5)
amd_tuned_sysctl_overrides: { vm.nr_hugepages: 2000 }
amd_tuned_network_sysctl_enabled: false        # rmem/wmem/backlog set; hashed out otherwise

# Solarflare X4 (guide 3.4 / ch. 4) - sfcaffinity_config called from the tuned script agent
amd_solarflare_affinity_enabled: true
amd_solarflare_affinity_cores: "40-41"
amd_solarflare_rss_cpus: "4"                   # options sfc rss_cpus=4

# amd_pstate=passive frequency steering (guide 2.4) via cpupower + amd-cpufreq.service
amd_cpufreq_profiles:
  - { cpus: "{{ hk_cpus }}", min: "2.4GHz", max: "3.3GHz" }
  - { cpus: "{{ isolated_cores }}", governor: "performance" }

# L3 Cache Allocation Technology (guide 2.6) via resctrl + amd-resctrl.service
amd_resctrl_groups:
  - { name: ccd0_cos0, schemata: "L3:0=00ff", cpus: "0-1" }
  - { name: ccd0_cos1, schemata: "L3:0=ff00", cpus: "2-7" }

# Extra commands run from the profile script.sh (guide 3.6)
amd_tuned_script_start_commands: []
```

Every variable is documented in `roles/configure-amd-low-latency/defaults/main.yml`.

## Usage

```bash
# Run against remote hosts
ansible-playbook -i inventory.example configure-housekeeping.yml --limit remote

# Run against localhost (bootloader changes skipped by group_vars/local.yml)
ansible-playbook -i localhost, -c local configure-housekeeping.yml

# Override the CPU layout
ansible-playbook -i inventory.example configure-housekeeping.yml \
  -e isolated_cores=32-47 -e hk_cpus=0-31

# Turn on mitigations=off and reboot automatically
ansible-playbook -i inventory.example configure-housekeeping.yml \
  -e amd_tuned_cmdline_disable_mitigations=true -e amd_reboot_after_apply=true

# Validate after reboot; run sysjitter for 60 s at a 300 ns threshold on the isolated cores
ansible-playbook -i inventory.example verify-tuning.yml -e sysjitter_runtime=60 -e sysjitter_threshold_ns=300
```

### Manual profile management on a host

```bash
tuned-adm profile                    # list profiles
tuned-adm active                     # current profile
tuned-adm profile amd-cpu-partitioning
tuned-adm verify
tuned-adm off                        # revert
cat /etc/tuned/bootcmdline           # what tuned added to the kernel cmdline
```

## Verification (guide ch. 5)

`verify-tuning.yml` reports the active profile, `tuned-adm verify`, `/proc/cmdline` with
any missing expected arguments, irqbalance settings, sysctls, the workqueue mask, the
threads still resident on isolated cores (`ps -eLo psr,...`), and optionally a sysjitter
run. Additional debug tools installed: `perf`, `trace-cmd`, `bpftrace`,
`/usr/local/bin/trace_jitter.sh` (bpftrace timer/irq/sched/rcu trace on isolated CPUs).

Examples from the guide:

```bash
# osnoise tracer on cores 42-47 for 60 s
cd /sys/kernel/tracing; echo 0 > tracing_on; echo osnoise > current_tracer
echo 42-47 > osnoise/cpus; echo 1000000 > osnoise/period_us; echo 1000000 > osnoise/runtime_us
echo > trace; echo 1 > tracing_on; sleep 60; echo 0 > tracing_on; cat trace

# scheduler activity on one core
perf record -C 42 -e sched:sched_switch,sched:sched_waking --call-graph dwarf -- sleep 300
```

## BIOS settings (guide 6.1)

Not automatable from the OS - set these in the platform BIOS before applying the profile:

| Setting | Value |
|---|---|
| SMT Control | Disabled |
| Global C-State Control | Enabled (DF C-states disabled; OS controls) |
| Core Performance Boost | Enabled |
| Prefetchers | Enabled |
| NUMA Per Socket (NPS) | 4 (test 1/2/4) |
| 4-Link xGMI Max Speed | 32 Gbps (2-socket) |
| SDCI | Enabled |
| Periodic Directory Rinse | Adaptive (Blended) |
| Determinism Control / Enable | Manual / Power |
| APBDIS | 1 |
| DF Pstate | 0 |
| Power Profile Selection | Max IO perf mode |
| DF Pstate FREQ optimizer | Disabled |
| DF Cstates | Disabled |
| GMI Folding | Disabled |
| CPPC | Enabled |
| PCIe Idle Power Setting | Optimize for latency |
| ASPM Control | Disabled |
| IOMMU | Disabled |
| Enable 2 SPC (Gen4/Gen5) | Enable |
| SRIOV | Disabled |
| Memory Speed | 5600 (1DPC) / 3600 (2DPC) if PPT disabled |
| PPT DDR5 training | Disable |

## Notes

- Kernel command line changes need a reboot; `tuned-adm verify` will report mismatches until then.
- `mitigations=off` and `selinux=0` are off by default - the guide flags them as security decisions.
- `vm.nr_hugepages=5000` (~10 GB of 2 MB pages) is the guide default for Onload; size it for your host via `amd_tuned_sysctl_overrides`.
- irqbalance in oneshot mode restarts (one pass) whenever the sysconfig line changes; tuned's `[irqbalance]` plugin writes the banned-CPU mask to the same file.
- **Cloud images:** Rocky/Alma/RHEL AMIs and GenericCloud images regenerate `/etc/machine-id` on first boot while their BLS entries keep the image-build prefix, so tuned's bootloader hook patches nothing and the kernel args silently never reach `/proc/cmdline`. The role re-runs `92-tuned.install` per actual entry prefix and fails loudly if `$tuned_params` is still missing; `verify-tuning.yml` reports missing args after reboot.
- The tuned profile directory is auto-detected (`/etc/tuned/profiles` on tuned >= 2.23, otherwise `/etc/tuned`); override with `amd_tuned_profiles_dir`.
- The legacy `configure-housekeeping` grubby path now carries the AMD argument set; do not enable it together with the tuned profile or you will get duplicate `isolcpus`/`nohz_full` entries.
- All roles are idempotent; the profile is only re-activated when a profile file changes or it is not the active profile.

## Directory Structure

```
cpu-configuration/
├── configure-housekeeping.yml     # Main playbook
├── verify-tuning.yml              # Post-reboot validation
├── inventory.example
├── group_vars/
│   ├── all.yml
│   ├── local.yml
│   └── remote.yml
├── roles/
│   ├── install-dependencies/
│   ├── configure-amd-low-latency/
│   │   ├── defaults/main.yml
│   │   ├── handlers/main.yml
│   │   ├── tasks/{main,tuned,irqbalance,solarflare,cpufreq,resctrl}.yml
│   │   └── templates/
│   └── configure-housekeeping/
└── Low Latency Tuning for AMD EPYC 9005 CPU Powered Servers.pdf
```
