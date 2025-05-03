#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# File: scripts/scribe_agent.py (within linuxsetupdev repo)
# Project Scribe: Apex Automated Validation Agent v1.0
# Corrected & Refactored - Manifested under Drake Protocol v5.0 Apex
# For The Supreme Master Architect Alix Feronti

"""
Project Scribe: Apex Automated Code Validation & Integration Agent

Executes a validation gauntlet on provided Python code artifacts.
Handles venv, dependencies, audit, format, lint, type check, AI test gen/exec,
AI review, pre-commit hooks, conditional Git commit, and JSON reporting.
"""

import argparse
import ast
import inspect
import json
import logging
import os
import re # Added import
import shlex
import shutil
import subprocess
import sys
import time
import traceback
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from typing import (Any, Callable, Dict, List, Optional, Sequence, Tuple, TypedDict,
                      Union, cast)

# --- Dependency Check ---
try:
    import httpx
    HTTP_LIB: Optional[str] = "httpx"
except ImportError:
    try:
        import requests
        HTTP_LIB = "requests"
    except ImportError:
        HTTP_LIB = None

try:
    import tomllib # Standard in Python 3.11+
except ImportError:
    # This check ensures clarity if script is run with wrong Python version
    print("FATAL ERROR: Could not import 'tomllib'. Project Scribe requires Python 3.11 or newer.", file=sys.stderr)
    sys.exit(1)

# --- Constants ---
APP_NAME: str = "Project Scribe"
APP_VERSION: str = "1.0.0"
LOG_FORMAT: str = '%(asctime)s - %(name)s - %(levelname)s - %(module)s:%(lineno)d - %(message)s'
DEFAULT_LOG_LEVEL: str = "INFO"
LOG_LEVELS: List[str] = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
DEFAULT_CONFIG_FILENAME: str = ".scribe.toml"
VENV_DIR_NAME: str = ".venv"
DEFAULT_PYTHON_VERSION: str = "3.11" # Scribe itself needs 3.11+
DEFAULT_REPORT_FORMAT: str = "json"
REPORT_FORMATS: List[str] = ["json", "text"]
DEFAULT_OLLAMA_MODEL: str = "mistral-nemo:12b-instruct-2407-q4_k_m"
DEFAULT_OLLAMA_BASE_URL: str = "http://localhost:11434" # Default assumes Ollama on same host as Scribe
SCRIBE_TEST_DIR: str = "tests/scribe_generated" # Relative to target_dir

# Type Definitions
class StepResult(TypedDict):
    name: str; status: str; start_time: str; end_time: str
    duration_seconds: float; details: Union[str, Dict[str, Any], List[Any], None]
    error_message: Optional[str]

class FinalReport(TypedDict):
    scribe_version: str; run_id: str; start_time: str; end_time: str
    total_duration_seconds: float; overall_status: str
    target_project_dir: str; target_file_relative: str; language: str
    python_version: str; commit_attempted: bool; commit_sha: Optional[str]
    steps: List[StepResult]
    audit_findings: Optional[List[Dict]]; ai_review_findings: Optional[List[Dict]]
    test_results_summary: Optional[Dict]

# --- Custom Exceptions ---
class ScribeError(Exception): pass
class ScribeConfigurationError(ScribeError): pass
class ScribeInputError(ScribeError): pass
class ScribeEnvironmentError(ScribeError): pass
class ScribeToolError(ScribeError): pass
class ScribeApiError(ScribeError): pass
class ScribeFileSystemError(ScribeError): pass

# --- Logging Setup Function ---
def setup_logging(log_level_str: str, log_file: Optional[str] = None) -> logging.Logger:
    """Configures the Python logging system for console and optional file."""
    log_level = getattr(logging, log_level_str.upper(), logging.INFO)
    root_logger = logging.getLogger()
    root_logger.setLevel(logging.DEBUG)
    for handler in root_logger.handlers[:]: root_logger.removeHandler(handler); handler.close()
    logging.Formatter.converter = time.gmtime; formatter = logging.Formatter(LOG_FORMAT + " (UTC)")
    console_handler = logging.StreamHandler(sys.stderr); console_handler.setFormatter(formatter); console_handler.setLevel(log_level); root_logger.addHandler(console_handler)
    if log_file:
        try:
            log_file_path = Path(log_file).resolve(); log_file_path.parent.mkdir(parents=True, exist_ok=True)
            file_handler = logging.FileHandler(log_file_path, mode='a', encoding='utf-8'); file_handler.setFormatter(formatter); file_handler.setLevel(logging.DEBUG)
            root_logger.addHandler(file_handler); root_logger.info(f"Console logging level: {log_level_str}. Detailed log file: {log_file_path}")
        except Exception as e: root_logger.error(f"Failed file logging to '{log_file}': {e}", exc_info=False)
    else: root_logger.info(f"Console logging level: {log_level_str}. No log file.")
    return logging.getLogger(APP_NAME)

