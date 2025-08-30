#!/usr/bin/env bash
# Nova Versus Miner - Ultimate Advanced Automated Verus Mining Suite
# Author: MrNova420
# Version: 5.0.0-nova

set -euo pipefail
IFS=$'\n\t'

# === Colors & UI ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'
BOX_TOP="┌─────────────────────────────────────────────────────────────┐"
BOX_BOT="└─────────────────────────────────────────────────────────────┘"

banner() {
  clear
  echo -e "${GREEN}$BOX_TOP"
  echo -e "│     ${BOLD}Nova Versus Miner Suite v5.0${NC}${GREEN}            │"
  echo -e "│  The Most Advanced Automated Verus Miner (All-in-One)      │"
  echo -e "│      ${YELLOW}by MrNova420${GREEN}                                  │"
  echo -e "$BOX_BOT${NC}"
}

cEcho() { local c=$1; shift; echo -e "${c}$*${NC}"; }
pause() { read -rp "Press Enter to continue..."; }

# === Paths & Config ===
HOME_DIR="${HOME:-/root}"
CONFIG_DIR="$HOME_DIR/.nova_verus_data"
LOG_DIR="$CONFIG_DIR/logs"
BIN_DIR="$CONFIG_DIR/miner_bin"
DASH_DIR="$CONFIG_DIR/dashboard"
MODULES_DIR="$CONFIG_DIR/modules"
CONFIG_FILE="$CONFIG_DIR/config.conf"
RUN_INFO_FILE="$CONFIG_DIR/run.info"
MINER_LOG="$LOG_DIR/miner.log"
WATCHDOG_LOG="$LOG_DIR/watchdog.log"
MINER_PID_FILE="$CONFIG_DIR/miner.pid"
WATCHDOG_PID_FILE="$CONFIG_DIR/watchdog.pid"
ACTIVE_MINER_FILE="$CONFIG_DIR/active_miner"
SCRIPT_VERSION="5.0.0-nova"
GITHUB_REPO="MrNova420/NovaVerusMiner"
DEFAULT_MINER_BIN_NAME="verus-miner"
MINER_LIST_FILE="$CONFIG_DIR/miners.list"

mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$BIN_DIR" "$DASH_DIR" "$MODULES_DIR"

# === Globals ===
WALLET=""
POOL=""
THREADS=0
MODE="balanced"
MINER_ARGS=""
BACKUP_POOLS=()
MINER_PID=0
WATCHDOG_PID=0
CPU_ARCH=""
ROOT_ACCESS=0
IS_TERMUX=0
ACTIVE_MINER="$DEFAULT_MINER_BIN_NAME"
MINERS=("verus-miner" "cpuminer" "xmrig")
SUGGESTED_POOLS=("na.luckpool.net:3956" "eu.luckpool.net:3956" "veruspool.com:13721" "vrsc.suprnova.cc:17777" "veruscoin.pro:3032")
BOOST_MODES=("Low Power" "Balanced" "Boosted" "Custom")

# === System Detection ===
detect_root() {
  if [ "$(id -u)" -eq 0 ] || command -v sudo >/dev/null 2>&1; then
    ROOT_ACCESS=1
  else
    ROOT_ACCESS=0
  fi
}
detect_cpu_arch() {
  local arch
  arch=$(uname -m 2>/dev/null || echo unknown)
  case "$arch" in
    aarch64|arm64) CPU_ARCH="arm64";;
    armv7l|armv7*) CPU_ARCH="armv7";;
    x86_64) CPU_ARCH="x86_64";;
    i686|i386) CPU_ARCH="x86";;
    *) CPU_ARCH="$arch";;
  esac
}
detect_termux() {
  if command -v termux-notification >/dev/null 2>&1 || [ -n "${PREFIX:-}" ] && echo "$PREFIX" | grep -q "com.termux"; then
    IS_TERMUX=1
  else
    IS_TERMUX=0
  fi
}
detect_environment() {
  detect_root
  detect_cpu_arch
  detect_termux
}

