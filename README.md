# Ansible Playbook for CPU Configuration

This playbook automates the configuration of:
1. **Dependencies Installation** - Installs libbpf-tools, bpftrace, trace-cmd, and sysjitter
2. **Kernel Boot Arguments** - Configures kernel boot parameters via `grubby`
3. **Sysctl Configuration** - Applies and persists sysctl settings
4. **Housekeeping Scripts** - Deploys CPU housekeeping scripts
5. **Systemd Service** - Creates and enables pin-housekeeping service

## Prerequisites

- Ansible installed on the control node
- Target hosts must have:
  - `grubby` package (for RHEL/CentOS/Amazon Linux)
  - Root/sudo access

## Role Structure

The playbook is organized into reusable roles:

- **install-dependencies** - Installs required packages and builds sysjitter
- **configure-housekeeping** - Configures kernel boot args, sysctl, scripts, and service

## Configuration via Group Variables

Configuration is managed through **group variables** located in `group_vars/`:

- `group_vars/all.yml` - Default settings for all hosts
- `group_vars/local.yml` - Settings for local/test hosts (optional override)
- `group_vars/remote.yml` - Settings for remote/production hosts (optional override)

### Role Enable/Disable Flags

You can control which roles and components are applied using boolean flags:

```yaml
# Enable/disable entire roles
install_dependencies_enabled: true      # Install libbpf-tools, bpftrace, trace-cmd, sysjitter
configure_housekeeping_enabled: true    # Configure kernel, sysctl, scripts, service

# Fine-grained control for configure-housekeeping role components
configure_housekeeping_kernel_boot_args: true   # Apply kernel boot arguments
configure_housekeeping_sysctl: true             # Apply sysctl settings
configure_housekeeping_scripts: true            # Deploy housekeeping scripts
configure_housekeeping_service: true            # Deploy and enable systemd service
```

### Example: Disable Kernel Boot Args for Testing

Edit `group_vars/local.yml`:

```yaml
# Disable kernel boot args modification to avoid reboot requirement
configure_housekeeping_kernel_boot_args: false
configure_housekeeping_sysctl: true
configure_housekeeping_scripts: true
configure_housekeeping_service: true
```

### Example: Install Dependencies Only

Edit `group_vars/all.yml`:

```yaml
install_dependencies_enabled: true
configure_housekeeping_enabled: false
```

## Usage

### Basic Usage

```bash
# Run against localhost with inventory file
ansible-playbook -i inventory.example configure-housekeeping.yml

# Run against localhost directly
ansible-playbook -i localhost, -c local configure-housekeeping.yml

# Run against remote hosts
ansible-playbook -i inventory.example configure-housekeeping.yml --limit remote
```

### With Custom Variables via Command Line

```bash
# Override housekeeping CPUs
ansible-playbook -i localhost, -c local configure-housekeeping.yml \
  -e "hk_cpus=0,1,12,13"

# Disable a role
ansible-playbook -i localhost, -c local configure-housekeeping.yml \
  -e "configure_housekeeping_enabled=false"

# Disable kernel boot args configuration
ansible-playbook -i localhost, -c local configure-housekeeping.yml \
  -e "configure_housekeeping_kernel_boot_args=false"

# Override sysctl settings
ansible-playbook -i localhost, -c local configure-housekeeping.yml \
  -e '{"sysctl_settings": {"kernel.sched_rt_runtime_us": "-1", "vm.swappiness": "1"}}'
```

### Inventory File Example

Create `inventory.ini`:

```ini
[local]
localhost ansible_connection=local

[remote]
host1 ansible_host=192.168.1.10 ansible_user=ec2-user
host2 ansible_host=192.168.1.11 ansible_user=ec2-user
```

Then create corresponding `group_vars/local.yml` and `group_vars/remote.yml` files with group-specific settings.

## What It Does

### 1. Install Dependencies Role

- Installs packages: `libbpf-tools`, `bpftrace`, `trace-cmd`, `grubby`
- Builds and installs `sysjitter` from source to `/usr/local/bin/sysjitter`
- Makes binaries available system-wide

### 2. Configure Housekeeping Role

**Kernel Boot Arguments** (if enabled):
- Captures current boot arguments from `/proc/cmdline`
- Applies them using `grubby --update-kernel=ALL`
- Changes take effect after reboot