# --- Configuration Manager ---
class ScribeConfig:
    """Handles loading, validation, and access to Scribe configuration."""
    def __init__(self, config_path_override: Optional[str] = None):
        self._logger = logging.getLogger(f"{APP_NAME}.ScribeConfig")
        self._config_path: Optional[Path] = self._find_config_file(config_path_override)
        self._config: Dict[str, Any] = self._load_and_validate_config()

    def _find_config_file(self, path_override: Optional[str]) -> Optional[Path]:
        potential_paths: List[Path] = []
        if path_override: p = Path(path_override).resolve(); potential_paths.append(p) if p.is_file() else self._logger.warning(f"Explicit config path not found: {path_override}")
        potential_paths.append(Path.cwd() / DEFAULT_CONFIG_FILENAME) # Check current dir
        # potential_paths.append(Path.home() / ".config" / "scribe" / DEFAULT_CONFIG_FILENAME) # User config dir - add if needed
        for path in potential_paths:
            try:
                if path.is_file(): self._logger.info(f"Using config file: {path}"); return path
            except OSError as e: self._logger.warning(f"Cannot access {path}: {e}")
        self._logger.info("No config file found."); return None

    def _load_and_validate_config(self) -> Dict[str, Any]:
        defaults: Dict[str, Any] = { # Define defaults here
            "allowed_target_bases": [str(Path.home()), "/tmp"], "fail_on_audit_severity": "high",
            "fail_on_lint_critical": True, "fail_on_mypy_error": True, "fail_on_test_failure": True,
            "ollama_base_url": os.environ.get("OLLAMA_API_BASE", DEFAULT_OLLAMA_BASE_URL),
            "ollama_model": os.environ.get("OLLAMA_MODEL", DEFAULT_OLLAMA_MODEL),
            "ollama_request_timeout": 120.0,
            "commit_message_template": "feat(auto): Apply validated code for {target_file} via Scribe",
            "test_generation_prompt_template": """Generate concise pytest unit tests...\nTarget: {target_file_path}\nCode:\n```python\n{code_content}```\nSignatures:\n{signatures}\n\nTest Code:""",
            "review_prompt_template": """Perform code review...\nTarget: {target_file_path}\nCode:\n```python\n{code_content}```\nReview Findings (JSON List):""",
            "validation_steps": ["validate_inputs", "setup_environment", "install_deps", "audit_deps", "apply_code", "format_code", "lint_code", "type_check", "extract_signatures", "generate_tests", "save_tests", "execute_tests", "review_code", "run_precommit", "commit_changes", "generate_report"]
        }
        if not self._config_path: config_data = defaults; self._logger.warning("Using default config.")
        else:
            try:
                with open(self._config_path, "rb") as f: loaded_config = tomllib.load(f)
                config_data = self._merge_configs(defaults, loaded_config)
            except (tomllib.TOMLDecodeError, OSError) as e: raise ScribeConfigurationError(f"Error reading/parsing {self._config_path}: {e}") from e
        self._validate_loaded_config(config_data)
        self._logger.debug("Configuration loaded and validated.")
        return config_data

    def _merge_configs(self, base: Dict, updates: Dict) -> Dict:
        merged = base.copy()
        for key, value in updates.items():
            if isinstance(value, dict) and isinstance(merged.get(key), dict): merged[key] = self._merge_configs(merged[key], value)
            else: merged[key] = value
        return merged

    def _validate_loaded_config(self, config: Dict[str, Any]):
        if not isinstance(config.get("allowed_target_bases"), list): raise ScribeConfigurationError("'allowed_target_bases' must be list.")
        try: config["allowed_target_bases"] = [str(Path(p).expanduser().resolve()) for p in config["allowed_target_bases"]]
        except Exception as e: raise ScribeConfigurationError(f"Cannot resolve 'allowed_target_bases': {e}")
        if config.get("fail_on_audit_severity") not in [None, "critical", "high", "moderate", "low"]: raise ScribeConfigurationError("Invalid 'fail_on_audit_severity'.")
        # Add more validation...

    def get(self, key: str, default: Any = None) -> Any: return self._config.get(key, default)
    def get_list(self, key: str, default: Optional[List] = None) -> List: value = self._config.get(key, default or []); return value if isinstance(value, list) else (default or [])
    def get_str(self, key: str, default: str = "") -> str: value = self._config.get(key, default); return value if isinstance(value, str) else default
    def get_bool(self, key: str, default: bool = False) -> bool: value = self._config.get(key, default); return value if isinstance(value, bool) else default
    def get_float(self, key: str, default: float = 0.0) -> float: value = self._config.get(key, default); return float(value) if isinstance(value, (int, float)) else default
    @property
    def config_path(self) -> Optional[Path]: return self._config_path

# --- Tool Runner ---
class ToolRunner:
    """Executes external command-line tools securely."""
    def __init__(self):
        self._logger = logging.getLogger(f"{APP_NAME}.ToolRunner")

    def run_tool(self, command_args: List[str], cwd: Path, venv_path: Optional[Path] = None, check: bool = True, env_vars: Optional[Dict[str, str]] = None) -> subprocess.CompletedProcess:
        executable_name = command_args[0]; executable_path: Optional[Path] = None
        if venv_path: # Prioritize venv bin
            bin_dir = venv_path.resolve() / ("Scripts" if sys.platform == "win32" else "bin")
            for suffix in ["", ".exe"] if sys.platform == "win32" else [""]:
                venv_exec = bin_dir / f"{executable_name}{suffix}"
                if venv_exec.is_file(): executable_path = venv_exec; break
        if not executable_path: # Fallback to PATH
            system_exec = shutil.which(executable_name)
            if system_exec: executable_path = Path(system_exec)
            else: raise FileNotFoundError(f"Executable '{executable_name}' not found in venv ('{venv_path}') or PATH.")

        full_command = [str(executable_path.resolve())] + command_args[1:]
        self._logger.info(f"Running: {' '.join(shlex.quote(str(arg)) for arg in full_command)} (in {cwd})")
        process_env = os.environ.copy()
        if venv_path:
            resolved_venv = venv_path.resolve(); process_env['VIRTUAL_ENV'] = str(resolved_venv)
            venv_bin = resolved_venv / ('Scripts' if sys.platform == 'win32' else 'bin')
            process_env['PATH'] = f"{str(venv_bin)}{os.pathsep}{process_env.get('PATH', '')}"
            process_env.pop('PYTHONHOME', None); process_env.pop('PYTHONPATH', None)
        if env_vars: process_env.update(env_vars)
        try:
            result = subprocess.run(full_command, cwd=cwd, env=process_env, capture_output=True, check=False, text=True, encoding='utf-8', errors='replace')
            log_func = self._logger.debug if result.returncode == 0 else self._logger.warning
            log_func(f"Finished: {shlex.quote(str(full_command[0]))}... RC={result.returncode}")
            if result.stdout: log_func(f"Stdout:\n{result.stdout.strip()}")
            if result.stderr: log_func(f"Stderr:\n{result.stderr.strip()}")
            if check and result.returncode != 0:
                error_detail = result.stderr.strip() or result.stdout.strip()
                raise ScribeToolError(f"Tool '{executable_name}' failed (RC={result.returncode}).\n{error_detail}")
            return result
        except Exception as e: raise ScribeToolError(f"Unexpected error running {executable_name}: {e}") from e

