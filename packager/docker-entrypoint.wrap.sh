#!/usr/bin/env bash
set -euo pipefail

# 基本限制，避免文件句柄过低
ulimit -Sn 10000 || true

# 目录与环境
STEAMCMDDIR="${STEAMCMDDIR:-/steamcmd}"
DST_DIR="${DST_DIR:-/app/dst-dedicated-server}"
KLEI_DIR="${KLEI_DIR:-/root/.klei/DoNotStarveTogether}"
CLUSTER_NAME="${CLUSTER_NAME:-MyDediServer}"

# 需要的工具与模拟器
command -v box86 >/dev/null || { echo "box86 not found"; exit 1; }
command -v box64 >/dev/null || { echo "box64 not found"; exit 1; }

# 将目标 ELF 包裹到 box86/box64 下运行
create_wrapper() {
  # $1=target; $2=boxer (box86|box64)
  local target="$1" boxer="$2"
  [ -e "$target" ] || return 0
  local real="${target}.real"
  if [ ! -e "$real" ]; then
    mv "$target" "$real"
  fi
  cat > "$target" <<EOF
#!/usr/bin/env bash
exec ${boxer} "${real}" "\$@"
EOF
  chmod +x "$target"
}

echo "[entrypoint] ensure steamcmd exists"
mkdir -p "${STEAMCMDDIR}"
if [ ! -e "${STEAMCMDDIR}/steamcmd.sh" ]; then
  curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz -o "${STEAMCMDDIR}/steamcmd_linux.tar.gz"
  tar -xzf "${STEAMCMDDIR}/steamcmd_linux.tar.gz" -C "${STEAMCMDDIR}"
  rm -f "${STEAMCMDDIR}/steamcmd_linux.tar.gz"
fi
# steamcmd 是 i386，可用 box86 包裹
create_wrapper "${STEAMCMDDIR}/steamcmd.sh" "box86"

echo "[entrypoint] ensure DST dedicated server installed"
mkdir -p "${DST_DIR}"
if [ ! -e "${DST_DIR}/bin/dontstarve_dedicated_server_nullrenderer" ] && \
   [ ! -e "${DST_DIR}/bin/dontstarve_dedicated_server_nullrenderer_x64" ]; then
  "${STEAMCMDDIR}/steamcmd.sh" +force_install_dir "${DST_DIR}" +login anonymous +app_update 343050 validate +quit
fi

echo "[entrypoint] wrap DST server binaries if present"
if [ -e "${DST_DIR}/bin/dontstarve_dedicated_server_nullrenderer_x64" ]; then
  create_wrapper "${DST_DIR}/bin/dontstarve_dedicated_server_nullrenderer_x64" "box64"
fi
if [ -e "${DST_DIR}/bin/dontstarve_dedicated_server_nullrenderer" ]; then
  # 非必须，但也包一层（如是 32 位则用 box86）
  create_wrapper "${DST_DIR}/bin/dontstarve_dedicated_server_nullrenderer" "box86"
fi

echo "[entrypoint] ensure Klei dirs and minimal dst_config"
mkdir -p "${KLEI_DIR}/${CLUSTER_NAME}" "${KLEI_DIR}/backup" "${KLEI_DIR}/download_mod"

# 如果镜像内未提供 dst_config（目录或文件），则生成默认文件放到 /app/dst_config/dst_config
if [ ! -d "/app/dst_config" ]; then
  mkdir -p /app/dst_config
fi
if [ ! -f "/app/dst_config/dst_config" ]; then
  cat > /app/dst_config/dst_config <<CFG
steamcmd=${STEAMCMDDIR}
force_install_dir=${DST_DIR}
cluster=${CLUSTER_NAME}
backup=${KLEI_DIR}/backup
mod_download_path=${KLEI_DIR}/download_mod
CFG
fi

echo "[entrypoint] launch panel"
cd /app
exec ./dst-admin-go
