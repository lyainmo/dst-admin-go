#!/usr/bin/env bash
set -euo pipefail

# 基本限制，避免文件句柄过低
ulimit -Sn 10000 || true

# 目录与环境
STEAMCMDDIR="${STEAMCMDDIR:-/app/steamcmd}"
DST_DIR="${DST_DIR:-/app/dst-dedicated-server}"

log() { echo "[$(date +'%H:%M:%S')] $*"; }

need_root() {
  if [ "$(id -u)" != "0" ]; then
    log "ERROR: this entrypoint requires root to install packages."
    exit 1
  fi
}

apt_update_safe() {
  apt-get update -y || (sleep 2 && apt-get update -y)
}

add_repo_if_missing() {
  # $1=name(box86|box64) $2=list_url $3=key_url $4=keyring_path
  local name="$1" list_url="$2" key_url="$3" keyring="$4"
  local list_file="/etc/apt/sources.list.d/${name}.list"

  if [ ! -f "$list_file" ]; then
    log "Adding $name repo list: $list_url"
    if ! wget -qO "$list_file" "$list_url"; then
      log "ERROR: failed to fetch repo list: $list_url"
      return 1
    fi
  fi

  if [ ! -f "$keyring" ]; then
    log "Fetching $name repo key: $key_url"
    # 试 KEY.gpg，失败则尝试常见备选名
    if ! wget -qO- "$key_url" | gpg --dearmor -o "$keyring"; then
      for alt in KEY.gpg REPO.KEY Release.key; do
        if wget -qO- "${key_url%/*}/$alt" | gpg --dearmor -o "$keyring" 2>/dev/null; then
          log "Fetched alt key: $alt"
          break
        fi
      done
    fi
    if [ ! -s "$keyring" ]; then
      log "ERROR: failed to fetch/dearmor repo key for $name"
      rm -f "$keyring"
      return 1
    fi
  fi
}

detect_target_box64() {
  # 一些平台有优化，否则使用通用包
  local cpuinfo; cpuinfo="$(tr '[:upper:]' '[:lower:]' < /proc/cpuinfo)"
  if grep -q 'rk3588' <<<"$cpuinfo"; then echo box64-rk3588; return; fi
  if grep -q 'rk3399' <<<"$cpuinfo"; then echo box64-rk3399; return; fi
  if grep -q 'tegra'  <<<"$cpuinfo"; then echo box64-tegrax1; return; fi
  if grep -q 't194' <<<"$cpuinfo"; then echo box64-tegra-t194; return; fi
  if grep -qi 'raspberry' /proc/device-tree/model 2>/dev/null; then
    if grep -qi 'Raspberry Pi 5' /proc/device-tree/model 2>/dev/null; then
      echo box64-rpi5arm64; return
    fi
    echo box64-rpi4arm64; return
  fi
  echo box64
}

detect_target_box86() {
  # 一些平台有优化，否则使用通用包
  local cpuinfo; cpuinfo="$(tr '[:upper:]' '[:lower:]' < /proc/cpuinfo)"
  if grep -q 'rk3588' <<<"$cpuinfo"; then echo box86-rk3588; return; fi
  if grep -q 'rk3399' <<<"$cpuinfo"; then echo box86-rk3399; return; fi
  if grep -q 'tegra'  <<<"$cpuinfo"; then echo box86-tegrax1; return; fi
  if grep -qi 'raspberry' /proc/device-tree/model 2>/dev/null; then
    echo box86-rpi4arm64; return
  fi
  echo box86-generic-arm
}

install_box64_if_needed() {
  if command -v box64 >/dev/null 2>&1; then
    log "box64 already installed: $(box64 -v 2>/dev/null || true)"
    return 0
  fi
  need_root
  pkg_ensure_tools

  # 仓库与 key
  local list_url="https://ryanfortner.github.io/box64-debs/box64.list"
  local key_url="https://ryanfortner.github.io/box64-debs/KEY.gpg"
  local keyring="/etc/apt/trusted.gpg.d/box64-debs-archive-keyring.gpg"

  # 可选：中国大陆镜像（官方页面注明第三方镜像，有风险）
  if [ "${USE_BOX64_CN_MIRROR:-0}" = "1" ]; then
    list_url="https://cdn05042023.gitlink.org.cn/shenmo7192/box64-debs/raw/branch/master/box64-CN.list"
    key_url="https://cdn05042023.gitlink.org.cn/shenmo7192/box64-debs/raw/branch/master/KEY.gpg"
    log "Using CN mirror for box64"
  fi

  if ! add_repo_if_missing "box64" "$list_url" "$key_url" "$keyring"; then
    log "WARN: failed to add box64 repo/key; skip install for now"
    return 1
  fi

  apt_update_safe
  local pkg; pkg="$(detect_target_box64)"
  log "Installing box64 package: $pkg"
  if ! apt-get install -y --no-install-recommends "$pkg"; then
    log "WARN: install $pkg failed, fallback to box64"
    apt-get install -y --no-install-recommends box64 || {
      log "ERROR: box64 install failed"; return 1; }
  fi
}

