python := env_var_or_default("PYTHON_BIN", ".venv/bin/python")
py := python

default:
    just --list

check:
    PYTHONPYCACHEPREFIX=.pycache {{py}} -m compileall -q src

[unix]
smoke:
    PAS_APP_DATA_DIR=.pas-smoke {{py}} -m pas_automation.cli --template-dir . --config config.example.toml slack test --dry-run
    PAS_APP_DATA_DIR=.pas-smoke {{py}} -m pas_automation.cli --template-dir . --config config.example.toml jira today --dry-run

clean:
    find . -type d -name __pycache__ -prune -exec rm -rf {} +
    rm -rf .pycache build dist .pas-smoke *.spec

status:
    git status --short --ignored

setup:
    python3.13 -m venv .venv

install-dev:
    .venv/bin/python -m pip install --upgrade pip
    .venv/bin/python -m pip install -e .
    .venv/bin/python -m pip install pyinstaller

package-local:
    {{py}} -m PyInstaller --clean --onefile --paths src --name pas src/pas_automation/cli.py

[unix]
macos-app-build:
    swift build -c release --package-path apps/macos/PASMenuBar