# --- Environment Manager ---
class EnvironmentManager:
    """Manages the target project's venv and dependencies."""
    def __init__(self, target_dir: Path, python_version_str: str, tool_runner: ToolRunner):
        self._logger = logging.getLogger(f"{APP_NAME}.EnvironmentManager")
        self._target_dir = target_dir; self._python_version_str = python_version_str
        self._tool_runner = tool_runner; self._venv_path = self._target_dir.resolve() / VENV_DIR_NAME
        self._venv_python_path: Optional[Path] = None; self._pip_path: Optional[Path] = None

    @property
    def venv_path(self) -> Path: return self._venv_path
    @property
    def python_executable(self) -> Optional[Path]: return self._venv_python_path
    @property
    def pip_executable(self) -> Optional[Path]: return self._pip_path

    def find_venv_executable(self, name: str) -> Optional[Path]:
        if not self._venv_path.is_dir(): return None
        bin_dir = self._venv_path / ("Scripts" if sys.platform == "win32" else "bin")
        for suffix in ["", ".exe"] if sys.platform == "win32" else [""]:
            exec_path = bin_dir / f"{name}{suffix}"
            if exec_path.is_file(): return exec_path.resolve()
        return None

    def setup_venv(self) -> None:
        self._logger.info(f"Setting up venv in: {self._venv_path}")
        if not self._venv_path.exists():
            self._logger.info("Creating virtual environment..."); python_exe = sys.executable # Use Scribe's python
            try: self._tool_runner.run_tool([python_exe, "-m", "venv", str(self._venv_path)], cwd=self._target_dir, check=True)
            except Exception as e: raise ScribeEnvironmentError(f"Failed create venv: {e}") from e
        elif not self._venv_path.is_dir(): raise ScribeEnvironmentError(f"Venv path not dir: {self._venv_path}")
        else: self._logger.info("Existing venv found.")
        self._venv_python_path = self.find_venv_executable("python"); self._pip_path = self.find_venv_executable("pip")
        if not self._venv_python_path or not self._pip_path: raise ScribeEnvironmentError(f"Missing python/pip in venv: {self._venv_path}")
        self._logger.info(f"Venv paths OK: Py={self._venv_python_path}, Pip={self._pip_path}")
        try: cmd = [str(self._pip_path), "install", "--upgrade", "pip", "setuptools", "wheel"]; self._tool_runner.run_tool(cmd, cwd=self._target_dir, venv_path=self._venv_path, check=True)
        except ScribeToolError as e: self._logger.warning(f"Could not upgrade pip/setuptools: {e}.")

    def install_dependencies(self) -> None:
        if not self._pip_path: raise ScribeEnvironmentError("Pip path unset.")
        self._logger.info("Installing project dependencies..."); pyproj = self._target_dir / "pyproject.toml"; reqs = self._target_dir / "requirements.txt"; cmd = None
        pip_base = [str(self._pip_path), "install"]
        if pyproj.is_file(): cmd = pip_base + ["-e", "."]; self._logger.info("Using 'pip install -e .'")
        elif reqs.is_file(): cmd = pip_base + ["-r", str(reqs)]; self._logger.info("Using 'pip install -r requirements.txt'")
        else: self._logger.warning("No dependency file found."); return # Not an error
        try: self._tool_runner.run_tool(cmd, cwd=self._target_dir, venv_path=self._venv_path, check=True)
        except ScribeToolError as e: raise ScribeEnvironmentError(f"Dependency install failed: {e}") from e

    def run_pip_audit(self) -> Tuple[bool, Dict[str, Any]]:
        if not self._pip_path: raise ScribeEnvironmentError("Pip path unset.")
        self._logger.info("Running 'pip audit'..."); cmd = [str(self._pip_path), "audit", "--format", "json"]; results = {}; success = False
        try:
            result = self._tool_runner.run_tool(cmd, cwd=self._target_dir, venv_path=self._venv_path, check=False)
            if result.stdout: results = json.loads(result.stdout)
            success = True
        except json.JSONDecodeError as e: self._logger.error(f"Failed parse pip audit JSON: {e}")
        except (ScribeToolError, FileNotFoundError) as e:
            if "audit" in str(e).lower(): self._logger.warning(f"Skipping audit ('pip audit' missing/failed): {e}")
            else: self._logger.error(f"Audit exec failed: {e}")
        return success, results

