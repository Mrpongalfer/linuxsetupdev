#!/bin/bash
# nexus_env_init.sh - v1.8: Target Py3.11 for Ekko, use modular scripts
# Comprehensive setup script for Apex Development Environment on Ubuntu/Pop!_OS.

set -e
echo "--- Starting Apex Nexus Environment Initialization (v1.8) ---"
echo "Timestamp: $(date --iso-8601=seconds)"
echo "[WARNING] This script requires sudo privileges."

# --- 0. Define Project Path & Variables ---
if [ -n "$SUDO_USER" ]; then ORIGINAL_USER="$SUDO_USER"; else ORIGINAL_USER=$(logname); fi
ORIGINAL_HOME=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6)
if [ -z "$ORIGINAL_HOME" ] || [ ! -d "$ORIGINAL_HOME" ]; then echo "[FATAL] Cannot determine home dir."; exit 1; fi

# Both Scribe and Ekko will target Python 3.11 now
PYTHON_VERSION_TARGET="3.11"; PYTHON_CMD_TARGET="python${PYTHON_VERSION_TARGET}"
PROJECTS_BASE_DIR="${ORIGINAL_HOME}/Projects"
SCRIBE_PROJECT_DIR="${PROJECTS_BASE_DIR}/scribe_agent"; SCRIBE_AGENT_CODE_PATH="${SCRIBE_PROJECT_DIR}/scribe_agent.py"
EKKO_PROJECT_DIR="${PROJECTS_BASE_DIR}/ekko"; EKKO_PROJECT_NAME="ekko"
SETUP_REPO_URL="https://github.com/mrpongalfer/linuxsetupdev.git"; SETUP_REPO_CLONE_DIR="${ORIGINAL_HOME}/.nexus-setup-scripts"
VENV_DIR_NAME=".venv"
echo "[Info] Operating for user: ${ORIGINAL_USER} (Home: ${ORIGINAL_HOME})"
echo "[Info] Target Python for Scribe & Ekko: ${PYTHON_VERSION_TARGET}"

# --- Helper ---
command_exists() { command -v "$1" >/dev/null 2>&1 ; }
if [ "$(id -u)" -eq 0 ] && [ -z "$SUDO_USER" ]; then echo "[FATAL] Run via 'sudo ./nexus_env_init.sh'."; exit 1; fi

# --- 1. Initial System Update & Prereqs ---
echo "[Step 1/9] Updating apt & core utils..."
sudo apt update > /dev/null || exit 1
sudo apt install -y git curl wget sudo software-properties-common jq || exit 1
echo "[OK] System updated & core utils checked."

# --- 2. Clone/Update Setup Scripts Repo ---
echo "[Step 2/9] Ensuring setup scripts repo (${SETUP_REPO_CLONE_DIR})..."
if [ -d "${SETUP_REPO_CLONE_DIR}/.git" ]; then echo "  Updating repo..."; (cd "${SETUP_REPO_CLONE_DIR}" && sudo -u "$ORIGINAL_USER" git pull origin main) || echo "[Warn] Pull failed.";
elif [ -d "${SETUP_REPO_CLONE_DIR}" ]; then sudo rm -rf "${SETUP_REPO_CLONE_DIR}" || exit 1; sudo -u "$ORIGINAL_USER" git clone "$SETUP_REPO_URL" "$SETUP_REPO_CLONE_DIR" || exit 1;
else sudo -u "$ORIGINAL_USER" git clone "$SETUP_REPO_URL" "$SETUP_REPO_CLONE_DIR" || exit 1; fi
SCRIBE_CODE_SRC="${SETUP_REPO_CLONE_DIR}/scripts/scribe_agent.py"; EKKO_BOOTSTRAP_SRC="${SETUP_REPO_CLONE_DIR}/scripts/ekko_bootstrap_logic.sh"
if [ ! -f "$SCRIBE_CODE_SRC" ] || [ ! -f "$EKKO_BOOTSTRAP_SRC" ]; then echo "[FATAL] Key scripts missing from ${SETUP_REPO_CLONE_DIR}."; exit 1; fi
echo "[OK] Setup scripts repo ready."