# === Dependencies Install ===
check_dependencies() {
  local deps=(curl jq git bc wget)
  local miss=0
  for dep in "${deps[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      cEcho $YELLOW "[!] Missing dependency: $dep"
      miss=1
    fi
  done
  if [ $miss -eq 1 ]; then
    if [ "$IS_TERMUX" -eq 1 ]; then
      cEcho $CYAN "[*] Installing missing packages with pkg..."
      pkg update -y || true
      pkg install -y "${deps[@]}"
    else
      cEcho $CYAN "[*] Installing missing packages with apt (needs sudo)..."
      if command -v sudo >/dev/null 2>&1; then
        sudo apt update -y
        sudo apt install -y "${deps[@]}"
      else
        cEcho $RED "[!] Install dependencies manually!"
        exit 1
      fi
    fi
  fi
  cEcho $GREEN "[✓] Dependencies OK."
}

# === Termux API ===
termux_api_warning="TERMUX API NOT AVAILABLE - limited notifications, battery/temp monitoring."
check_termux_api() {
  if [ "$IS_TERMUX" -eq 1 ] && ! command -v termux-notification >/dev/null 2>&1; then
    cEcho $YELLOW "[!] $termux_api_warning"
    return 1
  fi
  return 0
}
termux_storage_setup() {
  if [ "$IS_TERMUX" -eq 1 ] && command -v termux-setup-storage >/dev/null 2>&1; then
    termux-setup-storage || cEcho $YELLOW "[i] termux-setup-storage returned non-zero; ensure you grant permission in Android."
    cEcho $GREEN "[✓] Storage access requested."
  fi
}

# === Miner Binary Download/Management ===
miner_download_url_for_arch() {
  local miner="$1"
  local arch="$2"
  case "$miner" in
    verus-miner)
      case "$arch" in
        arm64) echo "https://github.com/$GITHUB_REPO/releases/latest/download/verus-miner-arm64";;
        armv7) echo "https://github.com/$GITHUB_REPO/releases/latest/download/verus-miner-armv7";;
        x86) echo "https://github.com/$GITHUB_REPO/releases/latest/download/verus-miner-x86";;
        x86_64) echo "https://github.com/$GITHUB_REPO/releases/latest/download/verus-miner-x86_64";;
        *) echo "";;
      esac
      ;;
    cpuminer)
      case "$arch" in
        arm64|x86_64|x86) echo "https://github.com/JayDDee/cpuminer-opt/releases/latest/download/cpuminer";;
        *) echo "";;
      esac
      ;;
    xmrig)
      case "$arch" in
        arm64) echo "https://github.com/xmrig/xmrig/releases/latest/download/xmrig-arm64";;
        x86_64) echo "https://github.com/xmrig/xmrig/releases/latest/download/xmrig-x86_64";;
        x86) echo "https://github.com/xmrig/xmrig/releases/latest/download/xmrig-x86";;
        *) echo "";;
      esac
      ;;
    *) echo "";;
  esac
}
download_miner_binary() {
  local miner="$1"
  local arch="$2"
  local url alt_url
  url="$(miner_download_url_for_arch "$miner" "$arch")"
  alt_url="https://github.com/$GITHUB_REPO/releases/latest/download/$miner-$arch"
  cEcho $CYAN "[*] Attempting to download $miner ($arch)..."
  if curl -fSL --retry 3 -o "$BIN_DIR/$miner" "$url"; then
    chmod +x "$BIN_DIR/$miner"
    cEcho $GREEN "[✓] Downloaded $miner using curl."
    return 0
  elif wget -O "$BIN_DIR/$miner" "$url"; then
    chmod +x "$BIN_DIR/$miner"
    cEcho $GREEN "[✓] Downloaded $miner using wget."
    return 0
  elif curl -fSL --retry 3 -o "$BIN_DIR/$miner" "$alt_url"; then
    chmod +x "$BIN_DIR/$miner"
    cEcho $GREEN "[✓] Downloaded $miner using alternate URL."
    return 0
  else
    cEcho $RED "[!] All download methods failed for $miner ($arch)."
    cEcho $YELLOW "Place $miner in $BIN_DIR manually, or check your internet."
    return 1
  fi
}
check_miner_binary() {
  local miner="$1"
  if [ -x "$BIN_DIR/$miner" ]; then
    cEcho $GREEN "[✓] $miner binary present: $BIN_DIR/$miner"
    return 0
  fi
  cEcho $YELLOW "[!] $miner binary not found. Downloading now..."
  download_miner_binary "$miner" "$CPU_ARCH" || return 1
}
list_miners() {
  [ -f "$MINER_LIST_FILE" ] && mapfile -t MINERS < "$MINER_LIST_FILE"
}
save_miners_list() {
  printf "%s\n" "${MINERS[@]}" > "$MINER_LIST_FILE"
}
set_active_miner() {
  echo "$1" > "$ACTIVE_MINER_FILE"
  ACTIVE_MINER="$1"
}
get_active_miner() {
  if [ -f "$ACTIVE_MINER_FILE" ]; then
    ACTIVE_MINER=$(cat "$ACTIVE_MINER_FILE")
  else
    set_active_miner "$DEFAULT_MINER_BIN_NAME"
  fi
}

