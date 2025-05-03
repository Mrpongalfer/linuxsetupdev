#!/bin/bash
# nexus_env_init.sh - v2.0: Orchestrator for Apex Development Environment Setup
# Clones this repo locally, installs tools, sets up Scribe & Ekko using modular components.
# Requires sudo privileges. Should be run as a non-root user with sudo rights.

set -e # Exit on first error
SCRIPT_VERSION="2.0"
echo "--- Starting Apex Nexus Environment Initialization Orchestrator (v${SCRIPT_VERSION}) ---"
echo "Timestamp: $(date --iso-8601=seconds)"
echo "[WARNING] This script requires sudo privileges for system package management."
echo "          It will prompt for your password when needed."
# read -p "Press Enter to continue, or Ctrl+C to abort..." # Removed for less interaction

# --- 0. Define Paths & Variables ---
# Try to get the original user even when run with sudo
if [ -n "$SUDO_USER" ]; then ORIGINAL_USER="$SUDO_USER"; else ORIGINAL_USER=$(logname); fi
ORIGINAL_HOME=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6)
if [ -z "$ORIGINAL_HOME" ] || [ ! -d "$ORIGINAL_HOME" ]; then
    echo "[FATAL] Could not reliably determine original user's home directory: '$ORIGINAL_HOME'. Exiting."
    exit 1
fi

PYTHON_VERSION_EKKO="3.12"; PYTHON_CMD_EKKO="python${PYTHON_VERSION_EKKO}"
PYTHON_VERSION_SCRIBE="3.11"; PYTHON_CMD_SCRIBE="python${PYTHON_VERSION_SCRIBE}"

PROJECTS_BASE_DIR="${ORIGINAL_HOME}/Projects" # Standard location for user projects
SCRIBE_PROJECT_DIR="${PROJECTS_BASE_DIR}/scribe_agent"
EKKO_PROJECT_DIR="${PROJECTS_BASE_DIR}/ekko"

SETUP_REPO_URL="https://github.com/mrpongalfer/linuxsetupdev.git" # URL of this repo
# Clone setup repo to a hidden dir in user's home for easy access/updates
SETUP_REPO_CLONE_DIR="${ORIGINAL_HOME}/.nexus-setup-scripts"

VENV_DIR_NAME=".venv"

echo "[Info] Operating for user: ${ORIGINAL_USER} (Home: ${ORIGINAL_HOME})"
echo "[Info] Base Project Dir: ${PROJECTS_BASE_DIR}"
echo "[Info] Setup Script Repo: ${SETUP_REPO_URL}"
echo "[Info] Local Setup Clone: ${SETUP_REPO_CLONE_DIR}"
echo "[Info] Target Python: Ekko=${PYTHON_VERSION_EKKO}, Scribe=${PYTHON_VERSION_SCRIBE}"

# --- Helper Function ---
command_exists() { command -v "$1" >/dev/null 2>&1 ; }

# Ensure script is not run as root directly (needs SUDO_USER)
if [ "$(id -u)" -eq 0 ] && [ -z "$SUDO_USER" ]; then
   echo "[FATAL] Please run this script using 'sudo ./nexus_env_init.sh', not directly as root."
   exit 1
fi

# --- 1. Initial System Update & Prereqs ---
echo
echo "[Step 1/9] Updating package list and ensuring core utils..."
sudo apt update || { echo "[FATAL] Initial apt update failed."; exit 1; }
sudo apt install -y git curl wget sudo software-properties-common jq || { echo "[FATAL] Failed install core utils."; exit 1; }
echo "[OK] System updated and core utils checked."

# --- 2. Clone/Update Setup Scripts Repo ---
echo
echo "[Step 2/9] Ensuring local copy of setup scripts (${SETUP_REPO_CLONE_DIR})..."
# Run git commands as the original user
if [ -d "${SETUP_REPO_CLONE_DIR}/.git" ]; then
    echo "  Updating existing setup scripts repo..."
    # Pull changes if repo exists
    sudo -u "$ORIGINAL_USER" git -C "${SETUP_REPO_CLONE_DIR}" pull origin main || echo "[Warning] Failed to update setup scripts repo. Using local copy."
elif [ -d "${SETUP_REPO_CLONE_DIR}" ]; then
     # Directory exists but isn't a git repo - attempt cleanup
     echo "  Non-git directory found at ${SETUP_REPO_CLONE_DIR}. Attempting removal..."
     rm -rf "${SETUP_REPO_CLONE_DIR}" || { echo "[FATAL] Failed to remove existing non-git directory at ${SETUP_REPO_CLONE_DIR}. Please remove manually."; exit 1; }
     echo "  Cloning setup scripts repo..."
     sudo -u "$ORIGINAL_USER" git clone "$SETUP_REPO_URL" "$SETUP_REPO_CLONE_DIR" || { echo "[FATAL] Failed to clone setup repo."; exit 1; }
