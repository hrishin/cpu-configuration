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

- Ansible (ansible-core >= 2.15) on the control node and the `ansible.posix` collection:
  `ansible-galaxy collection install -r requirements.yml`
- RHEL 9 (guide tested on 9.7) or compatible target with root/sudo
- **BIOS configured per guide section 6.1** - this cannot be automated; see [BIOS settings](#bios-settings-guide-61) below
- A reboot after the first run (kernel command line changes)

## Quick Start

```bash
# 1. Set your CPU layout (group_vars/all.yml): isolated_cores / hk_cpus
# 2. Apply
ansible-playbook site.yml --limit remote
# 3. Reboot (or set amd_low_latency_reboot_after_apply: true)
# 4. Validate
ansible-playbook verify-tuning.yml --limit remote -e sysjitter_runtime=60
```

`ansible.cfg` points at `inventory.example`, `roles/` and `collections/`; pass `-i` to use
another inventory.

## Layout

```
cpu-configuration/
├── ansible.cfg
├── requirements.yml               # ansible.posix (sysctl module)
├── site.yml                       # apply: install_dependencies -> amd_low_latency -> housekeeping
├── verify-tuning.yml              # post-reboot validation
├── inventory.example
├── group_vars/
│   ├── all.yml                    # CPU layout + role switches (single source of truth)
│   ├── local.yml                  # [local]: no bootloader changes
│   └── remote.yml                 # [remote]: full tuned profile
├── roles/
│   ├── install_dependencies/      # packages + sysjitter build
│   ├── amd_low_latency/           # tuned profile, irqbalance, Solarflare, cpufreq, resctrl
│   │   ├── defaults/main.yml      # every knob, documented
│   │   ├── tasks/{main,tuned,irqbalance,solarflare,oneshot_service}.yml
│   │   └── templates/             # tuned.conf, script.sh, 00-tuned-pre-udev.sh, variables.conf (from the PDF)
│   └── housekeeping/              # legacy grubby/sysctl.d path, pin scripts and service
└── test/                          # bare-metal spot benchmark harness (see test/README.md)
```

Roles are imported by `site.yml` with tags (`dependencies`, `amd`/`tuned`, `housekeeping`)
so `--tags tuned` re-applies only the profile. Each role asserts it is running on an
Enterprise Linux host.

## Configuration

Variables are role-prefixed (`install_dependencies_*`, `amd_low_latency_*`, `housekeeping_*`)
and documented in each role's `defaults/main.yml`. `group_vars/all.yml` holds the values you
are expected to change and maps the shared CPU layout into both roles.

### CPU layout

```yaml
isolated_cores: "2-11,14-23"                # nohz_full / rcu_nocbs / isolcpus
no_balance_cores: "{{ isolated_cores }}"    # isolcpus=nohz,managed_irq,domain,<cores>; "" to skip
hk_cpus: "0,1,12,13"                        # housekeeping cores (pin scripts, irqaffinity fallback)
```

Keep isolated cores within one CCD / NUMA node local to the NIC (guide 2.2, 2.6). Check
with `lstopo` or `cat /sys/class/net/<if>/device/numa_node` and
`lscpu -e=CPU,CORE,SOCKET,NODE,CACHE`.

### Role and component flags

```yaml
install_dependencies_enabled: true
amd_low_latency_enabled: true
housekeeping_enabled: true

amd_low_latency_tuned_profile_enabled: true   # deploy + activate amd-cpu-partitioning
amd_low_latency_irqbalance_oneshot: true      # IRQBALANCE_ARGS="--oneshot"
amd_low_latency_reboot_after_apply: false     # reboot when the profile changed

# Legacy path - tuned owns these now, keep off unless amd_low_latency_tuned_profile_enabled is false
housekeeping_boot_args_enabled: false
housekeeping_sysctl_enabled: false
housekeeping_scripts_enabled: true
housekeeping_service_enabled: true
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

### Variable precedence

Ansible merges variables from many places; the later source wins. The layers this repo
uses, lowest to highest:

| # | Source | Where in this repo | Use it for |
|---|---|---|---|
| 1 | Role defaults | `roles/*/defaults/main.yml` | the documented default for every knob; roles stay usable standalone |
| 2 | Inventory `group_vars/all.yml` | (none) | |
| 3 | Playbook `group_vars/all.yml` | `group_vars/all.yml` | site-wide choices: CPU layout, role switches |
| 4 | Inventory `group_vars/<group>.yml` | `test/inventory/group_vars/bench.yml` | per-inventory overrides for a named group |
| 5 | Playbook `group_vars/<group>.yml` | `group_vars/local.yml`, `group_vars/remote.yml` | per-environment differences (bootloader on/off) |
| 6 | Inventory / playbook `host_vars/<host>.yml` | (none) | one-off host quirks |
| 7 | Host facts | `ansible_facts[...]` | read-only, gathered by `gather_facts` |
| 8 | Play `vars:` / `vars_files:` | `verify-tuning.yml`, `test/benchmark.yml` | playbook-local settings such as `sysjitter_runtime` |
| 9 | Role `vars/main.yml`, block and task `vars:` | `amd_low_latency` oneshot parameters | internal, not meant to be overridden |
| 10 | `set_fact` / `register` | `amd_low_latency_tuned_profile_path`, `housekeeping_missing_boot_args` | computed during the run |
| 11 | `include_role` / `include_tasks` params | `oneshot_service.yml` `vars:` | per-call parameters |
| 12 | Extra vars `-e` | command line | one-off overrides; always win |

Consequences worth knowing:

- Set your real configuration in `group_vars/`, not in the role defaults. Defaults exist so
  `ansible-lint` and standalone use have a value; editing them is a code change.
- The shared CPU layout (`isolated_cores`, `no_balance_cores`, `hk_cpus`) is mapped into
  role-prefixed variables in `group_vars/all.yml`. Overriding `isolated_cores` with `-e`
  works because the mapping is a Jinja reference that is resolved at use time; overriding
  `amd_low_latency_isolated_cores` directly is also fine and only affects that role.
- Both playbook-adjacent `group_vars/` (next to `site.yml`) and inventory-adjacent
  `group_vars/` (next to `hosts.ini`) are loaded. A named group always beats `all`, which
  is why `test/inventory/group_vars/bench.yml` overrides `group_vars/all.yml`; at the same
  group level the playbook-adjacent file beats the inventory-adjacent one. Between sibling
  groups the last one alphabetically wins, so avoid setting the same key in two groups a
  host belongs to.
- Role defaults that reference other variables (`amd_low_latency_no_balance_cores:
  "{{ amd_low_latency_isolated_cores }}"`) follow whatever value the referenced variable
  ends up with after precedence is applied, not the default next to it.
- `-e` values are strings unless you pass JSON (`-e '{"amd_low_latency_cpufreq_profiles": [...]}'`
  or `-e @file.json`). Flags used in `when: x | bool` tolerate `"true"`/`"false"` strings;
  lists and dicts do not.
- `include_tasks` `vars:` (the oneshot service parameters) sit above inventory and
  `group_vars`, so they cannot be overridden from outside the role by design; the
  values they pass through (`amd_low_latency_cpufreq_profiles`, ...) still come from
  your `group_vars`.

Full list: <https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html#understanding-variable-precedence>

### Optional tuning knobs

```yaml
# Security trade-offs (guide 3.3 note)
amd_low_latency_tuned_cmdline_disable_mitigations: false   # mitigations=off
amd_low_latency_tuned_cmdline_disable_selinux: false       # selinux=0
amd_low_latency_tuned_cmdline_extra: []                    # anything else to append

# Sysctl overrides / network buffers (guide 3.5)
amd_low_latency_tuned_sysctl_overrides: { vm.nr_hugepages: 2000 }
amd_low_latency_tuned_network_sysctl_enabled: false        # rmem/wmem/backlog set; hashed out otherwise

# Solarflare X4 (guide 3.4 / ch. 4) - sfcaffinity_config called from the tuned script agent
amd_low_latency_solarflare_affinity_enabled: true
amd_low_latency_solarflare_affinity_cores: "40-41"
amd_low_latency_solarflare_rss_cpus: "4"                   # options sfc rss_cpus=4

# amd_pstate=passive frequency steering (guide 2.4) via cpupower + amd-cpufreq.service
amd_low_latency_cpufreq_profiles:
  - { cpus: "{{ hk_cpus }}", min: "2.4GHz", max: "3.3GHz" }
  - { cpus: "{{ isolated_cores }}", governor: "performance" }

# L3 Cache Allocation Technology (guide 2.6) via resctrl + amd-resctrl.service
amd_low_latency_resctrl_groups:
  - { name: ccd0_cos0, schemata: "L3:0=00ff", cpus: "0-1" }
  - { name: ccd0_cos1, schemata: "L3:0=ff00", cpus: "2-7" }

# Extra commands run from the profile script.sh (guide 3.6)
amd_low_latency_tuned_script_start_commands: []
```

The cpufreq and resctrl helpers share one task file (`oneshot_service.yml`): an empty list
stops, disables and removes the corresponding unit and script.

## Usage

```bash
# Run against remote hosts
ansible-playbook site.yml --limit remote

# Run against localhost (bootloader changes skipped by group_vars/local.yml)
ansible-playbook -i localhost, -c local site.yml

# Override the CPU layout
ansible-playbook site.yml -e isolated_cores=32-47 -e hk_cpus=0-31

# Turn on mitigations=off and reboot automatically
ansible-playbook site.yml \
  -e amd_low_latency_tuned_cmdline_disable_mitigations=true -e amd_low_latency_reboot_after_apply=true

# Only re-apply the tuned profile
ansible-playbook site.yml --tags tuned

# Validate after reboot; run sysjitter for 60 s at a 300 ns threshold on the isolated cores
ansible-playbook verify-tuning.yml -e sysjitter_runtime=60 -e sysjitter_threshold_ns=300
```

### Linting

```bash
ansible-lint            # production profile, config in .ansible-lint
yamllint .              # config in .yamllint
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
`/usr/local/bin/trace_jitter.sh` (bpftrace timer/irq/sched/rcu trace, filtered to `isolated_cores`).

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
- `vm.nr_hugepages=5000` (~10 GB of 2 MB pages) is the guide default for Onload; size it for your host via `amd_low_latency_tuned_sysctl_overrides`.
- irqbalance in oneshot mode restarts (one pass) whenever the sysconfig line changes; tuned's `[irqbalance]` plugin writes the banned-CPU mask to the same file.
- **Cloud images:** Rocky/Alma/RHEL AMIs and GenericCloud images regenerate `/etc/machine-id` on first boot while their BLS entries keep the image-build prefix, so tuned's bootloader hook patches nothing and the kernel args silently never reach `/proc/cmdline`. The role re-runs `92-tuned.install` per actual entry prefix and fails loudly if `$tuned_params` is still missing; `verify-tuning.yml` reports missing args after reboot.
- The tuned profile directory is auto-detected (`/etc/tuned/profiles` on tuned >= 2.23, otherwise `/etc/tuned`); override with `amd_low_latency_tuned_profiles_dir`.
- The legacy `housekeeping` grubby path carries the same AMD argument set and only calls grubby when the default kernel is missing one; do not enable it together with the tuned profile or you will get duplicate `isolcpus`/`nohz_full` entries.
- All roles are idempotent; the profile is only re-activated when a profile file changes or it is not the active profile.
