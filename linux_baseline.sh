#!/usr/bin/env bash
set -euo pipefail

# ----------------------------
# Config
# ----------------------------
SCRIPT_NAME="linux_baseline"
HOST="$(hostname)"
OS="linux"
TS="$(date -Iseconds)"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="./logs"
LOG_FILE="${LOG_DIR}/kali_baseline_${RUN_ID}.jsonl"

mkdir -p "$LOG_DIR"

# ----------------------------
# Helpers
# ----------------------------
json_escape() {
  # Minimal JSON-escaping for quotes and backslashes
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/ }"
  echo "$s"
}

log_jsonl() {
  local check="$1" status="$2" details="$3"
  details="$(json_escape "$details")"
  echo "{\"timestamp\":\"${TS}\",\"host\":\"${HOST}\",\"os\":\"${OS}\",\"script\":\"${SCRIPT_NAME}\",\"check\":\"${check}\",\"status\":\"${status}\",\"details\":\"${details}\"}" \
    | tee -a "$LOG_FILE" >/dev/null
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_jsonl "prereq_${cmd}" "FAIL" "Kommandot '${cmd}' saknas. Installera/aktivera det och kör igen."
    exit 2
  fi
}

# ----------------------------
# Check 1: APT updates available?
# ----------------------------
check_apt_updates() {
  require_cmd apt-get

  # apt-get -s upgrade simulerar uppgradering utan att ändra systemet.
  # Vi räknar rader som börjar med "Inst " (paket som skulle installeras/uppgraderas).
  local count
  set +e
  count="$(apt-get -s upgrade 2>/dev/null | awk '/^Inst /{c++} END{print c+0}')"
  local rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    log_jsonl "apt_updates" "FAIL" "Kunde inte simulera 'apt-get -s upgrade'. Kör ev. som root eller kontrollera APT-konfiguration."
    return 2
  fi

  if [[ "$count" -gt 0 ]]; then
    log_jsonl "apt_updates" "WARN" "${count} uppdateringar är tillgängliga (patchnivå ej aktuell)."
    return 1
  else
    log_jsonl "apt_updates" "OK" "Inga uppdateringar tillgängliga enligt 'apt-get -s upgrade'."
    return 0
  fi
}

# ----------------------------
# Check 2: SSH PermitRootLogin
# ----------------------------
check_ssh_permit_root_login() {
  local cfg="/etc/ssh/sshd_config"

  if [[ ! -f "$cfg" ]]; then
    log_jsonl "ssh_permitrootlogin" "WARN" "Filen ${cfg} hittades inte. SSH kan vara ej installerat/aktiverat."
    return 1
  fi

  # Hämta sista matchande (icke-kommenterade) raden för PermitRootLogin om den finns.
  local line value
  line="$(grep -iE '^[[:space:]]*PermitRootLogin[[:space:]]+' "$cfg" | tail -n 1 || true)"
  value="$(echo "$line" | awk '{print $2}' | tr '[:upper:]' '[:lower:]' || true)"

  if [[ -z "$line" || -z "$value" ]]; then
    # Vi gör det enkelt: saknas => WARN (ni kan motivera som "oklart läge / bör verifieras").
    log_jsonl "ssh_permitrootlogin" "WARN" "PermitRootLogin saknas i ${cfg}. Rekommendation: sätt 'PermitRootLogin no'."
    return 1
  fi

  if [[ "$value" == "no" ]]; then
    log_jsonl "ssh_permitrootlogin" "OK" "PermitRootLogin är 'no' (root-inloggning via SSH är avstängd)."
    return 0
  fi

  if [[ "$value" == "yes" ]]; then
    log_jsonl "ssh_permitrootlogin" "FAIL" "PermitRootLogin är 'yes' (root-inloggning via SSH är tillåten)."
    return 2
  fi

  # Exempel på andra värden: prohibit-password, without-password, forced-commands-only
  log_jsonl "ssh_permitrootlogin" "WARN" "PermitRootLogin är '${value}'. Verifiera att policyn motsvarar önskad härdning."
  return 1
}

# ----------------------------
# Main
# ----------------------------
main() {
  log_jsonl "run_start" "OK" "Startar kontroller. Loggfil: ${LOG_FILE}"

  local exit_code=0

  check_apt_updates || exit_code=$(( exit_code < $? ? $? : exit_code ))
  check_ssh_permit_root_login || exit_code=$(( exit_code < $? ? $? : exit_code ))

  if [[ $exit_code -eq 0 ]]; then
    log_jsonl "run_summary" "OK" "Alla kontroller OK."
  elif [[ $exit_code -eq 1 ]]; then
    log_jsonl "run_summary" "WARN" "Minst en kontroll gav WARN."
  else
    log_jsonl "run_summary" "FAIL" "Minst en kontroll gav FAIL eller tekniskt fel."
  fi

  echo "Klart. Logg: ${LOG_FILE}"
  exit "$exit_code"
}

main "$@"