# --- LLM Client ---
class LLMClient:
    """Handles communication with the configured Ollama LLM API."""
    def __init__(self, config: ScribeConfig, cli_args: argparse.Namespace):
        self._logger = logging.getLogger(f"{APP_NAME}.LLMClient"); self._config = config
        self._base_url = cli_args.ollama_base_url or config.get_str("ollama_base_url", DEFAULT_OLLAMA_BASE_URL)
        self._model = cli_args.ollama_model or config.get_str("ollama_model", DEFAULT_OLLAMA_MODEL)
        self._timeout = config.get_float("ollama_request_timeout", 120.0); self._client: Optional[httpx.Client] = None
        if HTTP_LIB == "httpx": self._client = httpx.Client(base_url=self._base_url, timeout=self._timeout, follow_redirects=True)
        elif HTTP_LIB == "requests": self._logger.warning("Using requests (sync) for Ollama.")
        else: self._logger.error("No HTTP library found!"); # Should exit earlier
        self._logger.info(f"LLMClient: URL='{self._base_url}', Model='{self._model}'")

    def _call_api(self, prompt: str, format_type: Optional[str] = None) -> Dict[str, Any]:
        if not HTTP_LIB: raise ScribeApiError("No HTTP library.")
        endpoint = "/api/generate"; payload: Dict[str, Any] = {"model": self._model, "prompt": prompt, "stream": False}
        if format_type: payload["format"] = format_type
        self._logger.info(f"Calling Ollama {endpoint} for '{self._model}'..."); self._logger.debug(f"Payload (prompt~{len(prompt)} bytes)")
        try:
            response: Any # Define response type hint possibility
            if self._client: response = self._client.post(endpoint, json=payload) # httpx
            elif HTTP_LIB == "requests": response = requests.post(f"{self._base_url}{endpoint}", json=payload, timeout=self._timeout)
            else: raise ScribeApiError("No HTTP client.")
            response.raise_for_status(); response_data = response.json()
            if response_data.get("error"): raise ScribeApiError(f"Ollama API Error: {response_data['error']}")
            if "response" not in response_data: raise ScribeApiError("Ollama response missing 'response'.")
            self._logger.info("Ollama API call successful.")
            return response_data
        except Exception as e:
            err_type = type(e).__name__; err_msg = str(e);
            if isinstance(e, (httpx.ConnectError, requests.exceptions.ConnectionError)): err_msg = f"Connect error to {self._base_url}: {e}"
            elif isinstance(e, httpx.TimeoutException): err_msg = f"Timeout error: {e}"
            elif isinstance(e, (httpx.HTTPStatusError, requests.exceptions.HTTPError)): err_msg = f"HTTP error {e.response.status_code}: {e.response.text[:200]}"
            elif isinstance(e, json.JSONDecodeError): err_msg = f"JSON decode error: {e}"
            self._logger.error(f"Ollama API call failed: {err_msg}", exc_info=False); self._logger.debug("Traceback:", exc_info=True)
            raise ScribeApiError(err_msg) from e

    def _extract_code_from_response(self, txt: str) -> str:
        self._logger.debug("Extracting code from response."); match = re.search(r"```python\n(.*?)```", txt, re.DOTALL|re.I);
        if match: return match.group(1).strip();
        match = re.search(r"```(.*?)```", txt, re.DOTALL);
        if match: self._logger.warning("Using generic '```' fences."); return match.group(1).strip();
        self._logger.warning("No markdown fences. Assuming full response is code."); return txt.strip()

    def generate_tests(self, code: str, path: str, sigs: str) -> Optional[str]:
        self._logger.info(f"Requesting test generation for: {path}"); tmpl = self._config.get_str("test_generation_prompt_template"); p = tmpl.format(code_content=code[:3000], target_file_path=path, signatures=sigs)
        try: data = self._call_api(p); raw = data.get("response", ""); code = self._extract_code_from_response(raw) if raw else None
            if not code: self._logger.warning("Empty test generation."); return None
            try: ast.parse(code); self._logger.info("Generated test code syntax OK."); return code
            except SyntaxError as e: self._logger.error(f"Generated test syntax error: {e}"); return None
        except ScribeApiError as e: self._logger.error(f"Test gen API error: {e}"); return None

    def generate_review(self, code: str, path: str) -> Optional[List[Dict[str, str]]]:
        self._logger.info(f"Requesting review simulation for: {path}"); tmpl = self._config.get_str("review_prompt_template"); p = tmpl.format(code_content=code[:4000], target_file_path=path)
        try: data = self._call_api(p, format_type="json"); txt = data.get("response", ""); findings = []
            if not txt: self._logger.warning("Empty review response."); return []
            try: parsed = json.loads(txt);
                if not isinstance(parsed, list): raise ValueError("Expected list.")
                findings = [{'severity': str(i.get('sev','info')).lower(), 'desc': str(i.get('desc','')), 'loc': str(i.get('loc','?'))} for i in parsed if isinstance(i, dict) and all(k in i for k in ['severity','description','location'])] # Use shortened keys for safety
                self._logger.info(f"Parsed {len(findings)} review findings."); return findings
            except (json.JSONDecodeError, ValueError) as e: self._logger.error(f"Failed parse JSON review: {e}"); return None # Indicate parse failure
        except ScribeApiError as e: self._logger.error(f"Review gen API error: {e}"); return None

# --- Report Generator ---
class ReportGenerator:
    def __init__(self, fmt: str): self._logger = logging.getLogger(f"{APP_NAME}.ReportGen"); self._fmt = fmt if fmt in REPORT_FORMATS else DEFAULT_REPORT_FORMAT
    def generate(self, data: FinalReport) -> str: self._logger.info(f"Generating report ({self._fmt})..."); return self._format_text(data) if self._fmt == "text" else self._format_json(data)
    def _format_json(self, data: FinalReport) -> str: try: return json.dumps(data, indent=2, default=str); except Exception as e: self._logger.error(f"JSON serialize error: {e}"); return '{"status":"FATAL", "error":"Report serialize failed"}'
    def _make_serializable(self, detail: Any) -> Any:
         if detail is None or isinstance(detail, (str, int, float, bool)): return detail
         elif isinstance(detail, (dict, list)): try: json.dumps(detail); return detail; except TypeError: return str(detail)
         elif isinstance(detail, (datetime, Path)): return str(detail)
         else: return f"<Unserializable {type(detail).__name__}>"
    def _format_text(self, r: FinalReport) -> str: # Simplified text format
         lines = [f"--- {APP_NAME} Report ---", f"Run: {r['run_id']}", f"Status: {r['overall_status']}", f"Time: {r['total_duration_seconds']:.2f}s", f"Target: {r['target_file_relative']} in {r['target_project_dir']}", "-"*20, "Steps:"]
         counts: Dict[str, int] = {}; for s in r['steps']: counts[s['status']] = counts.get(s['status'], 0) + 1
         lines.append(f"  Summary: S:{counts.get('SUCCESS',0)} F:{counts.get('FAILURE',0)} W:{counts.get('WARNING',0)} A:{counts.get('ADVISORY',0)} S:{counts.get('SKIPPED',0)}")
         for i, s in enumerate(r['steps']): lines.append(f"  {i+1}. {s['name']} -> {s['status']} ({s['duration_seconds']:.2f}s){' ERR: '+s['error_message'] if s['error_message'] else ''}")
         lines.append("-" * 20); lines.append(f"Commit Attempted: {'Yes' if r['commit_attempted'] else 'No'}")
         if r['commit_sha']: lines.append(f"Commit SHA: {r['commit_sha']}")
         if r.get('audit_findings'): lines.append(f"\nAudit Findings:\n{json.dumps(r['audit_findings'], indent=2)}")
         if r.get('ai_review_findings'): lines.append(f"\nAI Review Findings:\n{json.dumps(r['ai_review_findings'], indent=2)}")
         if r.get('test_results_summary'): lines.append(f"\nTest Summary:\n{json.dumps(r['test_results_summary'], indent=2)}")
         lines.append("--- End Report ---"); return "\n".join(lines)

