#!/usr/bin/env bash
# End-to-end benchmark of the AMD low-latency tuning on the terraform-provisioned host:
#
#   1. install   - tooling only (sysjitter, perf, bpftrace, ...), no tuning
#   2. baseline  - sysjitter on the to-be-isolated cores, untuned kernel
#   3. tune      - apply the amd-cpu-partitioning tuned profile + reboot
#   4. verify    - verify-tuning.yml
#   5. tuned     - sysjitter again, same cores / threshold / runtime
#   6. compare   - per-core baseline vs tuned table
#
# Usage:
#   test/run-benchmark.sh                # all phases
#   test/run-benchmark.sh --apply        # terraform apply first
#   test/run-benchmark.sh --from tuned   # resume at a phase (install|baseline|tune|verify|tuned|compare)
#   SYSJITTER_RUNTIME=3600 test/run-benchmark.sh   # 1 h runs (guide 3.7)
#
# Env: SYSJITTER_RUNTIME (s, default 300), SYSJITTER_THRESHOLD_NS (default 300),
#      RESULTS_DIR (default test/results/<UTC timestamp>), INVENTORY (default test/inventory/hosts.ini)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

INVENTORY="${INVENTORY:-test/inventory/hosts.ini}"
SYSJITTER_RUNTIME="${SYSJITTER_RUNTIME:-300}"
SYSJITTER_THRESHOLD_NS="${SYSJITTER_THRESHOLD_NS:-300}"
RESULTS_DIR="${RESULTS_DIR:-test/results/$(date -u +%Y%m%dT%H%M%SZ)}"
[[ "${RESULTS_DIR}" = /* ]] || RESULTS_DIR="${REPO_ROOT}/${RESULTS_DIR}"
APPLY=false
FROM=install

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=true ;;
    --from) FROM="$2"; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

PHASES=(install baseline tune verify tuned compare)
started=false
log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

run_phase() {
  local phase="$1"
  if [[ "${started}" == false ]]; then
    [[ "${phase}" == "${FROM}" ]] && started=true || return 0
  fi
  case "${phase}" in
    install)
      log "Phase 1/6: install tooling (no tuning)"
      ansible-playbook -i "${INVENTORY}" site.yml \
        -e amd_low_latency_enabled=false \
        -e housekeeping_enabled=false
      ;;
    baseline)
      log "Phase 2/6: baseline sysjitter (${SYSJITTER_RUNTIME}s @ ${SYSJITTER_THRESHOLD_NS}ns)"
      ansible-playbook -i "${INVENTORY}" test/benchmark.yml \
        -e phase=baseline -e sysjitter_runtime="${SYSJITTER_RUNTIME}" \
        -e sysjitter_threshold_ns="${SYSJITTER_THRESHOLD_NS}" -e results_dir="${RESULTS_DIR}"
      ;;
    tune)
      log "Phase 3/6: apply AMD tuned profile and reboot"
      ansible-playbook -i "${INVENTORY}" site.yml \
        -e install_dependencies_enabled=false -e amd_low_latency_reboot_after_apply=true
      ;;
    verify)
      log "Phase 4/6: verify tuning"
      ansible-playbook -i "${INVENTORY}" verify-tuning.yml | tee "${RESULTS_DIR}/verify.txt"
      ;;
    tuned)
      log "Phase 5/6: tuned sysjitter (${SYSJITTER_RUNTIME}s @ ${SYSJITTER_THRESHOLD_NS}ns)"
      ansible-playbook -i "${INVENTORY}" test/benchmark.yml \
        -e phase=tuned -e sysjitter_runtime="${SYSJITTER_RUNTIME}" \
        -e sysjitter_threshold_ns="${SYSJITTER_THRESHOLD_NS}" -e results_dir="${RESULTS_DIR}"
      ;;
    compare)
      log "Phase 6/6: compare"
      python3 test/sysjitter_compare.py \
        "${RESULTS_DIR}/baseline/sysjitter.txt" "${RESULTS_DIR}/tuned/sysjitter.txt" \
        | tee "${RESULTS_DIR}/compare.txt"
      ;;
  esac
}

if [[ "${APPLY}" == true ]]; then
  log "terraform apply (spot c7a.metal-48xl, Rocky 9)"
  terraform -chdir=test/terraform init -input=false
  terraform -chdir=test/terraform apply -auto-approve
fi

[[ -f "${INVENTORY}" ]] || { echo "inventory ${INVENTORY} not found; run with --apply or 'terraform -chdir=test/terraform apply'" >&2; exit 1; }
mkdir -p "${RESULTS_DIR}"
echo "results -> ${RESULTS_DIR}"

log "Waiting for SSH (metal instances take 10-15 min to boot)"
ansible -i "${INVENTORY}" all -m wait_for_connection -a "timeout=1500 sleep=15"

for p in "${PHASES[@]}"; do run_phase "$p"; done

log "Done. Results in ${RESULTS_DIR}"
echo "Remember: terraform -chdir=test/terraform destroy"