# === Input Validation ===
validate_wallet() { [[ "${WALLET:-}" =~ ^R[a-zA-Z0-9]{33,35}$ ]]; }
validate_pool() { [[ "${POOL:-}" =~ ^[a-zA-Z0-9\.\-]+:[0-9]{1,5}$ ]]; }
validate_threads() {
  local max
  max=$(nproc 2>/dev/null || echo 2)
  [[ "$THREADS" =~ ^[0-9]+$ ]] && [ "$THREADS" -ge 1 ] && [ "$THREADS" -le "$max" ]
}

# === Config Load/Save ===
save_config() {
  cat > "$CONFIG_FILE" <<EOF
WALLET="${WALLET:-}"
POOL="${POOL:-}"
THREADS=${THREADS:-0}
MODE="${MODE:-balanced}"
MINER_ARGS="${MINER_ARGS:-}"
BACKUP_POOLS="${BACKUP_POOLS[*]}"
ACTIVE_MINER="${ACTIVE_MINER:-$DEFAULT_MINER_BIN_NAME}"
EOF
  cEcho $GREEN "[✓] Configuration saved to $CONFIG_FILE"
}

load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    IFS=' ' read -r -a BACKUP_POOLS <<< "${BACKUP_POOLS:-}"
    get_active_miner
  fi
}

# === Run Info ===
write_run_info() {
  local status="${1:-unknown}"
  local errcode="${2:-0}"
  local runtime=0
  if [ -f "$MINER_PID_FILE" ]; then
    local pid
    pid=$(cat "$MINER_PID_FILE" 2>/dev/null || echo "")
    if [ -n "$pid" ]; then
      runtime=$(ps -o etimes= -p "$pid" 2>/dev/null || echo 0)
    fi
  fi
  local cpu_model mem_total mem_free
  cpu_model=$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null || echo "unknown")
  mem_total=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
  mem_free=$(grep MemFree /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
  local hash_rate="N/A"
  if [ -f "$MINER_LOG" ]; then
    hash_rate=$(tail -n 50 "$MINER_LOG" | grep -oE '[0-9]+(\.[0-9]+)?[kM]?H/s' | tail -n1 || true)
    [ -z "$hash_rate" ] && hash_rate="N/A"
  fi
  cat > "$RUN_INFO_FILE" <<EOF
Last Run Timestamp: $(date +"%Y-%m-%d %H:%M:%S")
Status: $status
Error Code: $errcode
Runtime Seconds: $runtime
CPU Model: $cpu_model
Memory Total KB: $mem_total
Memory Free KB: $mem_free
Threads: $THREADS
Wallet: $WALLET
Pool: $POOL
Miner Mode: $MODE
Active Miner: $ACTIVE_MINER
Hash Rate (approx): $hash_rate
EOF
}

