    #!/bin/bash
    # ekko_bootstrap_logic.sh
    # Performs the core setup steps for Project Ekko.
    # Assumes it's run by the main init script as the target user,
    # with necessary variables (EKKO_PROJECT_DIR, EKKO_PYTHON_CMD, EKKO_TEMPLATES_DIR) exported
    # or passed as arguments (using exported variables for simplicity here).

    set -e # Exit on first error

    echo "  --- Starting Ekko Bootstrap Logic ---"

    # --- 0. Verify Environment Variables ---
    if [ -z "$EKKO_PROJECT_DIR" ] || [ -z "$EKKO_PYTHON_CMD" ] || [ -z "$EKKO_TEMPLATES_DIR" ]; then
        echo "  [FATAL] Required environment variables (EKKO_PROJECT_DIR, EKKO_PYTHON_CMD, EKKO_TEMPLATES_DIR) not set. Cannot proceed."
        exit 1
    fi
    if [ ! -d "$EKKO_TEMPLATES_DIR" ]; then
         echo "  [FATAL] Templates directory specified by EKKO_TEMPLATES_DIR ('${EKKO_TEMPLATES_DIR}') not found."
         exit 1
    fi

    VENV_DIR_NAME=".venv" # Consistent venv name
    PROJECT_NAME="ekko"   # Ekko's internal package name

    echo "  [Info] Ekko Target Dir: ${EKKO_PROJECT_DIR}"
    echo "  [Info] Ekko Python Cmd: ${EKKO_PYTHON_CMD}"
    echo "  [Info] Ekko Templates Dir: ${EKKO_TEMPLATES_DIR}"

    # --- 1. Create Dirs ---
    echo "  Creating Ekko standard directories..."
    mkdir -p "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/cli" \
             "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/api" \
             "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/tui" \
             "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/core" \
             "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/validation" \
             "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/orchestration" \
             "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/config" \
             "${EKKO_PROJECT_DIR}/tests/unit" \
             "${EKKO_PROJECT_DIR}/tests/integration" \
             "${EKKO_PROJECT_DIR}/tests/chaos" \
             "${EKKO_PROJECT_DIR}/scripts" \
             "${EKKO_PROJECT_DIR}/docs" \
             "${EKKO_PROJECT_DIR}/.github/workflows" \
             "${EKKO_PROJECT_DIR}/config_examples" \
        || { echo "  [FATAL] Failed to create Ekko directories."; exit 1; }
    # Create necessary __init__.py files
    touch "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/__init__.py"
    touch "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/cli/__init__.py"
    touch "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/api/__init__.py"
    touch "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/tui/__init__.py"
    touch "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/core/__init__.py"
    touch "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/validation/__init__.py"
    touch "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/orchestration/__init__.py"
    touch "${EKKO_PROJECT_DIR}/src/${PROJECT_NAME}/config/__init__.py"
    touch "${EKKO_PROJECT_DIR}/tests/__init__.py"
    touch "${EKKO_PROJECT_DIR}/tests/unit/__init__.py"
    touch "${EKKO_PROJECT_DIR}/tests/integration/__init__.py"
    touch "${EKKO_PROJECT_DIR}/tests/chaos/__init__.py" \
        || { echo "  [FATAL] Failed to create Ekko __init__.py files."; exit 1; }
    echo "  [OK] Ekko directories created."

    # --- 2. Git Init ---
    echo "  Initializing Ekko Git repository..."
    if [ -d "${EKKO_PROJECT_DIR}/.git" ]; then
        echo "    [Skipped] Ekko Git repo exists."
    else
        (cd "${EKKO_PROJECT_DIR}" && git init && git branch -M main) || { echo "  [FATAL] Ekko git init failed."; exit 1; }
        echo "    [OK] Ekko Git repo initialized."
    fi

    # --- 3. Copy Template Files ---
    echo "  Copying template files from ${EKKO_TEMPLATES_DIR}..."
    TEMPLATE_FILES=(
        "python_gitignore.template:.gitignore"
        "ekko_readme.template:README.md"
        "mit_license.template:LICENSE"
        "ekko_pyproject.template:pyproject.toml"
        "ekko_precommit.template:.pre-commit-config.yaml"
        "ekko_ci.template:.github/workflows/ci.yaml"
        "ekko_placeholder_main.template:src/ekko/main.py"
        "ekko_placeholder_cli.template:src/ekko/cli/main.py"
        "ekko_placeholder_api.template:src/ekko/api/main.py"
        "ekko_placeholder_tui.template:src/ekko/tui/main.py"
        "ekko_placeholder_config.template:src/ekko/config.py"
    )
    for item in "${TEMPLATE_FILES[@]}"; do
        TEMPLATE_NAME="${item%%:*}"
        TARGET_NAME="${item##*:}"
        TEMPLATE_PATH="${EKKO_TEMPLATES_DIR}/${TEMPLATE_NAME}"
        TARGET_PATH="${EKKO_PROJECT_DIR}/${TARGET_NAME}"
        if [ -f "$TEMPLATE_PATH" ]; then
            if [ ! -f "$TARGET_PATH" ]; then # Only copy if target doesn't exist
                echo "    Copying ${TEMPLATE_NAME} -> ${TARGET_NAME}"
                cp "$TEMPLATE_PATH" "$TARGET_PATH" || echo "    [Warning] Failed copy ${TEMPLATE_NAME}"
            else
                 echo "    [Skipped] Target file ${TARGET_NAME} already exists."
            fi
        else
            echo "    [Warning] Template file ${TEMPLATE_NAME} not found in ${EKKO_TEMPLATES_DIR}. Skipping."
        fi
    done
    # Create example .env file
    EXAMPLE_ENV_DEST="${EKKO_PROJECT_DIR}/config_examples/.env.example"
     if [ ! -f "$EXAMPLE_ENV_DEST" ]; then
        echo "    Creating config_examples/.env.example..."
        mkdir -p "${EKKO_PROJECT_DIR}/config_examples"
        cat << 'EOF' > "$EXAMPLE_ENV_DEST"