**Sysctl Configuration** (if enabled):
- Applies sysctl settings immediately
- Persists settings to `/etc/sysctl.d/99-housekeeping.conf`

**Scripts Deployment** (if enabled):
- Deploys `pin_housekeeping.sh` to `/usr/local/sbin/`
- Deploys `set_irq_affinity.sh` to `/usr/local/sbin/`
- Deploys `trace_jitter.sh` to `/usr/local/bin/`

**Systemd Service** (if enabled):
- Deploys `pin-housekeeping.service` to `/etc/systemd/system/`
- Enables and starts the service

## Configuration Variables

All variables are defined in `group_vars/all.yml` with defaults. You can override them in group-specific files or via `-e` flags.

### Role Control Variables

- `install_dependencies_enabled`: Enable/disable dependency installation (default: `true`)
- `configure_housekeeping_enabled`: Enable/disable housekeeping configuration (default: `true`)
- `configure_housekeeping_kernel_boot_args`: Enable/disable kernel boot args (default: `true`)
- `configure_housekeeping_sysctl`: Enable/disable sysctl configuration (default: `true`)
- `configure_housekeeping_scripts`: Enable/disable script deployment (default: `true`)
- `configure_housekeeping_service`: Enable/disable systemd service (default: `true`)

### Housekeeping Configuration Variables

- `hk_cpus`: Housekeeping CPUs (default: `"0,1,12,13"`)
- `kernel_boot_args`: Override boot arguments (default: captured from target or uses `default_boot_params`)
- `default_boot_params`: Default kernel boot parameters string
- `sysctl_settings`: Custom sysctl settings dictionary (default: uses `default_sysctl_settings`)
- `default_sysctl_settings`: Default sysctl settings dictionary
- `isolated_cpu_start`: Start of isolated CPU range for trace_jitter.sh (default: `2`)
- `isolated_cpu_end`: End of isolated CPU range for trace_jitter.sh (default: `7`)

### Path Variables

- `pin_housekeeping_script_path`: Path for pin_housekeeping.sh (default: `/usr/local/sbin/pin_housekeeping.sh`)
- `set_irq_affinity_script_path`: Path for set_irq_affinity.sh (default: `/usr/local/sbin/set_irq_affinity.sh`)
- `trace_jitter_script_path`: Path for trace_jitter.sh (default: `/usr/local/bin/trace_jitter.sh`)
- `systemd_service_path`: Path for systemd service (default: `/etc/systemd/system/pin-housekeeping.service`)

## Examples

### Example 1: Test Environment (No Kernel Changes)

Create `group_vars/test.yml`:

```yaml
install_dependencies_enabled: true
configure_housekeeping_enabled: true
configure_housekeeping_kernel_boot_args: false  # Skip kernel changes
configure_housekeeping_sysctl: true
configure_housekeeping_scripts: true
configure_housekeeping_service: true
```

### Example 2: Dependencies Only

```yaml
install_dependencies_enabled: true
configure_housekeeping_enabled: false
```

### Example 3: Full Production Configuration

```yaml
install_dependencies_enabled: true
configure_housekeeping_enabled: true
configure_housekeeping_kernel_boot_args: true
configure_housekeeping_sysctl: true
configure_housekeeping_scripts: true
configure_housekeeping_service: true

# Custom settings
hk_cpus: "0,1,12,13"
sysctl_settings:
  kernel.numa_balancing: 0
  kernel.sched_rt_runtime_us: -1
  vm.swappiness: 1
```

## Notes

- Boot argument changes require a reboot to take effect
- Sysctl settings are applied immediately and persisted
- The service is enabled to start on boot
- All roles are idempotent - safe to run multiple times
- Group variables allow different configurations for different host groups
- Variables can be overridden via command-line `-e` flags (highest priority)

## Directory Structure

```
cpu-configuration/
├── configure-housekeeping.yml    # Main playbook
├── inventory.example              # Example inventory file
├── group_vars/                   # Group variables
│   ├── all.yml                  # Default settings for all hosts
│   ├── local.yml                # Local host overrides
│   └── remote.yml               # Remote host overrides
├── roles/
│   ├── install-dependencies/
│   │   └── tasks/main.yml
│   └── configure-housekeeping/
│       ├── defaults/main.yml
│       ├── handlers/main.yml
│       ├── tasks/main.yml
│       └── templates/
└── README.md
```