show_run_info() {
  banner
  echo -e "${CYAN}Last run details:${NC}"
  if [ -f "$RUN_INFO_FILE" ]; then
    cat "$RUN_INFO_FILE"
  else
    echo "No run.info found."
  fi
  pause
}

# === Interactive Wizard ===
run_wizard() {
  banner
  cEcho $CYAN "Welcome to Nova Versus Miner!"
  cEcho $BLUE "Let's quickly configure your mining setup."
  # Wallet
  while true; do
    read -rp "Enter your Verus wallet address (starts with R): " WALLET
    validate_wallet && break
    cEcho $RED "Invalid wallet format. Please try again."
  done
  # Pool
  echo -e "${YELLOW}Suggested Pools:"
  for i in "${!SUGGESTED_POOLS[@]}"; do
    echo "  $((i+1))) ${SUGGESTED_POOLS[$i]}"
  done
  echo "  $(( ${#SUGGESTED_POOLS[@]} + 1 ))) Custom"
  while true; do
    read -rp "Choose pool [1-$(( ${#SUGGESTED_POOLS[@]} + 1 ))]: " pool_choice
    if [[ "$pool_choice" =~ ^[1-9][0-9]*$ ]] && [ "$pool_choice" -le "${#SUGGESTED_POOLS[@]}" ]; then
      POOL="${SUGGESTED_POOLS[$((pool_choice-1))]}"
      break
    elif [ "$pool_choice" -eq $(( ${#SUGGESTED_POOLS[@]} + 1 )) ]; then
      read -rp "Enter custom pool (host:port): " POOL
      validate_pool && break
      cEcho $RED "Invalid pool format. Try again."
    else
      cEcho $RED "Invalid choice. Try again."
    fi
  done
  # Booster Modes (compat per miner)
  echo -e "${YELLOW}Mining Modes:"
  echo "  1) Low Power (save battery)"
  echo "  2) Balanced (recommended)"
  echo "  3) Boosted (max performance)"
  echo "  4) Custom (manual settings)"
  while true; do
    read -rp "Choose mining mode [1-4]: " mode_choice
    case $mode_choice in
      1) MODE="lowpower"; THREADS=1; MINER_ARGS=""; break;;
      2) MODE="balanced"; THREADS=$(( (nproc || echo 2) / 2 )); MINER_ARGS=""; break;;
      3) MODE="boosted"; THREADS=$(nproc || echo 2); MINER_ARGS=""; break;;
      4) MODE="custom"; read -rp "Threads: " THREADS; validate_threads || THREADS=2; read -rp "Extra miner args: " MINER_ARGS; break;;
      *) cEcho $RED "Invalid choice. Try again.";;
    esac
  done
  # Backup Pools
  BACKUP_POOLS=()
  echo -e "${YELLOW}Setup backup pools for redundancy?${NC}"
  for p in "${SUGGESTED_POOLS[@]}"; do
    if [ "$p" != "$POOL" ]; then
      read -rp "Add $p as backup? [y/N]: " yn
      if [[ "$yn" =~ ^[Yy] ]]; then
        BACKUP_POOLS+=("$p")
      fi
    fi
  done
  # Miner selection
  echo -e "${YELLOW}Available miners:${NC}"
  for i in "${!MINERS[@]}"; do
    echo "  $((i+1))) ${MINERS[$i]}"
  done
  read -rp "Choose active miner [1-${#MINERS[@]}] (default: 1): " miner_choice
  if [[ "$miner_choice" =~ ^[1-9][0-9]*$ ]] && [ "$miner_choice" -le "${#MINERS[@]}" ]; then
    ACTIVE_MINER="${MINERS[$((miner_choice-1))]}"
    set_active_miner "$ACTIVE_MINER"
  else
    ACTIVE_MINER="${MINERS[0]}"
    set_active_miner "$ACTIVE_MINER"
  fi
  save_config
  cEcho $GREEN "[✓] Initial configuration saved!"
  pause
}

