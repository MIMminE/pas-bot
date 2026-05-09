python := env_var_or_default("PYTHON_BIN", "python3")
bundled_python := "C:\\Users\\harun\\.cache\\codex-runtimes\\codex-primary-runtime\\dependencies\\python\\python.exe"

windows_python := if path_exists(bundled_python) {
    bundled_python
} else {
    "python"
}

py := if os() == "windows" {
    windows_python
} else {
    python
}

default:
    just --list

check:
    {{py}} -m compileall -q src

smoke:
    {{py}} -m pas_automation.cli --config config.example.toml --env .env.example slack test --dry-run
    {{py}} -m pas_automation.cli --config config.example.toml --env .env.example jira today --dry-run

[windows]
clean:
    powershell -NoProfile -Command "Get-ChildItem -Recurse -Directory -Filter __pycache__ -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force; Remove-Item -Recurse -Force build, dist -ErrorAction SilentlyContinue; Remove-Item -Force *.spec -ErrorAction SilentlyContinue"

[unix]
clean:
    find . -type d -name __pycache__ -prune -exec rm -rf {} +
    rm -rf build dist *.spec

status:
    git status --short --ignored

setup:
    {{py}} -m venv .venv

[windows]
install-dev:
    .venv\Scripts\python.exe -m pip install --upgrade pip
    .venv\Scripts\python.exe -m pip install -e .
    .venv\Scripts\python.exe -m pip install pyinstaller

[unix]
install-dev:
    .venv/bin/python -m pip install --upgrade pip
    .venv/bin/python -m pip install -e .
    .venv/bin/python -m pip install pyinstaller

package-local:
    {{py}} -m PyInstaller --clean --onefile --paths src --name pas src/pas_automation/cli.py

[unix]
macos-app-build:
    swift build -c release --package-path apps/macos/PASMenuBar