install_box86_if_needed() {
  if command -v box86 >/dev/null 2>&1; then
    log "box86 already installed: $(box86 -v 2>/dev/null || true)"
    return 0
  fi
  need_root
  pkg_ensure_tools

  local arch; arch="$(uname -m)"
  if [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ]; then
    log "Enable armhf multiarch for box86 on arm64"
    dpkg --add-architecture armhf || true
  fi

  local list_url="https://ryanfortner.github.io/box86-debs/box86.list"
  local key_url="https://ryanfortner.github.io/box86-debs/KEY.gpg"
  local keyring="/etc/apt/trusted.gpg.d/box86-debs-archive-keyring.gpg"

  if ! add_repo_if_missing "box86" "$list_url" "$key_url" "$keyring"; then
    log "WARN: failed to add box86 repo/key; skip install for now"
    return 1
  fi

  apt_update_safe
  local pkg; pkg="$(detect_target_box86)"
  if [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ]; then
    pkg="${pkg}:armhf"
  fi

  log "Installing box86 package: $pkg"
  if ! apt-get install -y --no-install-recommends "$pkg"; then
    log "WARN: install $pkg failed, fallback to generic"
    local fallback="box86-generic-arm"
    if [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ]; then
      fallback="${fallback}:armhf"
    fi
    apt-get install -y --no-install-recommends "$fallback" || {
      log "ERROR: box86 install failed"; return 1; }
  fi
}

# 运行时确保已安装 box64/box86
install_box64_if_needed || true
install_box86_if_needed || true

# 若仍未安装，则直接报错退出
command -v box86 >/dev/null || { echo "box86 not found"; exit 1; }
command -v box64 >/dev/null || { echo "box64 not found"; exit 1; }

#SteamCMD下载
echo "[entrypoint] ensure steamcmd exists"
mkdir -p "${STEAMCMDDIR}"
retry=1
while [ ! -e "${STEAMCMDDIR}/steamcmd.sh" ] || [ ! -e "${STEAMCMDDIR}/linux32/steamcmd" ]; do
  if [ $retry -gt 3 ]; then
    echo "Download steamcmd failed after three times"
    exit -2
  fi
  echo "Not found steamcmd, start to installing steamcmd, try: ${retry}"
  wget http://media.steampowered.com/installer/steamcmd_linux.tar.gz -P "${STEAMCMDDIR}"
  tar -zxvf "${STEAMCMDDIR}/steamcmd_linux.tar.gz" -C "${STEAMCMDDIR}"
  rm -f "${STEAMCMDDIR}/steamcmd_linux.tar.gz"
  sleep 3
  ((retry++))
done

#安装饥荒服务端
echo "[entrypoint] ensure DST dedicated server installed"
mkdir -p "${DST_DIR}"
retry=1
while [ ! -e "${DST_DIR}/bin/dontstarve_dedicated_server_nullrenderer" ] && \
      [ ! -e "${DST_DIR}/bin/dontstarve_dedicated_server_nullrenderer_x64" ]; do
  if [ $retry -gt 3 ]; then
    echo "Download Dont Starve Together Server failed after three times"
    exit -2
  fi
  echo "Not found DST server, start to installing, try: ${retry}"
  
  setsid bash -c '
    timeout 3h box86 "'"${STEAMCMDDIR}/linux32/steamcmd"'" \
      +force_install_dir "'"${DST_DIR}"'" \
      +login anonymous \
      +app_update 343050 validate \
      +quit
  ' || true
  sleep 3
  ((retry++))
done


echo "[entrypoint] launch panel"
cd /app
exec ./dst-admin-go
