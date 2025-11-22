# Ansible Playbook for CPU Configuration

This playbook automates the configuration of:
1. Kernel boot arguments via `grubby`
2. Sysctl configuration settings
3. Systemd service for pin-housekeeping

## Prerequisites

- Ansible installed on the control node
- Target hosts must have:
  - `grubby` package (for RHEL/CentOS/Amazon Linux)
  - Root/sudo access

## Usage

### Basic Usage

```bash
# Run against localhost
ansible-playbook -i localhost, -c local configure-housekeeping.yml

# Run against remote hosts
ansible-playbook -i inventory.ini configure-housekeeping.yml
```

### With Custom Variables

```bash
# Override housekeeping CPUs
ansible-playbook -i localhost, -c local configure-housekeeping.yml \
  -e "hk_cpus=0,1,12,13"

# Override sysctl settings
ansible-playbook -i localhost, -c local configure-housekeeping.yml \
  -e '{"sysctl_settings": {"kernel.sched_rt_runtime_us": "-1", "vm.swappiness": "1"}}'
```

### Inventory File Example

Create `inventory.ini`:
```ini
[targets]
host1 ansible_host=192.168.1.10
host2 ansible_host=192.168.1.11
```

## What It Does

1. **Kernel Boot Arguments**: 
   - Captures current boot arguments from `/proc/cmdline`
   - Applies them using `grubby --update-kernel=ALL`
   - Changes take effect after reboot

2. **Sysctl Configuration**:
   - Captures all current sysctl settings
   - Applies them to ensure persistence
   - Can override with custom settings via variables

3. **Systemd Service**:
   - Deploys `pin_housekeeping.sh` and `set_irq_affinity.sh` scripts
   - Creates and enables `pin-housekeeping.service`
   - Service runs after network.target

## Variables

- `hk_cpus`: Housekeeping CPUs (default: "0,1,12,13")
- `kernel_boot_args`: Override boot arguments (default: captured from target)
- `sysctl_settings`: Custom sysctl settings dictionary (default: captured from target)

## Notes

- Boot argument changes require a reboot to take effect
- Sysctl settings are applied immediately and persisted
- The service is enabled to start on boot

