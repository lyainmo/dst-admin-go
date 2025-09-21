#!/usr/bin/env bash
set -euo pipefail

# Basic limits for better stability
ulimit -Sn 10000 || true

# Paths and env (allow override)
STEAMCMDDIR="${STEAMCMDDIR:-/steamcmd}"
DST_DIR="${DST_DIR:-/app/dst-dedicated-server}"

# Ensure box is present
command -v box86 >/dev/null || { echo "box86 not found"; exit 1; }
command -v box64 >/dev/null || { echo "box64 not found"; exit 1; }

create_wrapper() {
  # $1 = target binary path; $2 = boxer (box86|box64)
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

# 1) Ensure steamcmd installed (image provides it), then wrap with box86
mkdir -p "${STEAMCMDDIR}"
if [ ! -e "${STEAMCMDDIR}/steamcmd.sh" ]; then
  echo "steamcmd missing in image; attempting download..."
  curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz -o "${STEAMCMDDIR}/steamcmd_linux.tar.gz"
  tar -xzf "${STEAMCMDDIR}/steamcmd_linux.tar.gz" -C "${STEAMCMDDIR}"
  rm -f "${STEAMCMDDIR}/steamcmd_linux.tar.gz"
fi
create_wrapper "${STEAMCMDDIR}/steamcmd.sh" "box86"

# 2) Ensure DST dedicated server installed (app_id 343050)
mkdir -p "${DST_DIR}"
if [ ! -e "${DST_DIR}/bin/dontstarve_dedicated_server_nullrenderer" ] && \
   [ ! -e "${DST_DIR}/bin/dontstarve_dedicated_server_nullrenderer_x64" ]; then
  "${STEAMCMDDIR}/steamcmd.sh" +force_install_dir "${DST_DIR}" +login anonymous +app_update 343050 validate +quit
fi

# 3) Wrap DST server binary with box64
if [ -e "${DST_DIR}/bin/dontstarve_dedicated_server_nullrenderer_x64" ]; then
  create_wrapper "${DST_DIR}/bin/dontstarve_dedicated_server_nullrenderer_x64" "box64"
elif [ -e "${DST_DIR}/bin/dontstarve_dedicated_server_nullrenderer" ]; then
  create_wrapper "${DST_DIR}/bin/dontstarve_dedicated_server_nullrenderer" "box64"
fi

# 4) Launch panel (ARM64 native)
cd /app
exec ./dst-admin-go