# --- 3. Ensure Target Python Version (3.11) & Venv Tools/Wheels ---
echo "[Step 3/9] Ensuring Python ${PYTHON_VERSION_TARGET} & required packages..."
PYTHON_PKGS_TO_INSTALL=()
if ! command_exists "$PYTHON_CMD_TARGET" || ! "$PYTHON_CMD_TARGET" -m venv -h &>/dev/null; then PYTHON_PKGS_TO_INSTALL+=("python${PYTHON_VERSION_TARGET}" "python${PYTHON_VERSION_TARGET}-venv"); fi
# Ensure virtualenv and wheels are installed for system python3
CORE_PY_UTILS=(virtualenv python3-pip-whl python3-setuptools-whl python3-wheel-whl)
PYTHON_PKGS_TO_INSTALL+=("${CORE_PY_UTILS[@]}")
# Remove duplicates just in case
UNIQUE_PKGS=($(printf "%s\n" "${PYTHON_PKGS_TO_INSTALL[@]}" | sort -u))
if [ ${#UNIQUE_PKGS[@]} -ne 0 ]; then
     echo "  Adding deadsnakes PPA (if needed for ${PYTHON_VERSION_TARGET})..."; sudo add-apt-repository ppa:deadsnakes/ppa -y || exit 1; sudo apt update > /dev/null; echo "  Installing/Verifying Python packages: ${UNIQUE_PKGS[*]}"; sudo apt install -y "${UNIQUE_PKGS[@]}" || exit 1;
fi
if ! command_exists "$PYTHON_CMD_TARGET" || ! command_exists "virtualenv" ; then echo "[FATAL] Python ${PYTHON_VERSION_TARGET} or virtualenv setup check failed."; exit 1; fi
echo "[OK] Required Python ${PYTHON_VERSION_TARGET} & utilities confirmed."

# --- 4. Install Standard Apt TUI/CLI Tools ---
echo "[Step 4/9] Installing TUI/CLI tools via apt..."
APT_TOOLS=(ranger lnav tig jq fzf ripgrep bat tmux build-essential libffi-dev zlib1g-dev libssl-dev pkg-config btop)
sudo apt install -y "${APT_TOOLS[@]}" || echo "[Warning] Failed install some apt tools."
if ! command_exists bat && command_exists batcat; then sudo ln -sfn "$(which batcat)" /usr/local/bin/bat || echo "[Warn] Failed symlink bat."; fi
echo "[OK] Standard apt tools installed."

# --- 5. Install Other Tools (PPA/Binary) ---
echo "[Step 5/9] Installing lazygit, lazydocker, yq..."
# (Logic for lazygit, lazydocker, yq remains the same as v1.6)
if ! command_exists lazygit; then echo "  Installing lazygit (PPA)..."; sudo add-apt-repository ppa:lazygit-team/release -y && sudo apt update >/dev/null && sudo apt install -y lazygit || echo "[Error] lazygit failed!"; else echo "  [OK] lazygit found."; fi
if ! command_exists lazydocker; then echo "  Installing lazydocker..."; INSTALL_DIR="/usr/local/bin"; LD_ARCH=$(uname -m); case $LD_ARCH in x86_64) LD_ARCH_GH="x86_64";; aarch64) LD_ARCH_GH="arm64";; *) echo "[F] Unspt arch."; exit 1;; esac; LD_VER=$(curl -s "https://api.github.com/repos/jesseduffield/lazydocker/releases/latest" | jq -r '.tag_name' | sed 's/^v//'); if [ -z "$LD_VER" ]; then echo "[E] No ver"; else FILE="lazydocker_${LD_VER}_Linux_${LD_ARCH_GH}.tar.gz"; URL="https://github.com/jesseduffield/lazydocker/releases/download/v${LD_VER}/${FILE}"; T_FILE=$(mktemp --suffix=.tar.gz); wget -qO "$T_FILE" "$URL" && T_DIR=$(mktemp -d) && tar -xzf "$T_FILE" -C "$T_DIR" lazydocker && sudo install -Dm 755 "${T_DIR}/lazydocker" "${INSTALL_DIR}/lazydocker" && echo "    [OK] lazydocker installed." || echo "[E] lazydocker failed."; rm -rf "$T_FILE" "$T_DIR"; fi; else echo "  [OK] lazydocker found."; fi
if ! command_exists yq; then echo "  Installing yq..."; INSTALL_DIR="/usr/local/bin"; YQ_ARCH=$(uname -m); case $YQ_ARCH in x86_64) YQ_ARCH_GH="amd64";; aarch64) YQ_ARCH_GH="arm64";; *) echo "[F] Unspt arch."; exit 1;; esac; YQ_VER=$(curl -s "https://api.github.com/repos/mikefarah/yq/releases/latest" | jq -r '.tag_name' | sed 's/^v//'); if [ -z "$YQ_VER" ]; then echo "[E] No ver"; else GITHUB_FILE="yq_linux_${YQ_ARCH_GH}"; URL="https://github.com/mikefarah/yq/releases/download/v${YQ_VER}/${GITHUB_FILE}"; T_FILE=$(mktemp); wget -qO "$T_FILE" "$URL" && sudo install -Dm 755 "$T_FILE" "${INSTALL_DIR}/yq" && echo "    [OK] yq installed." || echo "[E] yq failed."; rm -f "$T_FILE"; fi; else echo "  [OK] yq found."; fi
echo "[OK] Additional tools installed."

