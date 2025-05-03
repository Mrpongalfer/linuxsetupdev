# File: src/ekko/config.py
"""
Project Ekko - Configuration Loading using Pydantic Settings.
Loads from .env files and environment variables.
"""
import logging
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field, DirectoryPath, FilePath, HttpUrl
from pathlib import Path
from typing import Optional, List

logger = logging.getLogger(__name__)

class AIServiceConfig(BaseSettings):
    """Configuration for a single AI provider."""
    api_key: Optional[str] = Field(None, validation_alias="API_KEY") # Allow specific API_KEY var
    base_url: Optional[HttpUrl] = None # Optional base URL for self-hosted/proxied
    default_model: Optional[str] = None

class EkkoSettings(BaseSettings):
    """Main configuration model for Ekko."""
    log_level: str = Field("INFO", validation_alias="EKKO_LOG_LEVEL")
    project_base_dir: DirectoryPath = Field(Path.home() / "ekko_projects", validation_alias="EKKO_PROJECT_BASE")

    # AI Provider Config (Examples - adapt as needed)
    gemini_config: Optional[AIServiceConfig] = Field(default=None, validation_alias="EKKO_GEMINI")
    claude_config: Optional[AIServiceConfig] = Field(default=None, validation_alias="EKKO_CLAUDE")
    openai_config: Optional[AIServiceConfig] = Field(default=None, validation_alias="EKKO_OPENAI")
    ollama_config: AIServiceConfig = Field(default_factory=lambda: AIServiceConfig(base_url="http://localhost:11434", default_model="mistral"), validation_alias="EKKO_OLLAMA")

    primary_generator: str = Field("gemini", validation_alias="EKKO_PRIMARY_GENERATOR") # Provider name
    security_validator: str = Field("claude", validation_alias="EKKO_SECURITY_VALIDATOR")
    docs_generator: str = Field("openai", validation_alias="EKKO_DOCS_GENERATOR")
    # Add RLHF model config if needed

    # Ansible & Terraform config
    ansible_playbook_dir: Optional[DirectoryPath] = Field(None, validation_alias="EKKO_ANSIBLE_DIR")
    terraform_dir: Optional[DirectoryPath] = Field(None, validation_alias="EKKO_TERRAFORM_DIR")

    # Scribe Integration (Path to scribe executable)
    scribe_agent_path: Optional[FilePath] = Field(None, validation_alias="EKKO_SCRIBE_PATH")

    # Model Config for Pydantic Settings
    model_config = SettingsConfigDict(
        env_file=(Path('.') / 'config' / '.env', Path.home() / '.config' / 'ekko' / '.env'), # Load .env from project/config then user config
        env_prefix='EKKO_', # e.g., EKKO_LOG_LEVEL=DEBUG
        case_sensitive=False,
        extra='ignore', # Ignore extra env vars
        env_nested_delimiter='__' # e.g., EKKO_GEMINI__API_KEY=...
    )

# Global settings instance (cached)
_settings_instance: Optional[EkkoSettings] = None

def get_ekko_settings() -> EkkoSettings:
    """Loads and returns the Ekko settings, caching the instance."""
    global _settings_instance
    if _settings_instance is None:
        logger.debug("Loading Ekko settings...")
        try:
            _settings_instance = EkkoSettings()
            logger.info("Ekko settings loaded successfully.")
            # Log some loaded settings for verification (avoid logging secrets)
            logger.debug(f"  Log Level: {_settings_instance.log_level}")
            logger.debug(f"  Project Base: {_settings_instance.project_base_dir}")
            logger.debug(f"  Primary LLM: {_settings_instance.primary_generator}")
        except Exception as e:
            logger.error(f"FATAL: Failed to load/validate Ekko settings: {e}", exc_info=True)
            # Fallback to basic defaults if loading fails to allow basic operation?
            # Or just raise the error? Raising is safer.
            raise ScribeConfigurationError(f"Ekko settings load failed: {e}") from e
            # _settings_instance = EkkoSettings() # Fallback
    return _settings_instance

if __name__ == '__main__':
    # Example of loading and printing settings
    try:
        settings = get_ekko_settings()
        print("Ekko Settings Loaded:")
        # Be careful not to print sensitive data here in production
        print(settings.model_dump_json(indent=2, exclude={'gemini_config', 'claude_config', 'openai_config'})) # Exclude API keys
    except Exception as e:
        print(f"Error loading settings: {e}")