else
    echo "  Cloning setup scripts repo..."
    sudo -u "$ORIGINAL_USER" git clone "$SETUP_REPO_URL" "$SETUP_REPO_CLONE_DIR" || { echo "[FATAL] Failed to clone setup repo."; exit 1; }
fi
# Verify key scripts exist in the clone
SCRIBE_CODE_SRC="${SETUP_REPO_CLONE_DIR}/scripts/scribe_agent.py"
EKKO_BOOTSTRAP_SRC="${SETUP_REPO_CLONE_DIR}/scripts/ekko_bootstrap_logic.sh"
if [ ! -f "$SCRIBE_CODE_SRC" ] || [ ! -f "$EKKO_BOOTSTRAP_SRC" ]; then
    echo "[FATAL] Key scripts (scribe_agent.py, ekko_bootstrap_logic.sh) missing from cloned setup repo at ${SETUP_REPO_CLONE_DIR}. Ensure they were pushed to GitHub."
    exit 1
fi
echo "[OK] Setup scripts repository ready at ${SETUP_REPO_CLONE_DIR}"

# --- 3. Ensure Target Python Versions ---
echo
echo "[Step 3/9] Ensuring required Python versions (${PYTHON_VERSION_SCRIBE}+, ${PYTHON_VERSION_EKKO}) via PPA..."
PYTHON_PKGS_TO_INSTALL=()
# Check for Python 3.11 (for Scribe)
if ! command_exists "$PYTHON_CMD_SCRIBE" || ! "$PYTHON_CMD_SCRIBE" -m venv -h &> /dev/null; then
    PYTHON_PKGS_TO_INSTALL+=("python${PYTHON_VERSION_SCRIBE}" "python${PYTHON_VERSION_SCRIBE}-venv")
fi
# Check for Python 3.12 (for Ekko)
if ! command_exists "$PYTHON_CMD_EKKO" || ! "$PYTHON_CMD_EKKO" -m venv -h &> /dev/null; then
    PYTHON_PKGS_TO_INSTALL+=("python${PYTHON_VERSION_EKKO}" "python${PYTHON_VERSION_EKKO}-venv")
fi

