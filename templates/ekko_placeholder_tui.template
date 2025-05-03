#!/usr/bin/env python3
# File: src/ekko/tui/main.py
"""Project Ekko - Textual TUI Interface (Placeholder)"""
import logging
import sys
from pathlib import Path

# Basic logging setup - logs to ekko_tui_debug.log in project root
LOG_FILE = Path(__file__).parent.parent.parent / "ekko_tui_debug.log"
logging.basicConfig(
    level=logging.DEBUG, filename=LOG_FILE, filemode='a',
    format='%(asctime)s-%(levelname)s-%(name)s-%(message)s'
)
logger = logging.getLogger("EkkoTUI")

try:
    from textual.app import App, ComposeResult
    from textual.widgets import Header, Footer, Static, Log, Placeholder
    from textual.containers import Container, VerticalScroll
except ImportError as e:
    logger.critical(f"Textual import failed: {e}")
    print("ERROR: Textual library not found.", file=sys.stderr)
    print("Please activate the venv and ensure 'pip install textual' ran.", file=sys.stderr)
    sys.exit(f"Dependency Error: {e}")

class EkkoTUI(App):
    """Project Ekko Textual User Interface."""

    TITLE = "Project Ekko Control Plane v0.1"
    CSS_PATH = "main.css" # Optional: Add a CSS file later for styling
    BINDINGS = [
        ("d", "toggle_dark", "Toggle Dark Mode"),
        ("ctrl+l", "clear_log", "Clear Log"),
        ("q", "request_quit", "Quit"),
    ]

    def compose(self) -> ComposeResult:
        """Create child widgets for the app."""
        logger.info(f"Composing Ekko TUI...")
        yield Header()
        yield Container( # Main layout
            Placeholder("Project Management / Selection", id="nav-pane"),
            VerticalScroll(
               Placeholder("Main Content / Output", id="main-pane"),
               Log(id="log-pane", max_lines=1000, markup=True),
            )
        )
        yield Footer()

    def on_mount(self) -> None:
        """Called when the app is mounted."""
        log_widget = self.query_one(Log)
        log_widget.write_line("[bold green]Ekko TUI Initialized.[/]")
        log_widget.write_line(f"[dim]Debug Log File: {LOG_FILE}[/]")
        # TODO: Add initial actions like connecting to backend/API

    def action_toggle_dark(self) -> None:
        """Toggle dark mode."""
        logger.debug("Toggling dark mode.")
        self.dark = not self.dark

    def action_clear_log(self) -> None:
         """Clear the log display."""
         log_widget = self.query_one(Log)
         log_widget.clear()
         logger.info("Log widget cleared by user.")
         log_widget.write_line("[italic]Log cleared.[/]")

    def action_request_quit(self) -> None:
         """Action to quit the application."""
         logger.info("Quit action invoked.")
         self.exit("User requested quit.")


if __name__ == "__main__":
    logger.info("--- Starting Ekko TUI Application ---")
    app = EkkoTUI()
    app.run()
    logger.info("--- Ekko TUI Application Exited ---")