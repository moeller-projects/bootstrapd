#!/usr/bin/env bash
# modules/60-ai.sh — Stage 5: AI tooling, run under the sandboxed `agent` account.
#
# Tools installed:
#   OpenClaw, Pi Coding Agent, Codex CLI, Claude Code, Ollama (optional)
#
# Architecture:
#   - Binaries install system-wide (or via npm/bun).
#   - Each tool runs as a systemd *user* service under the `agent` account,
#     never under admin.
#   - agent owns /srv/agent/{workspace,cache,logs,models}; symlinks to its
#     $HOME/{workspace,cache,logs,models} are created in 25-filesystem.
#   - Logs go to journald (per-user) AND /srv/agent/logs/<tool>.log.
set -Eeuo pipefail

mod_60_ai_description()
{
  echo "AI tooling: OpenClaw, Pi, Codex CLI, Claude Code (under agent account)"
}
mod_60_ai_stage()
{
  echo "5"
}
mod_60_ai_dependencies()
{
  echo "25-filesystem 50-dev 55-shell"
}

mod_60_ai_check()
{
  if bootstrap_config_bool ENABLE_PI; then
    command -v pi >/dev/null || return 1
  fi
  return 0
}

_install_user_unit()
{
  # _install_user_unit USER UNIT_NAME EXEC [WORKING_DIR]
  local user="$1" unit_name="$2" exec="$3" workdir="${4:-/srv/agent/workspace}"
  local home unit_dir unit_path uid
  home="$(getent passwd "$user" | cut -d: -f6)"
  uid="$(id -u "$user")"
  unit_dir="$home/.config/systemd/user"
  unit_path="$unit_dir/${unit_name}.service"

  if [[ -f "$unit_path" ]] && grep -qF "ExecStart=${exec}" "$unit_path"; then
    log_debug "user unit already present: $unit_name"
    return 0
  fi
  log_info "installing user unit: $unit_name for $user"
  if ((BOOTSTRAP_DRY_RUN)); then
    return 0
  fi

  ensure_directory "$unit_dir" 0700 "$user:$user"

  cat >"$unit_path" <<EOF
[Unit]
Description=BootstrapX managed: ${unit_name}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${workdir}
ExecStart=${exec}
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF
  chmod 0644 "$unit_path"
  bootstrap_chown_if_root -- "$user:$user" "$unit_path"

  # Reload as that user, ignoring errors from a missing runtime dir.
  if ((EUID == 0)); then
    mkdir -p "/run/user/${uid}" 2>/dev/null || true
    chown "$user:$user" "/run/user/${uid}" 2>/dev/null || true
    su - "$user" -s /bin/bash -c "XDG_RUNTIME_DIR=/run/user/${uid} systemctl --user daemon-reload" 2>/dev/null || true
  fi
}