if [ ${#PYTHON_PKGS_TO_INSTALL[@]} -ne 0 ]; then
    echo "  Adding deadsnakes PPA (required for specified Python versions)..."
    sudo add-apt-repository ppa:deadsnakes/ppa -y || { echo "[FATAL] Failed add deadsnakes PPA."; exit 1; }
    echo "  Updating package list after adding PPA..."
    sudo apt update || echo "[Warning] apt update after PPA failed."
    echo "  Installing required Python versions: ${PYTHON_PKGS_TO_INSTALL[*]}"
    sudo apt install -y "${PYTHON_PKGS_TO_INSTALL[@]}" || { echo "[FATAL] Failed install Python version(s)."; exit 1; }
    echo "  [OK] Required Python versions installed via PPA."
else
    echo "  [OK] Required Python versions (${PYTHON_CMD_SCRIBE}, ${PYTHON_CMD_EKKO}) appear present and functional."
fi
# Final verification
if ! command_exists "$PYTHON_CMD_SCRIBE" || ! "$PYTHON_CMD_SCRIBE" -m venv -h &>/dev/null ; then echo "[FATAL] Python ${PYTHON_VERSION_SCRIBE} setup check failed."; exit 1; fi
if ! command_exists "$PYTHON_CMD_EKKO" || ! "$PYTHON_CMD_EKKO" -m venv -h &>/dev/null ; then echo "[FATAL] Python ${PYTHON_VERSION_EKKO} setup check failed."; exit 1; fi
echo "[OK] Required Python versions confirmed functional."

# --- 4. Install System Packages for Tools ---
echo
echo "[Step 4/9] Installing TUI/CLI system packages via apt..."
# virtualenv needed as robust venv creator
APT_TOOLS=(ranger lnav tig jq fzf ripgrep bat tmux build-essential libffi-dev zlib1g-dev libssl-dev pkg-config btop virtualenv)
sudo apt install -y "${APT_TOOLS[@]}" || echo "[Warning] Failed to install some standard apt tools. Check logs."
if ! command_exists bat && command_exists batcat; then sudo ln -sfn "$(which batcat)" /usr/local/bin/bat || echo "[Warn] Failed symlink bat."; fi
echo "[OK] Standard apt tools installed/verified."

# --- 5. Install Other Tools (PPA/Binary) ---
echo
echo "[Step 5/9] Installing lazygit, lazydocker, yq..."
# lazygit (PPA)
if ! command_exists lazygit; then echo "  Installing lazygit (PPA)..."; sudo add-apt-repository ppa:lazygit-team/release -y && sudo apt update && sudo apt install -y lazygit || echo "[Error] Failed lazygit install!"; else echo "  [OK] lazygit found."; fi
# lazydocker (Binary)
if ! command_exists lazydocker; then echo "  Installing lazydocker binary..."; INSTALL_DIR="/usr/local/bin"; LD_ARCH=$(uname -m); case $LD_ARCH in x86_64) LD_ARCH_GH="x86_64";; aarch64) LD_ARCH_GH="arm64";; *) echo "[ERROR] Unspt arch."; exit 1;; esac; LD_VER=$(curl -s "https://api.github.com/repos/jesseduffield/lazydocker/releases/latest" | jq -r '.tag_name' | sed 's/^v//'); if [ -z "$LD_VER" ]; then echo "[Error] Failed get lazygit version"; else GITHUB_FILE="lazydocker_${LD_VER}_Linux_${LD_ARCH_GH}.tar.gz"; GITHUB_URL="https://github.com/jesseduffield/lazydocker/releases/download/v${LD_VER}/${GITHUB_FILE}"; T_FILE=$(mktemp --suffix=.tar.gz); wget -qO "$T_FILE" "$GITHUB_URL" && T_DIR=$(mktemp -d) && tar -xzf "$T_FILE" -C "$T_DIR" lazydocker && sudo install -Dm 755 "${T_DIR}/lazydocker" "${INSTALL_DIR}/lazydocker" && echo "    [OK] lazydocker installed." || echo "[Error] lazydocker install failed."; rm -rf "$T_FILE" "$T_DIR"; fi; else echo "  [OK] lazydocker found."; fi
# yq (Binary)
if ! command_exists yq; then echo "  Installing yq binary..."; INSTALL_DIR="/usr/local/bin"; YQ_ARCH=$(uname -m); case $YQ_ARCH in x86_64) YQ_ARCH_GH="amd64";; aarch64) YQ_ARCH_GH="arm64";; *) echo "[ERROR] Unspt arch."; exit 1;; esac; YQ_VER=$(curl -s "https://api.github.com/repos/mikefarah/yq/releases/latest" | jq -r '.tag_name' | sed 's/^v//'); if [ -z "$YQ_VER" ]; then echo "[Error] Failed get yq version"; else GITHUB_FILE="yq_linux_${YQ_ARCH_GH}"; GITHUB_URL="https://github.com/mikefarah/yq/releases/download/v${YQ_VER}/${GITHUB_FILE}"; T_FILE=$(mktemp); wget -qO "$T_FILE" "$GITHUB_URL" && sudo install -Dm 755 "$T_FILE" "${INSTALL_DIR}/yq" && echo "    [OK] yq installed." || echo "[Error] yq install failed."; rm -f "$T_FILE"; fi; else echo "  [OK] yq found."; fi
echo "[OK] Additional tools installed/verified."

# --- 6. Setup Project Scribe ---
echo
echo "[Step 6/9] Setting up Project Scribe (${SCRIBE_PROJECT_DIR})..."
# Create directory owned by original user
sudo -u "$ORIGINAL_USER" mkdir -p "${SCRIBE_PROJECT_DIR}" || { echo "[FATAL] Failed create Scribe dir."; exit 1; }
# Copy agent code from cloned setup repo
if [ ! -f "$SCRIBE_CODE_SRC" ]; then echo "[FATAL] Scribe agent source missing."; exit 1; fi
sudo -u "$ORIGINAL_USER" cp "$SCRIBE_CODE_SRC" "${SCRIBE_AGENT_CODE_PATH}" || { echo "[FATAL] Failed copy Scribe code."; exit 1; }
sudo -u "$ORIGINAL_USER" chmod +x "${SCRIBE_AGENT_CODE_PATH}" || { echo "[FATAL] Failed chmod Scribe agent."; exit 1; }
echo "  Agent code copied."
# Create venv as original user using Python 3.11+
SCRIBE_VENV_PATH="${SCRIBE_PROJECT_DIR}/${VENV_DIR_NAME}"
echo "  Setting up Scribe venv using ${PYTHON_CMD_SCRIBE}..."
if [ ! -d "$SCRIBE_VENV_PATH" ]; then
    sudo -u "$ORIGINAL_USER" virtualenv -p "$PYTHON_CMD_SCRIBE" "$SCRIBE_VENV_PATH" || { echo "[FATAL] Failed create Scribe venv (virtualenv)."; exit 1; }