Example .env file for Ekko Configuration
Copy this to project_root/config/.env and fill in values or set environment variables
EKKO_LOG_LEVEL=DEBUG
EKKO_DEFAULT_LLM_PROVIDER=claude
EKKO_API_PORT=9999
API Keys (Store securely, e.g., OS keychain or Vault, DO NOT COMMIT .env file)
OPENAI_API_KEY="sk-..."
ANTHROPIC_API_KEY="sk-ant-..."
GEMINI_API_KEY="..."

EOF
else echo "    [Skipped] Target file config_examples/.env.example already exists."
fi
echo "  [OK] Template files processed."

# --- 4. Setup Venv & Dependencies ---
echo "  Setting up Ekko venv using ${EKKO_PYTHON_CMD}..."
EKKO_VENV_PATH="${EKKO_PROJECT_DIR}/${VENV_DIR_NAME}"
if [ ! -d "$EKKO_VENV_PATH" ]; then
    # Use virtualenv if available (more robust), fallback to venv module
    if command -v virtualenv &> /dev/null; then
         echo "    Using 'virtualenv' package..."
         virtualenv -p "$EKKO_PYTHON_CMD" "$EKKO_VENV_PATH" || { echo "  [FATAL] virtualenv command failed."; exit 1; }
    else
         echo "    Using 'python -m venv' module..."
         "$EKKO_PYTHON_CMD" -m venv "$EKKO_VENV_PATH" || { echo "  [FATAL] venv module failed."; exit 1; }
         sleep 1 # Add delay after module creation
    fi
else echo "    Existing Ekko venv found."; fi

EKKO_VENV_PYTHON="${EKKO_VENV_PATH}/bin/python" # virtualenv should create this link
if [ ! -f "$EKKO_VENV_PYTHON" ]; then echo "  [FATAL] Ekko venv python missing after creation."; ls -l "${EKKO_VENV_PATH}/bin"; exit 1; fi
chmod +x "$EKKO_VENV_PYTHON" || echo "  [Warn] Failed chmod Ekko venv Python."
echo "  Installing Ekko base + dev dependencies..."
"$EKKO_VENV_PYTHON" -m pip install --upgrade pip || exit 1
"$EKKO_VENV_PYTHON" -m pip install -e "${EKKO_PROJECT_DIR}[dev]" || { echo "  [FATAL] Failed install Ekko deps."; exit 1; }
echo "  [OK] Ekko dependencies installed."

# --- 5. Setup Pre-commit ---
echo "  Setting up Ekko pre-commit hooks..."
EKKO_VENV_PRECOMMIT="${EKKO_VENV_PATH}/bin/pre-commit"
if [ ! -f "$EKKO_VENV_PRECOMMIT" ]; then echo "  [FATAL] Ekko pre-commit missing."; exit 1; fi
(cd "${EKKO_PROJECT_DIR}" && "$EKKO_VENV_PRECOMMIT" install) || { echo "  [Error] Failed install Ekko pre-commit hooks."; exit 1; }
echo "  [OK] Ekko Pre-commit setup complete."

# --- 6. Initial Commit ---
echo "  Creating Initial Ekko Git commit..."
(cd "${EKKO_PROJECT_DIR}" && \
 if [ -n "$(git status --porcelain)" ]; then \
    git add . ; \
    git commit --no-verify -m "feat: Initial project scaffold for Ekko (Python/FastAPI/Textual)"; \
    echo "    [OK] Initial commit created." ; \
 else echo "    [Skipped] No changes for initial commit."; fi \
) || echo "  [Warn] Ekko initial commit failed."

echo "--- Ekko Bootstrap Logic Complete ---"
exit 0