# --- Workflow Steps Logic ---
class WorkflowSteps:
    """Encapsulates individual workflow step logic."""
    def __init__(self, agent: 'ScribeAgent'): self.agent = agent # Reference main agent

    def validate_inputs(self) -> Tuple[str, str]:
        try: self.agent._target_file_path = self.agent._validate_target_file_path_logic(); self.agent._temp_code_path = self.agent._args.code_file.resolve(strict=True)
            if not self.agent._temp_code_path.is_file(): raise ScribeInputError("Code file not found.")
            return 'SUCCESS', f"Inputs OK. Target: {self.agent._target_file_path.name}"
        except (ScribeInputError, ScribeFileSystemError, PermissionError, FileNotFoundError) as e: raise ScribeInputError(f"Input validation failed: {e}") from e

    def _validate_target_file_path_logic(self) -> Path: # Renamed internal helper
         target_dir = self.agent._target_dir # Already validated
         target_file_rel = Path(self.agent._args.target_file)
         if target_file_rel.is_absolute() or ".." in target_file_rel.parts: raise ScribeInputError(f"Invalid relative path: '{target_file_rel}'.")
         target_file_abs = (target_dir / target_file_rel).resolve()
         if not target_file_abs.is_relative_to(target_dir): raise ScribeInputError(f"Resolved path '{target_file_abs}' outside target '{target_dir}'.")
         target_parent = target_file_abs.parent
         if not target_parent.exists(): target_parent.mkdir(parents=True, exist_ok=True)
         elif not target_parent.is_dir(): raise ScribeInputError(f"Target parent exists but is not dir: {target_parent}")
         return target_file_abs

    def setup_environment(self) -> Tuple[str, Optional[str]]:
        try: self.agent._env_manager.setup_venv(); return 'SUCCESS', f"Venv setup/validated: {self.agent._env_manager.venv_path}"
        except ScribeEnvironmentError as e: raise ScribeEnvironmentError(f"Venv setup failed: {e}") from e

    def install_deps(self) -> Tuple[str, Optional[str]]:
        try: self.agent._env_manager.install_dependencies(); return 'SUCCESS', "Deps installed/skipped."
        except ScribeEnvironmentError as e: raise ScribeEnvironmentError(f"Dep install failed: {e}") from e

    def audit_deps(self) -> Tuple[str, Dict]:
        try: run_ok, data = self.agent._env_manager.run_pip_audit(); vulns = data.get("vulnerabilities", []); count = len(vulns)
            summary = {"vulnerability_count": count, "details": vulns}
            if not run_ok: return 'WARNING', {**summary, "message": data.get("error", "Audit run failed/skipped.")}
            if count == 0: return 'SUCCESS', summary
            fail_sev = self.agent._config.get("fail_on_audit_severity"); failed = False; highest = "none"
            if fail_sev: sev_map = {"low":0,"moderate":1,"high":2,"critical":3}; thresh = sev_map.get(fail_sev, 4); max_sev = -1
                for v in vulns: sev=str(v.get("severity","?")).lower().replace("cvss ",""); lvl=sev_map.get(sev,-1);
                    if lvl>max_sev: max_sev=lvl; highest=sev;
                    if lvl>=thresh: failed=True;
            summary.update({"highest_severity": highest, "configured_fail_severity": fail_sev})
            return 'FAILURE' if failed else 'WARNING', summary
        except ScribeEnvironmentError as e: raise ScribeEnvironmentError(f"Pip audit failed: {e}") from e

    def apply_code(self) -> Tuple[str, str]:
        if not self.agent._target_file_path or not self.agent._temp_code_path: raise ScribeError("Paths unset for apply.")
        try: code = self.agent._temp_code_path.read_text('utf-8'); self.agent._target_file_path.write_text(code, 'utf-8'); return 'SUCCESS', f"Wrote {len(code)} bytes."
        except OSError as e: raise ScribeFileSystemError(f"File I/O error: {e}") from e

    def format_code(self) -> Tuple[str, str]:
        if not self.agent._target_file_path: raise ScribeError("Target path unset."); path = self.agent._env_manager.find_venv_executable("ruff");
        if not path: return 'SKIPPED', "Ruff not found."
        cmd = [str(path), "format", str(self.agent._target_file_path)]
        try: r = self.agent._tool_runner.run_tool(cmd, cwd=self.agent._target_dir, venv_path=self.agent._env_manager.venv_path, check=True); d = r.stderr.strip() or r.stdout.strip() or "Formatted."; return 'SUCCESS', d
        except ScribeToolError as e: raise ScribeToolError(f"Ruff format fail: {e}") from e

    def lint_code(self) -> Tuple[str, Dict]:
        if not self.agent._target_file_path: raise ScribeError("Target path unset."); path = self.agent._env_manager.find_venv_executable("ruff");
        if not path: return 'SKIPPED', {"message": "Ruff not found."}
        cmd = [str(path), "check", "--fix", "--show-source", str(self.agent._target_file_path)]
        try: r = self.agent._tool_runner.run_tool(cmd, cwd=self.agent._target_dir, venv_path=self.agent._env_manager.venv_path, check=False)
            out = f"Stdout:\n{r.stdout.strip()}\nStderr:\n{r.stderr.strip()}".strip(); d = {"output": out}
            if r.returncode==0: d["message"]="Lint passed/fixed."; return 'SUCCESS', d
            elif r.returncode==1: d["message"]="Lint issues remain."; fail = self.agent._config.get_bool("fail_on_lint_critical"); return 'FAILURE' if fail else 'WARNING', d
            else: raise ScribeToolError(f"Ruff check fail (RC={r.returncode}).\n{out}")
        except ScribeToolError as e: raise ScribeToolError(f"Ruff check fail: {e}") from e

    def type_check(self) -> Tuple[str, Dict]:
        if not self.agent._target_file_path: raise ScribeError("Target path unset."); path = self.agent._env_manager.find_venv_executable("mypy");
        if not path: return 'SKIPPED', {"message": "MyPy not found."}
        cmd = [str(path), str(self.agent._target_file_path)]
        try: r = self.agent._tool_runner.run_tool(cmd, cwd=self.agent._target_dir, venv_path=self.agent._env_manager.venv_path, check=False)
            out = r.stdout.strip() or r.stderr.strip(); d = {"message": "MyPy finished.", "output": out}
            if r.returncode==0: return 'SUCCESS', d
            else: d["message"]="MyPy found errors."; fail = self.agent._config.get_bool("fail_on_mypy_error"); return 'FAILURE' if fail else 'WARNING', d
        except ScribeToolError as e: raise ScribeToolError(f"MyPy exec failed: {e}") from e

    def extract_signatures(self) -> Tuple[str, str]:
        if not self.agent._target_file_path: raise ScribeError("Target path unset.")
        sigs = [];
        try: code = self.agent._target_file_path.read_text('utf-8'); tree = ast.parse(code)
            for node in ast.walk(tree):
                sig: Optional[str]=None
                if isinstance(node,(ast.FunctionDef, ast.AsyncFunctionDef)): sig = f"{'async ' if isinstance(node, ast.AsyncFunctionDef) else ''}def {node.name}{ast.unparse(node.args)}:"
                elif isinstance(node, ast.ClassDef): sig = f"class {node.name}:"
                if sig: sigs.append(sig)
            txt = "\n".join(sigs); return ('SUCCESS', txt) if txt else ('WARNING', "No signatures found.")
        except Exception as e: raise ScribeError(f"AST parse fail: {e}") from e

    def generate_tests(self, signatures: str) -> Tuple[str, Optional[str]]:
        if not self.agent._target_file_path: raise ScribeError("Target path unset.")
        if not signatures: return 'SKIPPED', "No signatures."
        try: code = self.agent._target_file_path.read_text('utf-8'); gen_code = self.agent._llm_client.generate_tests(code, self.agent._args.target_file, signatures);
            if not gen_code: return 'FAILURE', "LLM failed generation."
            try: ast.parse(gen_code); return 'SUCCESS', gen_code
            except SyntaxError as e: return 'FAILURE', f"Test syntax error: {e}"
        except (OSError, ScribeError) as e: return 'FAILURE', f"Test generation failed: {e}"

    def save_tests(self, test_code: str) -> Tuple[str, Path]:
        if not self.agent._target_file_path: raise ScribeError("Target path unset.")
        stem=self.agent._target_file_path.stem; safe_stem=''.join(c if c.isalnum() else '_' for c in stem)
        t_dir=self.agent._target_dir/SCRIBE_TEST_DIR; t_file=f"test_{safe_stem}_scribe.py"; t_path=t_dir/t_file
        try: t_dir.mkdir(parents=True, exist_ok=True); t_path.write_text(test_code, 'utf-8'); return 'SUCCESS', t_path
        except OSError as e: raise ScribeFileSystemError(f"Write test fail '{t_path}': {e}") from e

    def execute_tests(self, test_path: Path) -> Tuple[str, Dict]:
        if not self.agent._target_file_path: raise ScribeError("Target path unset."); path = self.agent._env_manager.find_venv_executable("pytest");
        if not path: return 'SKIPPED', {"message": "Pytest not found."}
        env = os.environ.copy(); pp=env.get('PYTHONPATH',''); env['PYTHONPATH']=f"{self.agent._target_dir}{os.pathsep}{pp}"
        cmd = [str(path), str(test_path), "-v"]
        try: r = self.agent._tool_runner.run_tool(cmd, cwd=self.agent._target_dir, venv_path=self.agent._env_manager.venv_path, env_vars=env, check=False)
            out=r.stdout.strip() or r.stderr.strip(); d={"output":out}; self.agent._report_data["test_results_summary"] = d # Store output
            if r.returncode==0: d["message"]="Tests passed."; return 'SUCCESS', d
            elif r.returncode==5: d["message"]="No tests collected."; return 'WARNING', d
            else: d["message"]=f"Tests failed (RC={r.returncode})."; fail=self.agent._config.get_bool("fail_on_test_failure",True); return 'FAILURE' if fail else 'WARNING', d
        except ScribeToolError as e: raise ScribeToolError(f"Pytest exec failed: {e}") from e

    def review_code(self) -> Tuple[str, Optional[List[Dict]]]:
        if not self.agent._target_file_path: raise ScribeError("Target path unset.")
        try: code = self.agent._target_file_path.read_text('utf-8'); findings = self.agent._llm_client.generate_review(code, self.agent._args.target_file);
            if findings is None: return 'WARNING', [{"severity":"warn", "desc":"Review API/Parse error.", "loc":"N/A"}]
            d = findings if findings else [{"severity":"info", "desc":"No issues found by AI.", "loc":"N/A"}]
            self.agent._report_data["ai_review_findings"] = d; return 'ADVISORY', d
        except (OSError, ScribeError) as e: return 'WARNING', [{"severity":"warn", "desc":f"Review failed: {e}", "loc":"N/A"}]

    def run_precommit(self) -> Tuple[str, Dict]:
        if not self.agent._target_file_path: raise ScribeError("Target path unset."); cfg = self.agent._target_dir / ".pre-commit-config.yaml";
        if not cfg.is_file(): return 'SKIPPED', {"message": ".pre-commit config missing."}; path = self.agent._env_manager.find_venv_executable("pre-commit");
        if not path: return 'SKIPPED', {"message": "pre-commit not found."}
        cmd = [str(path), "run", "--files", str(self.agent._target_file_path)]
        try: r = self.agent._tool_runner.run_tool(cmd, cwd=self.agent._target_dir, venv_path=self.agent._env_manager.venv_path, check=False)
            d={"output":r.stdout.strip() or r.stderr.strip()};
            if r.returncode==0: d["message"]="Hooks passed."; return 'SUCCESS', d
            else: d["message"]=f"Hooks failed (RC={r.returncode})."; return 'FAILURE', d
        except ScribeToolError as e: raise ScribeToolError(f"Pre-commit failed: {e}") from e

    def commit_changes(self) -> Tuple[str, Optional[str]]:
        if not self.agent._target_file_path: raise ScribeError("Target path unset."); git = self.agent.git_exe;
        if not git: return 'WARNING', "Git not found."
        try:
            r = self.agent._tool_runner.run_tool([git,"rev-parse","--is-inside-work-tree"], cwd=self.agent._target_dir, check=True);
            if r.stdout.strip() != "true": return 'WARNING', "Not Git repo."
            r = self.agent._tool_runner.run_tool([git,"status","--porcelain",str(self.agent._target_file_path)], cwd=self.agent._target_dir, check=True);
            if not r.stdout.strip(): return 'SUCCESS', "No changes to commit."
            self.agent._tool_runner.run_tool([git,"add",str(self.agent._target_file_path)], cwd=self.agent._target_dir, check=True)
            tmpl = self.agent._config.get_str("commit_message_template"); msg = tmpl.format(target_file=self.agent._args.target_file)
            self.agent._tool_runner.run_tool([git,"commit","-m",msg], cwd=self.agent._target_dir, check=True)
            r = self.agent._tool_runner.run_tool([git,"rev-parse","HEAD"], cwd=self.agent._target_dir, check=True)
            sha = r.stdout.strip(); self.agent._report_data["commit_sha"] = sha; return 'SUCCESS', sha
        except ScribeToolError as e:
            if "nothing to commit" in str(e).lower(): return 'SUCCESS', "No changes to commit."
            raise ScribeToolError(f"Git failed: {e}") from e

    def generate_report(self) -> Tuple[str, str]:
        """Generates the final report string. Should always succeed if report_data is valid."""
        self.agent._report_data["end_time"] = datetime.now(timezone.utc).isoformat()
        start_dt = datetime.fromisoformat(self.agent._report_data["start_time"]); end_dt = datetime.fromisoformat(self.agent._report_data["end_time"])
        self.agent._report_data["total_duration_seconds"] = round((end_dt - start_dt).total_seconds(), 3)
        self.agent._report_data["overall_status"] = "SUCCESS" if self.agent._overall_success else "FAILURE"
        try: return 'SUCCESS', self.agent._report_generator.generate(self.agent._report_data)
        except Exception as e: return 'FAILURE', f"Report generation failed: {e}"

