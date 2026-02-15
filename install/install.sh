#!/usr/bin/env bash
# Spotter installer - bootstraps the `spotter` launcher without cloning the repo.
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/marot/spotter/main"
BIN_DIR="${HOME}/.local/bin"
BUNDLE_DIR="${HOME}/.local/share/spotter/bundle/main"

echo "Installing Spotter launcher..."

mkdir -p "${BIN_DIR}" "${BUNDLE_DIR}/otel" "${BUNDLE_DIR}/dolt"

# Download launcher binary
curl -fsSL "${REPO_RAW}/install/spotter" -o "${BIN_DIR}/spotter"
chmod +x "${BIN_DIR}/spotter"

# Download bundle files
curl -fsSL "${REPO_RAW}/install/bundle/compose.yml"       -o "${BUNDLE_DIR}/compose.yml"
curl -fsSL "${REPO_RAW}/install/bundle/compose.debug.yml" -o "${BUNDLE_DIR}/compose.debug.yml"
curl -fsSL "${REPO_RAW}/install/bundle/otel/collector.yaml" -o "${BUNDLE_DIR}/otel/collector.yaml"
curl -fsSL "${REPO_RAW}/install/bundle/dolt/dolt-init.sql"  -o "${BUNDLE_DIR}/dolt/dolt-init.sql"

echo ""
echo "Spotter installed successfully!"
echo ""
echo "Next steps:"
SHELL_NAME="$(basename "${SHELL:-bash}")"
case "${SHELL_NAME}" in
  zsh)
    echo "  1. Run this command:"
    echo "     if ! grep -qxF 'export PATH=\"$HOME/.local/bin:$PATH\"' ~/.zshrc; then"
    echo "       echo 'export PATH=\"$HOME/.local/bin:$PATH\"' >> ~/.zshrc"
    echo "     fi"
    echo "     source ~/.zshrc"
    ;;
  bash)
    echo "  1. Run this command:"
    echo "     if ! grep -qxF 'export PATH=\"$HOME/.local/bin:$PATH\"' ~/.bashrc; then"
    echo "       echo 'export PATH=\"$HOME/.local/bin:$PATH\"' >> ~/.bashrc"
    echo "     fi"
    echo "     source ~/.bashrc"
    ;;
  *)
    echo "  1. Append ~/.local/bin to your shell path manually (current shell: ${SHELL_NAME})"
    ;;
esac
echo "  2. export SPOTTER_ANTHROPIC_API_KEY=sk-ant-..."
echo "  3. cd /path/to/target-repo"
echo "  4. spotter"
