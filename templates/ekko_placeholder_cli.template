#!/usr/bin/env python3
# File: src/ekko/cli/main.py
"""Project Ekko - CLI Interface (using Typer)"""
import typer
from typing_extensions import Annotated
import logging

logger = logging.getLogger(__name__)
app = typer.Typer(
    name="ekko",
    help="Project Ekko: AI Development & Deployment Platform CLI (v0.1)",
    rich_markup_mode="markdown"
)

@app.callback()
def main_callback(
    verbose: Annotated[bool, typer.Option("--verbose", "-v", help="Enable verbose output.")] = False
):
    """Ekko CLI Root"""
    level = logging.DEBUG if verbose else logging.INFO
    # Configure logging for CLI specifically? Or rely on root setup?
    # logging.basicConfig(level=level, format="%(levelname)s: %(message)s")
    logger.info(f"Ekko CLI invoked. Verbose: {verbose}")


@app.command()
def init(
    project_type: Annotated[str, typer.Option(help="Type of project (e.g., python, node)")] = "python",
    project_name: Annotated[Optional[str], typer.Argument(help="Optional name for the new project.")] = None
):
    """Initializes a new project scaffold."""
    print(f"Initializing Ekko project '{project_name or 'default'}' (Type: {project_type})... [Placeholder]")
    logger.info(f"Command: init, Type: {project_type}, Name: {project_name}")
    # TODO: Implement scaffolding logic using core modules

@app.command()
def validate(
    file: Annotated[Optional[str], typer.Argument(help="Specific file path to validate. Validates project if omitted.")] = None,
    profile: Annotated[str, typer.Option(help="Validation profile (e.g., 'quick', 'full', 'security')")] = "full"
):
    """Runs validation checks on a file or the entire project."""
    target = file if file else "project"
    print(f"Validating '{target}' using profile '{profile}'... [Placeholder]")
    logger.info(f"Command: validate, Target: {target}, Profile: {profile}")
    # TODO: Implement validation engine calls

@app.command()
def deploy(
    env: Annotated[str, typer.Option(help="Target environment (e.g., staging, prod)")] = "staging",
    skip_validation: Annotated[bool, typer.Option("--skip-validation", help="Skip validation checks before deploy.")] = False
):
    """Deploys the validated project to the target environment."""
    print(f"Deploying to '{env}' (Skip Validation: {skip_validation})... [Placeholder]")
    logger.info(f"Command: deploy, Env: {env}, Skip Validation: {skip_validation}")
    # TODO: Implement validation (unless skipped) and Ansible/Terraform integration

# Add more commands as needed for other Ekko features

if __name__ == "__main__":
    # This allows running the CLI module directly for testing if needed,
    # but the primary entry point is via the 'ekko' script installed by pip
    app()