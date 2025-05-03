#!/bin/bash
# ekko_bootstrap_logic.sh - v1.1: Target Python 3.11
# Performs the core setup steps for Project Ekko.
# Assumes it's run by the main init script as the target user,
# with necessary variables (EKKO_PROJECT_DIR, EKKO_PYTHON_CMD=python3.11, EKKO_TEMPLATES_DIR) exported.

set -e
echo "  --- Starting Ekko Bootstrap Logic (Python 3.11 Target) ---"
# Verify Environment Variables passed from parent script
if [ -z "$EKKO_PROJECT_DIR" ] || [ -z "$EKKO_PYTHON_CMD" ] || [ -z "$EKKO_TEMPLATES_DIR" ]; then echo "  [FATAL] Required env vars not set."; exit 1; fi
if [[ "$EKKO_PYTHON_CMD" != *"python3.11"* ]]; then echo "  [FATAL] Incorrect Python command passed: $EKKO_PYTHON_CMD. Expected python3.11."; exit 1; fi
if [ ! -d "$EKKO_TEMPLATES_DIR" ]; then echo "  [FATAL] Templates dir not found: ${EKKO_TEMPLATES_DIR}"; exit 1; fi

VENV_DIR_NAME=".venv"; PROJECT_NAME="ekko"
echo "  [Info] Ekko Target Dir: ${EKKO_PROJECT_DIR}"; echo "  [Info] Ekko Python Cmd: ${EKKO_PYTHON_CMD}"; echo "  [Info] Ekko Templates Dir: ${EKKO_TEMPLATES_DIR}"

# --- Create Dirs ---
echo "  Creating Ekko standard directories..."
mkdir -p "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/cli" "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/api" "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/tui" "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/core" "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/validation" "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/orchestration" "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/config" "${EKKO_PROJECT_DIR}/tests/unit" "${EKKO_PROJECT_DIR}/tests/integration" "${EKKO_PROJECT_DIR}/tests/chaos" "${EKKO_PROJECT_DIR}/scripts" "${EKKO_PROJECT_DIR}/docs" ".github/workflows" "config_examples" || exit 1
touch "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/__init__.py" "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/cli/__init__.py" "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/api/__init__.py" "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/tui/__init__.py" "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/core/__init__.py" "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/validation/__init__.py" "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/orchestration/__init__.py" "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/config/__init__.py" "${EKKO_PROJECT_DIR}/tests/__init__.py" "${EKKO_PROJECT_DIR}/tests/unit/__init__.py" "${EKKO_PROJECT_DIR}/tests/integration/__init__.py" "${EKKO_PROJECT_DIR}/tests/chaos/__init__.py" || exit 1
echo "  [OK] Ekko directories created."

# --- Git Init ---
echo "  Initializing Ekko Git repository..."
if [ ! -d "${EKKO_PROJECT_DIR}/.git" ]; then (cd "${EKKO_PROJECT_DIR}" && git init && git branch -M main) || exit 1; else echo "    [Skipped] Git repo exists."; fi

# --- Copy Template Files ---
echo "  Copying template files from ${EKKO_TEMPLATES_DIR}..."
TEMPLATE_FILES=("python_gitignore.template:.gitignore" "ekko_readme.template:README.md" "mit_license.template:LICENSE" "ekko_pyproject.template:pyproject.toml" "ekko_precommit.template:.pre-commit-config.yaml" "ekko_ci.template:.github/workflows/ci.yaml" "ekko_placeholder_main.template:src/ekko/main.py" "ekko_placeholder_cli.template:src/ekko/cli/main.py" "ekko_placeholder_api.template:src/ekko/api/main.py" "ekko_placeholder_tui.template:src/ekko/tui/main.py" "ekko_placeholder_config.template:src/ekko/config.py")
for item in "${TEMPLATE_FILES[@]}"; do TP="${item%%:*}"; TN="${item##*:}"; TP_PATH="${EKKO_TEMPLATES_DIR}/${TP}"; TG_PATH="${EKKO_PROJECT_DIR}/${TN}"; if [ -f "$TP_PATH" ]; then if [ ! -f "$TG_PATH" ]; then echo "    Copying ${TP} -> ${TN}"; cp "$TP_PATH" "$TG_PATH" || echo "[Warn] Copy ${TP} fail"; fi; else echo "[Warn] Template ${TP} miss"; fi; done
EG_ENV_DEST="${EKKO_PROJECT_DIR}/config_examples/.env.example"; if [ ! -f "$EG_ENV_DEST" ]; then echo "    Creating ${EG_ENV_DEST}..."; mkdir -p "${EKKO_PROJECT_DIR}/config_examples"; echo -e "# Example .env\n# EKKO_LOG_LEVEL=DEBUG" > "$EG_ENV_DEST"; fi
echo "  [OK] Template files processed."

# --- Setup Venv & Dependencies ---
echo "  Setting up Ekko venv using ${EKKO_PYTHON_CMD}..."
EKKO_VENV_PATH="${EKKO_PROJECT_DIR}/${VENV_DIR_NAME}"
if [ ! -d "$EKKO_VENV_PATH" ]; then virtualenv -p "$EKKO_PYTHON_CMD" "$EKKO_VENV_PATH" || exit 1; fi
EKKO_VENV_PYTHON="${EKKO_VENV_PATH}/bin/python"
if [ ! -f "$EKKO_VENV_PYTHON" ]; then echo "[FATAL] Ekko venv python missing."; exit 1; fi
chmod +x "$EKKO_VENV_PYTHON" || echo "[Warn] Failed chmod Ekko venv Python."
echo "  Installing Ekko base + dev dependencies..."
"$EKKO_VENV_PYTHON" -m pip install --upgrade pip || exit 1
"$EKKO_VENV_PYTHON" -m pip install -e "${EKKO_PROJECT_DIR}[dev]" || { echo "  [FATAL] Failed install Ekko deps."; exit 1; }
echo "  [OK] Ekko dependencies installed."

# --- Setup Pre-commit ---
echo "  Setting up Ekko pre-commit hooks..."
EKKO_VENV_PRECOMMIT="${EKKO_VENV_PATH}/bin/pre-commit"
if [ ! -f "$EKKO_VENV_PRECOMMIT" ]; then echo "[FATAL] Ekko pre-commit missing."; exit 1; fi
(cd "${EKKO_PROJECT_DIR}" && "$EKKO_VENV_PRECOMMIT" install) || { echo "  [Error] Failed install Ekko pre-commit hooks."; exit 1; }
echo "  [OK] Ekko Pre-commit setup complete."

# --- Initial Commit ---
echo "  Creating Initial Ekko Git commit..."
(cd "${EKKO_PROJECT_DIR}" && if [ -n "$(git status --porcelain)" ]; then git add .; git commit --no-verify -m "feat: Initial Ekko project scaffold (Python 3.11)"; else echo "  No changes."; fi ) || echo "[Warn] Ekko initial commit failed."

echo "--- Ekko Bootstrap Logic Complete ---"
exit 0