mod_60_ai_install()
{
  local agent="${AGENT_USER:-agent}"

  # ---- OpenClaw ----
  if bootstrap_config_bool ENABLE_OPENCLAW; then
    if ! command -v openclaw >/dev/null && [[ ! -d /opt/openclaw ]]; then
      log_info "installing OpenClaw"
      if ((!BOOTSTRAP_DRY_RUN)); then
        ensure_directory /opt/openclaw 0755 root:root
        if ! git clone --depth 1 https://github.com/openclaw/openclaw.git /opt/openclaw 2>/dev/null; then
          log_warn "openclaw clone failed; install manually to /opt/openclaw"
        fi
        if [[ -f /opt/openclaw/install.sh ]]; then
          bash /opt/openclaw/install.sh || log_warn "openclaw install.sh failed"
        fi
      fi
    fi
  fi

  # ---- Pi Coding Agent ----
  if bootstrap_config_bool ENABLE_PI; then
    if ! command -v pi >/dev/null 2>&1; then
      log_info "installing Pi Coding Agent"
      if ((!BOOTSTRAP_DRY_RUN)); then
        if curl --fail --location --silent --show-error \
          --connect-timeout 15 --max-time 300 \
          https://pi.dev/install.sh | bash 2>/dev/null; then
          # Move from ~/.local/bin to /usr/local/bin so the agent user can find it
          # without inheriting root's PATH.
          if [[ -f "$HOME/.local/bin/pi" ]]; then
            install -m 0755 "$HOME/.local/bin/pi" /usr/local/bin/pi
          elif [[ -f /root/.local/bin/pi ]]; then
            install -m 0755 /root/.local/bin/pi /usr/local/bin/pi
          fi
        else
          log_warn "pi install failed"
        fi
      fi
    fi
  fi

  # ---- Codex CLI (npm) ----
  if bootstrap_config_bool ENABLE_CODEX; then
    if ! command -v codex >/dev/null 2>&1 && command -v npm >/dev/null; then
      log_info "installing Codex CLI"
      if ((!BOOTSTRAP_DRY_RUN)); then
        npm install -g @openai/codex 2>/dev/null ||
          log_warn "codex npm install failed; install manually"
      fi
    fi
  fi

  # ---- Claude Code (npm) ----
  if bootstrap_config_bool ENABLE_CLAUDE; then
    if ! command -v claude >/dev/null 2>&1 && command -v npm >/dev/null; then
      log_info "installing Claude Code"
      if ((!BOOTSTRAP_DRY_RUN)); then
        npm install -g @anthropic-ai/claude-code 2>/dev/null ||
          log_warn "claude npm install failed; install manually"
      fi
    fi
  fi

  # ---- Ollama (optional local LLM server) ----
  if bootstrap_config_bool ENABLE_OLLAMA; then
    if ! command -v ollama >/dev/null 2>&1; then
      log_info "installing Ollama"
      if ((!BOOTSTRAP_DRY_RUN)); then
        if ! curl --fail --location --silent --show-error \
          --connect-timeout 15 --max-time 600 \
          https://ollama.com/install.sh | bash 2>/dev/null; then
          log_warn "ollama install failed"
        fi
        ensure_service_enabled ollama
      fi
    fi
  fi

  # ---- systemd user services under agent ----
  if user_exists "$agent" && ((EUID == 0)); then
    if command -v pi >/dev/null; then
      _install_user_unit "$agent" pi-agent "/usr/local/bin/pi --loop" /srv/agent/workspace
    fi
    if command -v codex >/dev/null; then
      _install_user_unit "$agent" codex-agent "/usr/local/bin/codex --auto" /srv/agent/workspace
    fi
    if command -v claude >/dev/null; then
      _install_user_unit "$agent" claude-agent "/usr/local/bin/claude --auto" /srv/agent/workspace
    fi
    if command -v ollama >/dev/null; then
      _install_user_unit "$agent" ollama "/usr/local/bin/ollama serve" /srv/agent/models
    fi

    # Enable lingering so the agent's services start without an open session.
    if command -v loginctl >/dev/null; then
      loginctl enable-linger "$agent" 2>/dev/null || true
    fi
  fi
}

mod_60_ai_validate()
{
  if bootstrap_config_bool ENABLE_PI && ! command -v pi >/dev/null; then
    log_warn "pi not installed"
  fi
  if bootstrap_config_bool ENABLE_CODEX && ! command -v codex >/dev/null; then
    log_warn "codex not installed"
  fi
  if bootstrap_config_bool ENABLE_CLAUDE && ! command -v claude >/dev/null; then
    log_warn "claude not installed"
  fi
  if bootstrap_config_bool ENABLE_OPENCLAW && [[ ! -d /opt/openclaw ]] && ! command -v openclaw >/dev/null; then
    log_warn "openclaw not installed"
  fi
  return 0
}

mod_60_ai_rollback()
{
  local agent="${AGENT_USER:-agent}"
  if user_exists "$agent"; then
    local home
    home="$(getent passwd "$agent" | cut -d: -f6)"
    rm -f "$home/.config/systemd/user"/{pi-agent,codex-agent,claude-agent,ollama}.service 2>/dev/null || true
  fi
}