# --- 6. Setup Project Scribe ---
echo "[Step 6/9] Setting up Project Scribe (${SCRIBE_PROJECT_DIR})..."
sudo -u "$ORIGINAL_USER" mkdir -p "${SCRIBE_PROJECT_DIR}" || exit 1
sudo -u "$ORIGINAL_USER" cp "${SCRIBE_CODE_SRC}" "${SCRIBE_AGENT_CODE_PATH}" || exit 1
sudo -u "$ORIGINAL_USER" chmod +x "${SCRIBE_AGENT_CODE_PATH}" || exit 1
echo "  Agent code copied."
SCRIBE_VENV_PATH="${SCRIBE_PROJECT_DIR}/${VENV_DIR_NAME}"
echo "  Setting up Scribe venv using 'virtualenv' (Python ${PYTHON_VERSION_SCRIBE})..."
if [ ! -d "$SCRIBE_VENV_PATH" ]; then sudo -u "$ORIGINAL_USER" virtualenv -p "$PYTHON_CMD_SCRIBE" "$SCRIBE_VENV_PATH" || exit 1; fi
SCRIBE_VENV_PYTHON="${SCRIBE_VENV_PATH}/bin/python"
if [ ! -f "$SCRIBE_VENV_PYTHON" ]; then echo "[FATAL] Scribe venv python missing."; exit 1; fi
sudo -u "$ORIGINAL_USER" chmod +x "$SCRIBE_VENV_PYTHON" || echo "[Warn] Chmod Scribe venv Py failed."
echo "  Installing Scribe dependencies..."
sudo -u "$ORIGINAL_USER" "$SCRIBE_VENV_PYTHON" -m pip install --upgrade pip || exit 1
sudo -u "$ORIGINAL_USER" "$SCRIBE_VENV_PYTHON" -m pip install httpx requests || exit 1
echo "[OK] Project Scribe setup complete."