# === Miner Control (Multi-miner) ===
start_miner() {
  load_config
  if ! validate_wallet; then cEcho $RED "[!] Invalid or missing wallet."; return 1; fi
  if ! validate_pool; then cEcho $RED "[!] Invalid or missing pool."; return 1; fi
  if ! validate_threads; then THREADS=$(nproc || echo 2); fi
  check_miner_binary "$ACTIVE_MINER" || return 1
  if [ -f "$MINER_PID_FILE" ]; then
    local pid
    pid=$(cat "$MINER_PID_FILE" 2>/dev/null || echo "")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      cEcho $YELLOW "[*] Miner already running (PID $pid)."
      return 0
    fi
  fi
  local bin="$BIN_DIR/$ACTIVE_MINER"
  local cmd=""
  case "$ACTIVE_MINER" in
    verus-miner)
      case "$MODE" in
        lowpower) MINER_ARGS="--lowpower";;
        boosted) MINER_ARGS="--max-performance";;
        balanced|custom) ;;
      esac
      cmd="\"$bin\" --wallet \"$WALLET\" --pool \"$POOL\" --threads \"$THREADS\" $MINER_ARGS"
      ;;
    cpuminer)
      case "$MODE" in
        lowpower) MINER_ARGS="-t 1";;
        boosted) MINER_ARGS="-t $THREADS";;
        balanced|custom) ;;
      esac
      cmd="\"$bin\" -a verus -o stratum+tcp://$POOL -u \"$WALLET\" $MINER_ARGS"
      ;;
    xmrig)
      case "$MODE" in
        lowpower) MINER_ARGS="--threads=1";;
        boosted) MINER_ARGS="--threads=$THREADS";;
        balanced|custom) ;;
      esac
      cmd="\"$bin\" -o $POOL -u \"$WALLET\" $MINER_ARGS"
      ;;
    *)
      cEcho $RED "[!] Unknown miner type."
      return 1
      ;;
  esac
  nohup bash -c "$cmd" > "$MINER_LOG" 2>&1 &
  local pid=$!
  echo "$pid" > "$MINER_PID_FILE"
  MINER_PID="$pid"
  cEcho $GREEN "[✓] $ACTIVE_MINER started (PID $pid). Logs: $MINER_LOG"
  write_run_info "running" 0
}
stop_miner() {
  if [ -f "$MINER_PID_FILE" ]; then
    local pid
    pid=$(cat "$MINER_PID_FILE" 2>/dev/null || echo "")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      cEcho $YELLOW "[*] Stopping miner (PID $pid)..."
      kill "$pid" || true
      sleep 2
      if kill -0 "$pid" 2>/dev/null; then
        cEcho $RED "[!] Miner did not stop; forcing kill..."
        kill -9 "$pid" || true
      fi
    fi
    rm -f "$MINER_PID_FILE"
    write_run_info "stopped" 0
    cEcho $GREEN "[✓] Miner stopped."
  else
    cEcho $YELLOW "[*] Miner not running."
  fi
}
restart_miner() {
  stop_miner
  sleep 1
  start_miner
}
miner_status() {
  banner
  load_config
  if [ -f "$MINER_PID_FILE" ]; then
    local pid
    pid=$(cat "$MINER_PID_FILE" 2>/dev/null || echo "")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo -e "${GREEN}Miner running (PID: $pid)${NC}"
      echo "Threads: $THREADS"
      echo "Wallet: $WALLET"
      echo "Pool: $POOL"
      echo "Mode: $MODE"
      echo "Active Miner: $ACTIVE_MINER"
      echo "Backup Pools: ${BACKUP_POOLS[*]}"
      echo "Log tail (last 10 lines):"
      tail -n 10 "$MINER_LOG" || true
    else
      cEcho $YELLOW "[*] PID present but process not running."
    fi
  else
    cEcho $RED "Miner is not running."
  fi
  pause
}

