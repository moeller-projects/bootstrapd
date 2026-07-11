#!/usr/bin/env bash
# modules/60-ai.sh — Stage 5: AI tooling (OpenClaw, Pi, Codex CLI, Claude Code).
set -Eeuo pipefail

mod_60_ai_description() { echo "AI tooling: OpenClaw, Pi, Codex CLI, Claude Code"; }
mod_60_ai_stage()       { echo "5"; }
mod_60_ai_dependencies(){ echo "50-dev"; }

mod_60_ai_check() {
  if bootstrap_config_bool ENABLE_PI; then
    command -v pi >/dev/null || return 1
  fi
  return 0
}

# Write a systemd *user* unit for an AI agent that auto-restarts.
_install_user_unit() {
  local user="$1" unit_name="$2" exec="$3"
  local home unit_dir unit_path
  home="$(getent passwd "$user" | cut -d: -f6)"
  unit_dir="$home/.config/systemd/user"
  unit_path="$unit_dir/${unit_name}.service"
  if [[ -f "$unit_path" ]] && grep -qF "ExecStart=$exec" "$unit_path"; then
    log_debug "user unit already present: $unit_name"
    return 0
  fi
  log_info "installing user unit: $unit_name for $user"
  if (( BOOTSTRAP_DRY_RUN )); then
    return 0
  fi
  fs_mkdir_p "$unit_dir"
  cat > "$unit_path" <<EOF
[Unit]
Description=BootstrapX managed: ${unit_name}
After=network-online.target

[Service]
Type=simple
ExecStart=${exec}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF
  chmod 0644 "$unit_path"
  bootstrap_chown_if_root -- "$user:$user" "$unit_path"
  su - "$user" -s /bin/bash -c "XDG_RUNTIME_DIR=/run/user/$(id -u "$user") systemctl --user daemon-reload" \
    2>/dev/null || true
}

mod_60_ai_install() {
  local admin="${ADMIN_USER:-admin}"

  # OpenClaw — installed from upstream install script (pin to a known URL).
  if bootstrap_config_bool ENABLE_OPENCLAW; then
    if ! command -v openclaw >/dev/null && [[ ! -d /opt/openclaw ]]; then
      log_info "installing OpenClaw"
      if (( ! BOOTSTRAP_DRY_RUN )); then
        ensure_directory /opt/openclaw 0755 root:root
        git clone --depth 1 https://github.com/openclaw/openclaw.git /opt/openclaw \
          || log_warn "openclaw clone failed; install manually"
        if [[ -f /opt/openclaw/install.sh ]]; then
          bash /opt/openclaw/install.sh
        fi
      fi
    fi
  fi

  # Pi Coding Agent — installed via the official installer script.
  if bootstrap_config_bool ENABLE_PI; then
    if ! command -v pi >/dev/null 2>&1; then
      log_info "installing Pi Coding Agent"
      if (( ! BOOTSTRAP_DRY_RUN )); then
        curl --fail --location --silent --show-error \
          --connect-timeout 15 --max-time 300 \
          https://pi.dev/install.sh | bash
        # Install to /usr/local/bin for system-wide use if installer dropped it locally.
        if [[ -f "$HOME/.local/bin/pi" ]]; then
          install -m 0755 "$HOME/.local/bin/pi" /usr/local/bin/pi
        elif [[ -f /root/.local/bin/pi ]]; then
          install -m 0755 /root/.local/bin/pi /usr/local/bin/pi
        fi
      fi
    fi
  fi

  # Codex CLI — npm-distributed.
  if bootstrap_config_bool ENABLE_CODEX; then
    if ! command -v codex >/dev/null 2>&1 && command -v npm >/dev/null; then
      log_info "installing Codex CLI"
      if (( ! BOOTSTRAP_DRY_RUN )); then
        npm install -g @openai/codex 2>/dev/null \
          || log_warn "codex npm install failed; install manually"
      fi
    fi
  fi

  # Claude Code — npm-distributed.
  if bootstrap_config_bool ENABLE_CLAUDE; then
    if ! command -v claude >/dev/null 2>&1 && command -v npm >/dev/null; then
      log_info "installing Claude Code"
      if (( ! BOOTSTRAP_DRY_RUN )); then
        npm install -g @anthropic-ai/claude-code 2>/dev/null \
          || log_warn "claude npm install failed; install manually"
      fi
    fi
  fi

  # Optional: Ollama local model server.
  if bootstrap_config_bool ENABLE_OLLAMA; then
    if ! command -v ollama >/dev/null 2>&1; then
      log_info "installing Ollama"
      if (( ! BOOTSTRAP_DRY_RUN )); then
        curl --fail --location --silent --show-error \
          --connect-timeout 15 --max-time 600 \
          https://ollama.com/install.sh | bash
        ensure_service_enabled ollama
      fi
    fi
  fi

  # Per-user workspace dirs (re-stated here for clarity; matches ARCHITECTURE.md).
  if id "$admin" >/dev/null 2>&1; then
    local home
    home="$(getent passwd "$admin" | cut -d: -f6)"
    for sub in workspace repos cache logs agents; do
      ensure_directory "$home/$sub" 0755 "$admin:$admin"
    done

    # Systemd user units for whichever agents are installed.
    if command -v pi >/dev/null; then
      _install_user_unit "$admin" "pi-agent" "/usr/local/bin/pi --loop"
    fi
    if command -v codex >/dev/null; then
      _install_user_unit "$admin" "codex-agent" "/usr/local/bin/codex --auto"
    fi
    if command -v claude >/dev/null; then
      _install_user_unit "$admin" "claude-agent" "/usr/local/bin/claude --auto"
    fi
  fi
}

mod_60_ai_validate() {
  if bootstrap_config_bool ENABLE_PI && ! command -v pi >/dev/null; then
    log_warn "pi not installed"
  fi
  if bootstrap_config_bool ENABLE_CODEX && ! command -v codex >/dev/null; then
    log_warn "codex not installed"
  fi
  if bootstrap_config_bool ENABLE_CLAUDE && ! command -v claude >/dev/null; then
    log_warn "claude not installed"
  fi
  return 0
}

mod_60_ai_rollback() {
  :
}