# --- 7. Bootstrap Project Ekko (Using PYTHON_CMD_TARGET=python3.11) ---
echo "[Step 7/9] Bootstrapping Project Ekko (${EKKO_PROJECT_DIR})..."
if [ -d "${EKKO_PROJECT_DIR}" ]; then echo "  [Skipped] Ekko project directory already exists.";
elif [ ! -f "$EKKO_BOOTSTRAP_SRC" ]; then echo "[FATAL] Ekko bootstrap script missing: ${EKKO_BOOTSTRAP_SRC}"; exit 1;
else
    echo "  Executing Ekko bootstrap logic as user ${ORIGINAL_USER} (TARGETING PYTHON ${PYTHON_VERSION_TARGET})..." # Target is now 3.11
    sudo -u "$ORIGINAL_USER" chmod +x "$EKKO_BOOTSTRAP_SRC" || echo "[Warn] Failed chmod Ekko bootstrap."
    # Execute as original user, passing PYTHON_CMD_TARGET (now python3.11)
    sudo -u "$ORIGINAL_USER" \
         env EKKO_PYTHON_CMD="$PYTHON_CMD_TARGET" \
             EKKO_PROJECT_DIR="$EKKO_PROJECT_DIR" \
             EKKO_PROJECT_NAME="$PROJECT_NAME" \
             EKKO_TEMPLATES_DIR="${SETUP_REPO_CLONE_DIR}/templates" \
         bash "$EKKO_BOOTSTRAP_SRC" \
         || { echo "[FATAL] Ekko bootstrap script failed execution."; exit 1; }
    echo "[OK] Project Ekko bootstrapped successfully (using Python ${PYTHON_VERSION_TARGET})."
fi

# --- 8. Optional: Basic tmux Configuration ---
echo "[Step 8/9] Optional: Setting up basic tmux configuration..."
TMUX_CONF="${ORIGINAL_HOME}/.tmux.conf"; TMUX_TEMPLATE="${SETUP_REPO_CLONE_DIR}/templates/tmux_config.template"
if [ ! -f "$TMUX_CONF" ] && [ -f "$TMUX_TEMPLATE" ]; then echo "  Creating ${TMUX_CONF}..."; sudo -u "$ORIGINAL_USER" cp "$TMUX_TEMPLATE" "$TMUX_CONF" || echo "[Warn] Failed copy tmux conf."; echo "[OK] Basic tmux config created."; elif [ -f "$TMUX_CONF" ]; then echo "  [Skipped] ${TMUX_CONF} exists."; else echo "  [Skipped] No tmux template."; fi

# --- 9. Final Ownership Fix & Summary ---
echo "[Step 9/9] Finalizing ownership and summary..."
echo "  Correcting ownership of ${PROJECTS_BASE_DIR}..."
# Use sudo directly as we are root
chown -R "${ORIGINAL_USER}:${ORIGINAL_USER}" "${PROJECTS_BASE_DIR}" || echo "[Warn] Failed chown on ${PROJECTS_BASE_DIR}."
if [ -d "$SETUP_REPO_CLONE_DIR" ]; then chown -R "${ORIGINAL_USER}:${ORIGINAL_USER}" "${SETUP_REPO_CLONE_DIR}"; fi # Fix ownership of clone too
echo "[OK] Ownership corrected."

echo ""
echo "--- Apex Development Environment Initialization Complete (v1.8 - Ekko Py3.11) ---"
echo "Summary:"
echo "  - Python ${PYTHON_VERSION_SCRIBE} & Python ${PYTHON_VERSION_EKKO} installed/verified." # Both should be 3.11 now
echo "  - TUI/CLI Tools installed: btop, ranger, lazygit, lazydocker, lnav, tig, jq, yq, fzf, rg, bat, tmux"
echo "  - Project Scribe: Ready at ${SCRIBE_PROJECT_DIR} (Python ${PYTHON_VERSION_SCRIBE} venv)"
echo "  - Project Ekko: Bootstrapped at ${EKKO_PROJECT_DIR} (Python ${PYTHON_VERSION_EKKO} venv)"
echo ""
echo "RECOMMENDATION: Start new terminal session or 'source ~/.bashrc' / '.zshrc'."
echo "-----------------------------------------------------------------"

exit 0