# === Multi-miner Menu ===
miner_switch_menu() {
  banner
  list_miners
  echo -e "${CYAN}Available Miners:${NC}"
  for i in "${!MINERS[@]}"; do
    echo "  $((i+1))) ${MINERS[$i]}"
  done
  read -rp "Choose new active miner [1-${#MINERS[@]}]: " miner_choice
  if [[ "$miner_choice" =~ ^[1-9][0-9]*$ ]] && [ "$miner_choice" -le "${#MINERS[@]}" ]; then
    ACTIVE_MINER="${MINERS[$((miner_choice-1))]}"
    set_active_miner "$ACTIVE_MINER"
    cEcho $GREEN "[✓] Active miner set to $ACTIVE_MINER"
    save_config
  else
    cEcho $YELLOW "Invalid. Keeping current."
  fi
  pause
}

add_miner_menu() {
  banner
  read -rp "Enter new miner binary name (must be in $BIN_DIR): " new_miner
  if [ -x "$BIN_DIR/$new_miner" ]; then
    MINERS+=("$new_miner")
    save_miners_list
    cEcho $GREEN "[✓] Miner $new_miner added to list."
  else
    cEcho $RED "[!] Binary $new_miner not found or not executable."
  fi
  pause
}

# === Stats Dashboard ===
show_dashboard() {
  banner
  load_config
  echo -e "${CYAN}Mining Stats Dashboard:${NC}"
  echo "$BOX_TOP"
  local hashrate accepted rejected errors coins termux_status
  if [ "$IS_TERMUX" -eq 1 ] && ! command -v termux-notification >/dev/null 2>&1; then
    termux_status="$termux_api_warning"
  else
    termux_status="OK"
  fi

  hashrate=$(tail -n 100 "$MINER_LOG" | grep -oE '[0-9]+(\.[0-9]+)?[kM]?H/s' | tail -n1)
  [ -z "$hashrate" ] && hashrate="N/A"
  accepted=$(grep -c -i 'accepted' "$MINER_LOG" 2>/dev/null || echo 0)
  rejected=$(grep -c -i 'rejected' "$MINER_LOG" 2>/dev/null || echo 0)
  errors=$(grep -c -i 'error' "$MINER_LOG" 2>/dev/null || echo 0)
  coins=$(grep -c -i 'found' "$MINER_LOG" 2>/dev/null || echo 0)
  printf "│ %-18s: %-20s │\n" "Termux API" "$termux_status"
  printf "│ %-18s: %-20s │\n" "Hashrate" "$hashrate"
  printf "│ %-18s: %-20s │\n" "Accepted" "$accepted"
  printf "│ %-18s: %-20s │\n" "Rejected" "$rejected"
  printf "│ %-18s: %-20s │\n" "Errors" "$errors"
  printf "│ %-18s: %-20s │\n" "Coins Found" "$coins"
  echo "$BOX_BOT"
  pause
}