# --- Scribe Agent Orchestrator ---
class ScribeAgent:
    """Orchestrates the automated validation workflow using WorkflowSteps."""
    def __init__(self, args: argparse.Namespace):
        self._args = args; self._logger = logging.getLogger(APP_NAME)
        self._start_time = datetime.now(timezone.utc)
        self._run_id = self._start_time.strftime('%Y%m%d_%H%M%S_%f')[:-3] + f"_{os.getpid()}"
        self._config: ScribeConfig = ScribeConfig(args.config_file)
        self._tool_runner: ToolRunner = ToolRunner()
        self._target_dir: Path = self._validate_target_dir() # Validates based on config
        self._env_manager: EnvironmentManager = EnvironmentManager(self._target_dir, args.python_version, self._tool_runner)
        self._llm_client: LLMClient = LLMClient(self._config, args)
        self._report_generator: ReportGenerator = ReportGenerator(args.report_format)
        self._report_data: FinalReport = self._initialize_report()
        self._overall_success: bool = True
        self._target_file_path: Optional[Path] = None # Set by steps.validate_inputs
        self._temp_code_path: Optional[Path] = None # Set by steps.validate_inputs
        self.git_exe: Optional[str] = shutil.which("git") # Find git once at init
        self.steps = WorkflowSteps(self) # Delegate steps logic

    def _validate_target_dir(self) -> Path:
        target_dir = Path(self._args.target_dir).resolve()
        if not target_dir.is_dir(): raise ScribeInputError(f"Target dir not found: {target_dir}")
        allowed = self._config.get_list("allowed_target_bases")
        if allowed and not any(target_dir.is_relative_to(Path(b)) for b in allowed):
             raise ScribeInputError(f"Target directory '{target_dir}' outside allowed bases.")
        return target_dir

    def _initialize_report(self) -> FinalReport:
        return cast(FinalReport, {
            "scribe_version":APP_VERSION,"run_id":self._run_id,"start_time":self._start_time.isoformat(),
            "end_time":"","total_duration_seconds":0.0,"overall_status":"PENDING",
            "target_project_dir":str(self._args.target_dir),"target_file_relative":self._args.target_file,
            "language":self._args.language,"python_version":self._args.python_version,
            "commit_attempted":self._args.commit,"commit_sha":None,"steps":[],
            "audit_findings":None,"ai_review_findings":None,"test_results_summary":None
        })

    def _add_step_result(self, name: str, status: str, start: datetime, details: Any = None, error: Optional[str] = None):
        end=datetime.now(timezone.utc); dur=(end-start).total_seconds()
        s_details=self._report_generator._make_serializable(details)
        step: StepResult=cast(StepResult, {"name":name,"status":status,"start_time":start.isoformat(),"end_time":end.isoformat(),"duration_seconds":round(dur,3),"details":s_details,"error_message":str(error) if error else None})
        self._report_data["steps"].append(step)
        if status == 'FAILURE': self._overall_success = False
        lvl=logging.INFO if status in ['SUCCESS','SKIPPED','ADVISORY'] else logging.WARNING if status=='WARNING' else logging.ERROR
        msg=f"Step '{name}': {status} ({dur:.3f}s)"
        if error: msg += f" | Err: {str(error)[:200]}"
        elif s_details and isinstance(s_details, str): msg += f" | Detail: {s_details[:100]}"
        self._logger.log(lvl, msg)

    def _execute_step(self, step_func: Callable[..., Any], *args, **kwargs) -> Any:
        if not callable(step_func): name=getattr(step_func,'__name__',str(step_func)); self._logger.error(f"Internal: Step not callable: {name}"); self._add_step_result(name,'FAILURE',datetime.now(timezone.utc),error_message="Internal: Step not callable."); self._overall_success=False; return None
        name=step_func.__name__; start=datetime.now(timezone.utc); self._logger.info(f"--- Start: {name} ---")
        status='FAILURE'; details:Any=None; error:Optional[str]=None; ret_val:Any=None
        if not self._overall_success and name not in ["generate_report"]: status,details,error='SKIPPED',"Prev failure.","Prev failure."
        else:
            try: res_tuple = step_func(*args, **kwargs)
                if isinstance(res_tuple, tuple) and len(res_tuple)>=1: status=res_tuple[0]; details=res_tuple[1] if len(res_tuple)>1 else None; error=str(details) if status=='FAILURE' else None; ret_val=details if status!='FAILURE' else None
                else: status,details,ret_val='SUCCESS',res_tuple,res_tuple
            except ScribeError as e: self._logger.error(f"Step '{name}' Error: {e}",exc_info=False); self._logger.debug("Trace:",exc_info=True); status,error='FAILURE',f"{type(e).__name__}: {e}"
            except Exception as e: self._logger.exception(f"Unhandled Step '{name}' Error:"); status,error='FAILURE',f"Unhandled {type(e).__name__}: {e}"
        self._add_step_result(name, status, start, details, error)
        return ret_val

    def run(self) -> int:
        self._logger.info(f"Starting run: {self._run_id}"); steps_failed = 0
        try:
            step_order = self._config.get_list("validation_steps")
            if not step_order: raise ScribeConfigurationError("No steps defined.")
            step_map = { "validate_inputs": self.steps.validate_inputs, "setup_environment": self.steps.setup_venv, "install_deps": self.steps.install_dependencies, "audit_deps": self.steps.audit_dependencies, "apply_code": self.steps.apply_code, "format_code": self.steps.format_code, "lint_code": self.steps.lint_code, "type_check": self.steps.type_check, "extract_signatures": self.steps.extract_signatures, "generate_tests": self.steps.generate_tests, "save_tests": self.steps.save_tests, "execute_tests": self.steps.execute_tests, "review_code": self.steps.review_code, "run_precommit": self.steps.run_precommit, "commit_changes": self.steps.commit_changes, "generate_report": self.steps.generate_report }
            results: Dict[str, Any] = {}
            for name in step_order:
                if name not in step_map: self._add_step_result(name,"SKIPPED",datetime.now(timezone.utc),error_message="Unknown step."); continue
                func=step_map[name]; args=[]; kwargs={}; skip=False
                if name in ["setup_environment","install_deps","audit_deps"] and self._args.skip_deps: skip=True
                if name in ["extract_signatures","generate_tests","save_tests","execute_tests"] and self._args.skip_tests: skip=True
                if name == "review_code" and self._args.skip_review: skip=True
                if name == "commit_changes" and not self._args.commit: skip=True
                if name == "generate_tests":
                    if "extract_signatures" not in results or not results["extract_signatures"]: skip=True
                    else: kwargs={"signatures": results["extract_signatures"]}
                if name == "save_tests":
                    if "generate_tests" not in results or not results["generate_tests"]: skip=True
                    else: kwargs={"test_code": results["generate_tests"]}
                if name == "execute_tests":
                    if "save_tests" not in results or not results["save_tests"]: skip=True
                    else: kwargs={"test_path": results["save_tests"]}

                if skip: self._add_step_result(name, "SKIPPED", datetime.now(timezone.utc), error_message=f"Skipped via CLI flag or prerequisite fail.")
                else:
                     res = self._execute_step(func, *args, **kwargs)
                     results[name] = res
                     if not self._overall_success and name != "generate_report": self._logger.warning(f"Workflow halted after fail in: {name}"); break
        except ScribeError as e: self._logger.error(f"Workflow Error: {e}"); self._overall_success = False
        except Exception as e: self._logger.critical("Workflow Critical Error!", exc_info=True); self._overall_success = False
        finally: final_report_tuple=self.steps.generate_report(); final_report_str=final_report_tuple[1] if isinstance(final_report_tuple,tuple) and len(final_report_tuple)>1 else "{}"; print(final_report_str); self._cleanup_temp_file(); self._logger.info(f"--- Workflow Ended [{self._report_data['overall_status']}] ---"); return 0 if self._overall_success else 1

    def _cleanup_temp_file(self):
        try:
             if self._temp_code_path and self._temp_code_path.exists(): self._temp_code_path.unlink(); self._logger.info(f"Cleaned temp file: {self._temp_code_path}")
        except Exception as e: self._logger.warning(f"Could not remove temp file '{self._temp_code_path}': {e}")