fi
SCRIBE_VENV_PYTHON="${SCRIBE_VENV_PATH}/bin/python"
if [ ! -f "$SCRIBE_VENV_PYTHON" ]; then echo "[FATAL] Scribe venv python missing."; exit 1; fi
sudo -u "$ORIGINAL_USER" chmod +x "$SCRIBE_VENV_PYTHON" || echo "[Warning] Failed chmod Scribe venv Python."
echo "  Installing Scribe dependencies (httpx, requests)..."
sudo -u "$ORIGINAL_USER" "$SCRIBE_VENV_PYTHON" -m pip install --upgrade pip || exit 1
sudo -u "$ORIGINAL_USER" "$SCRIBE_VENV_PYTHON" -m pip install httpx requests || exit 1
echo "[OK] Project Scribe Python environment setup complete."

# --- 7. Bootstrap Project Ekko ---
echo
echo "[Step 7/9] Bootstrapping Project Ekko (${EKKO_PROJECT_DIR})..."
if [ -d "${EKKO_PROJECT_DIR}" ]; then
    echo "  [Skipped] Ekko project directory already exists."
elif [ ! -f "$EKKO_BOOTSTRAP_SRC" ]; then
    echo "[FATAL] Ekko bootstrap script missing: ${EKKO_BOOTSTRAP_SRC}"; exit 1;
else
    echo "  Executing Ekko bootstrap logic as user ${ORIGINAL_USER}..."
    # Ensure bootstrap script is executable
    chmod +x "$EKKO_BOOTSTRAP_SRC" || echo "[Warning] Failed chmod Ekko bootstrap script."
    # Export variables needed by the bootstrap script
    export EKKO_PYTHON_CMD="$PYTHON_CMD_EKKO"
    export EKKO_PROJECT_DIR="$EKKO_PROJECT_DIR"
    export EKKO_PROJECT_NAME="ekko" # Project name within src dir
    export EKKO_TEMPLATES_DIR="${SETUP_REPO_CLONE_DIR}/templates" # Pass templates dir
    # Execute as original user
    sudo -u "$ORIGINAL_USER" bash "$EKKO_BOOTSTRAP_SRC" || { echo "[FATAL] Ekko bootstrap script failed."; exit 1; }
    unset EKKO_PYTHON_CMD EKKO_PROJECT_DIR EKKO_PROJECT_NAME EKKO_TEMPLATES_DIR # Clean up env
    echo "[OK] Project Ekko bootstrapped successfully."
fi

# --- 8. Optional: Basic tmux Configuration ---
echo
echo "[Step 8/9] Optional: Applying basic tmux configuration..."
TMUX_CONF="${ORIGINAL_HOME}/.tmux.conf"
TMUX_TEMPLATE="${SETUP_REPO_CLONE_DIR}/templates/tmux_config.template"
if [ ! -f "$TMUX_CONF" ] && [ -f "$TMUX_TEMPLATE" ]; then
    echo "  Creating ${TMUX_CONF} from template..."
    sudo -u "$ORIGINAL_USER" cp "$TMUX_TEMPLATE" "$TMUX_CONF" || echo "[Warning] Failed copy tmux config."
    echo "[OK] Basic tmux config created."
elif [ -f "$TMUX_CONF" ]; then echo "  [Skipped] ${TMUX_CONF} exists.";
else echo "  [Skipped] No tmux template found in setup repo."; fi

# --- 9. Final Summary & Ownership Fix ---
echo
echo "[Step 9/9] Finalizing and correcting ownership..."
# Ensure everything under PROJECTS_BASE_DIR is owned by the original user
if [ -d "$PROJECTS_BASE_DIR" ]; then
    chown -R "${ORIGINAL_USER}:${ORIGINAL_USER}" "${PROJECTS_BASE_DIR}" || echo "[Warning] Failed to change ownership of ${PROJECTS_BASE_DIR}. Manual 'chown -R ${ORIGINAL_USER}:${ORIGINAL_USER} ${PROJECTS_BASE_DIR}' might be needed."
fi
echo "[OK] Ownership corrected."

echo ""
echo "--- Apex Development Environment Initialization Complete ---"
echo "Installation Summary:"
echo "  - Python ${PYTHON_VERSION_EKKO} & ${PYTHON_VERSION_SCRIBE} installed."
echo "  - TUI/CLI Tools: btop++, ranger, lazygit, lazydocker, lnav, tig, jq, yq, fzf, rg, bat, tmux installed."
echo "  - Project Scribe: Ready at ${SCRIBE_PROJECT_DIR} (Python ${PYTHON_VERSION_SCRIBE} venv)"
echo "  - Project Ekko: Bootstrapped at ${EKKO_PROJECT_DIR} (Python ${PYTHON_VERSION_EKKO} venv)"
echo ""
echo "RECOMMENDATION: Start a new terminal session or source your shell profile (~/.bashrc, ~/.zshrc) for PATH updates."
echo "--------------------------------------------------------"

exit 0