# === Watchdog & Monitoring ===
notify_user() {
  local msg="$1"
  local title="${2:-Nova Versus Miner Alert}"
  if [ "$IS_TERMUX" -eq 1 ] && command -v termux-notification >/dev/null 2>&1; then
    termux-notification --title "$title" --content "$msg" --priority high || true
  else
    echo -e "${YELLOW}[NOTIFY]${NC} $title - $msg"
    if command -v notify-send >/dev/null 2>&1; then
      notify-send "$title" "$msg" || true
    fi
  fi
  echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" >> "$WATCHDOG_LOG"
}
watchdog_loop() {
  local INTERVAL=60
  cEcho $CYAN "[*] Watchdog started (interval ${INTERVAL}s)."
  while true; do
    # Miner alive check
    if [ ! -f "$MINER_PID_FILE" ] || ! (pid=$(cat "$MINER_PID_FILE" 2>/dev/null) && kill -0 "$pid" 2>/dev/null); then
      cEcho $RED "[!] Miner process not found, attempting restart..."
      restart_miner && notify_user "Miner restarted by watchdog" || notify_user "Watchdog failed to restart miner"
      sleep 5
    fi
    # Termux checks: battery/temp when available
    if [ "$IS_TERMUX" -eq 1 ] && command -v termux-battery-status >/dev/null 2>&1; then
      battery_info="$(termux-battery-status 2>/dev/null || echo '{}')"
      battery_level=$(echo "$battery_info" | jq '.percentage' 2>/dev/null || echo 100)
      charging=$(echo "$battery_info" | jq '.plugged' 2>/dev/null || echo false)
      if [ -n "$battery_level" ] && [ "$battery_level" -lt 15 ] && [ "$charging" != "true" ]; then
        cEcho $YELLOW "[!] Low battery ($battery_level%). Pausing miner."
        stop_miner
        notify_user "Miner paused: battery $battery_level%"
      fi
    fi
    # Temperature check (Termux sensor)
    if [ "$IS_TERMUX" -eq 1 ] && command -v termux-sensor >/dev/null 2>&1; then
      cpu_temp=$(termux-sensor | jq -r '.[] | select(.name=="cpu_temperature") | .value' 2>/dev/null || echo "")
      if [ -n "$cpu_temp" ]; then
        if awk "BEGIN {exit !($cpu_temp > 75)}"; then
          cEcho $YELLOW "[!] High CPU temp: ${cpu_temp}C. Pausing miner."
          stop_miner
          notify_user "Miner paused: high CPU temp ${cpu_temp}C"
        fi
      fi
    fi
    # Disk space
    avail=$(df -k "$CONFIG_DIR" 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)
    if [ -n "$avail" ] && [ "$avail" -lt 10240 ]; then
      notify_user "Low disk space: ${avail}KB in $CONFIG_DIR"
    fi
    sleep "$INTERVAL"
  done
}
watchdog_start() {
  if [ -f "$WATCHDOG_PID_FILE" ]; then
    local pid
    pid=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null || echo "")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      cEcho $YELLOW "[*] Watchdog already running (PID $pid)."
      return 0
    fi
  fi
  watchdog_loop & disown
  local pid=$!
  echo "$pid" > "$WATCHDOG_PID_FILE"
  cEcho $GREEN "[✓] Watchdog started (PID $pid)."
}
watchdog_stop() {
  if [ -f "$WATCHDOG_PID_FILE" ]; then
    local pid
    pid=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null || echo "")
    if [ -n "$pid" ]; then
      kill "$pid" 2>/dev/null || true
      rm -f "$WATCHDOG_PID_FILE"
      cEcho $GREEN "[✓] Watchdog stopped."
    fi
  else
    cEcho $YELLOW "[*] Watchdog not running."
  fi
}

# === Auto-update Script ===
check_script_update() {
  cEcho $CYAN "[*] Checking for script updates..."
  local latest_version
  latest_version=$(curl -fsSL "https://raw.githubusercontent.com/$GITHUB_REPO/main/version.txt" 2>/dev/null || echo "")
  if [ -z "$latest_version" ]; then
    cEcho $YELLOW "[i] Could not fetch latest version info."
    return 1
  fi
  if [ "$latest_version" != "$SCRIPT_VERSION" ]; then
    cEcho $GREEN "[✓] New version available: $latest_version. Updating..."
    update_script
    return 0
  else
    cEcho $GREEN "[✓] Script is up to date."
    return 1
  fi
}
update_script() {
  local script_url="https://raw.githubusercontent.com/$GITHUB_REPO/main/NovaVersusMiner.sh"
  if curl -fsSL "$script_url" -o "$CONFIG_DIR/NovaVersusMiner.sh.tmp"; then
    mv "$CONFIG_DIR/NovaVersusMiner.sh.tmp" "$0"
    chmod +x "$0"
    cEcho $GREEN "[✓] Script updated successfully. Restarting..."
    exec "$0" "$@"
  else
    cEcho $RED "[!] Failed to download updated script."
    return 1
  fi
}