# --- Argument Parser Setup ---
def setup_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=f"{APP_NAME} v{APP_VERSION}...", formatter_class=argparse.ArgumentDefaultsHelpFormatter); parser.add_argument('-v', '--version', action='version', version=f'%(prog)s {APP_VERSION}')
    core = parser.add_argument_group('Core Inputs'); core.add_argument('--target-dir', type=Path, required=True); core.add_argument('--code-file', type=Path, required=True); core.add_argument('--target-file', type=str, required=True)
    cfg = parser.add_argument_group('Config & Behavior'); cfg.add_argument('--language', default="python"); cfg.add_argument('--python-version', default=DEFAULT_PYTHON_VERSION); cfg.add_argument('--config-file', default=None); cfg.add_argument('--commit', action='store_true'); cfg.add_argument('--report-format', choices=REPORT_FORMATS, default=DEFAULT_REPORT_FORMAT)
    skip = parser.add_argument_group('Skip Flags'); skip.add_argument('--skip-deps', action='store_true'); skip.add_argument('--skip-tests', action='store_true'); skip.add_argument('--skip-review', action='store_true')
    llm = parser.add_argument_group('LLM Overrides'); llm.add_argument('--ollama-base-url'); llm.add_argument('--ollama-model')
    log = parser.add_argument_group('Logging'); log.add_argument('--log-level', choices=LOG_LEVELS, default=DEFAULT_LOG_LEVEL); log.add_argument('--log-file')
    return parser