# === Logs ===
logs_menu() {
  banner
  echo "1) Tail miner log"
  echo "2) Tail watchdog log"
  echo "3) Show logs folder"
  echo "4) Clear logs"
  echo "0) Back"
  read -rp "Choice: " lchoice
  case "$lchoice" in
    1) [ -f "$MINER_LOG" ] && tail -n 200 -f "$MINER_LOG" || cEcho $YELLOW "No miner log yet." ;;
    2) [ -f "$WATCHDOG_LOG" ] && tail -n 200 -f "$WATCHDOG_LOG" || cEcho $YELLOW "No watchdog log yet." ;;
    3) ls -lah "$LOG_DIR"; read -rp "Press Enter..." ;;
    4) rm -f "$LOG_DIR"/* && mkdir -p "$LOG_DIR" && cEcho $GREEN "[✓] Logs cleared." ;;
    0) return ;;
    *) cEcho $YELLOW "Invalid" ;;
  esac
}

# === Export/Import Config ===
export_config() {
  local out="$HOME_DIR/nova_config_export_$(date +%s).conf"
  cp -f "$CONFIG_FILE" "$out" && cEcho $GREEN "[✓] Config exported to $out"
}
import_config() {
  read -rp "Enter path to config file to import: " imp
  if [ -f "$imp" ]; then
    cp -f "$imp" "$CONFIG_FILE"
    load_config
    cEcho $GREEN "[✓] Config imported and loaded."
  else
    cEcho $RED "[!] File not found."
  fi
}

# === Module Loader ===
load_modules() {
  for mod in "$MODULES_DIR"/*.sh; do
    [ -f "$mod" ] && source "$mod"
  done
}

# === Main Menu ===
show_main_menu() {
  load_modules
  while true; do
    banner
    echo -e "${CYAN}1) Configure Wallet & Pool"
    echo -e "2) Configure Mining Mode & Threads"
    echo -e "3) Start Miner"
    echo -e "4) Stop Miner"
    echo -e "5) Restart Miner"
    echo -e "6) Miner Status"
    echo -e "7) Show Last Run Info"
    echo -e "8) Start Watchdog"
    echo -e "9) Stop Watchdog"
    echo -e "10) Download/Check Miner Binary"
    echo -e "11) Check for Script Update"
    echo -e "12) Logs & Tail"
    echo -e "13) Export Config"
    echo -e "14) Import Config"
    echo -e "15) Mining Stats Dashboard"
    echo -e "16) Switch Miner"
    echo -e "17) Add Miner"
    echo -e "0) Exit${NC}"
    read -rp "Choose an option: " choice
    case $choice in
      1) run_wizard ;;
      2) run_wizard ;; # Also allows changing mode/threads via wizard
      3) start_miner; notify_user "Miner started" "Nova Versus Miner" ;;
      4) stop_miner; notify_user "Miner stopped" "Nova Versus Miner" ;;
      5) restart_miner; notify_user "Miner restarted" "Nova Versus Miner" ;;
      6) miner_status ;;
      7) show_run_info ;;
      8) watchdog_start ;;
      9) watchdog_stop ;;
      10) check_miner_binary "$ACTIVE_MINER" ;;
      11) check_script_update ;;
      12) logs_menu ;;
      13) export_config ;;
      14) import_config ;;
      15) show_dashboard ;;
      16) miner_switch_menu ;;
      17) add_miner_menu ;;
      0) stop_miner; watchdog_stop; cEcho $GREEN "Goodbye!"; exit 0 ;;
      *) cEcho $RED "Invalid option. Try again.";;
    esac
    pause
  done
}

# === Initial Boot Flow ===
initial_setup() {
  banner
  detect_environment
  check_dependencies
  check_termux_api
  termux_storage_setup
  load_config
}

# === Entry Point ===
main() {
  initial_setup
  if [ ! -f "$CONFIG_FILE" ]; then
    run_wizard
  fi
  show_main_menu
}
main