# --- Main Execution ---
def main(cli_args: Optional[Sequence[str]] = None) -> int:
    if not HTTP_LIB: print("FATAL: httpx/requests required.", file=sys.stderr); return 1
    if cli_args is None: cli_args = sys.argv[1:]
    parser = setup_arg_parser(); args: argparse.Namespace
    try: args = parser.parse_args(cli_args);
    except SystemExit as e: return e.code
    except Exception as e: print(f"Arg parse error: {e}", file=sys.stderr); parser.print_usage(sys.stderr); return 2
    try: setup_logging(args.log_level, args.log_file)
    except Exception as e: print(f"FATAL Logging init error: {e}", file=sys.stderr); return 1
    logger = logging.getLogger(APP_NAME); exit_code: int = 1
    try: agent = ScribeAgent(args); exit_code = agent.run()
    except ScribeError as e: logger.error(f"Workflow Error: {e}", exc_info=False); print(f"\nERROR: {e}", file=sys.stderr); exit_code = 3
    except Exception as e: logger.critical("Unhandled Exception!", exc_info=True); print(f"\nCRITICAL ERROR: {e}", file=sys.stderr); exit_code = 1
    finally: logger.info(f"--- Execution Finished ---"); logging.shutdown()
    return exit_code

# --- Entry Point ---
if __name__ == "__main__":
    sys.exit(main())