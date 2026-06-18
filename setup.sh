#!/bin/bash

# =========================================================
# .glang Setup Script (Linux Edition - Unified)
# LLVM + Clang + GLang Toolchain Manager
# =========================================================

FALLBACK_VERSION="20.1.8"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
GLANG_BIN="$ROOT_DIR/g_linux_x86-64/bin"
INSTALL_ROOT="$ROOT_DIR/g_clang_depend"
VERSION_FILE="$ROOT_DIR/glang_meta/VERSION.gwin"

DOCTOR=0
REPAIR=0
FORCE=0

# ---------------------------------------------------------
# Args
# ---------------------------------------------------------
for arg in "$@"; do
    case "$arg" in
        --doctor) DOCTOR=1 ;;
        --repair) REPAIR=1 ;;
        --force) FORCE=1 ;;
    esac
done

# ---------------------------------------------------------
# Colors + Logging
# ---------------------------------------------------------
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${CYAN}[INFO] $1${NC}"; }
log_ok()   { echo -e "${GREEN}[ OK ] $1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
log_err()  { echo -e "${RED}[FAIL] $1${NC}"; }
log_blank() { echo -e "${GREEN}$1${NC}"; }

# ---------------------------------------------------------
# Version helpers
# ---------------------------------------------------------
get_latest_llvm_version() {
    log_info "Checking latest LLVM version..."

    local version
    version=$(curl -s https://api.github.com/repos/llvm/llvm-project/releases/latest \
        | grep '"tag_name":' \
        | sed -E 's/.*"llvmorg-([^"]+)".*/\1/')

    if [ -z "$version" ]; then
        log_warn "GitHub failed -> fallback $FALLBACK_VERSION"
        echo "$FALLBACK_VERSION"
    else
        log_ok "Latest LLVM: $version"
        echo "$version"
    fi
}

get_clang_version() {
    if ! command -v clang >/dev/null 2>&1; then
        echo "none"
        return
    fi

    clang --version | head -n1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" || echo "unknown"
}

get_glang_version() {
    if [ ! -f "$VERSION_FILE" ]; then
        echo "unknown"
        return
    fi

    # expected: version := r"1.2.3"
    grep -oE 'version\s*:=\s*"\s*([0-9]+\.[0-9]+\.[0-9]+)\s*"'"$VERSION_FILE" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
        | head -n1
}

# ---------------------------------------------------------
# PATH helper (safe, no duplicates)
# ---------------------------------------------------------
add_to_path() {
    local target="$1"
    local shell_rc="$HOME/.bashrc"

    if [[ "$SHELL" == *zsh* ]]; then
        shell_rc="$HOME/.zshrc"
    fi

    if [ ! -d "$target" ]; then
        log_warn "Missing path: $target"
        return
    fi

    # already in runtime PATH?
    if [[ ":$PATH:" == *":$target:"* ]]; then
        log_info "Already in PATH: $target"
        return
    fi

    # already in rc file?
    if grep -q "$target" "$shell_rc" 2>/dev/null; then
        log_info "Already persisted in $shell_rc"
        return
    fi

    echo "" >> "$shell_rc"
    echo "# gawin setup" >> "$shell_rc"
    echo "export PATH=\"\$PATH:$target\"" >> "$shell_rc"

    log_ok "Added to $shell_rc"
    echo "      $target"
}

# ---------------------------------------------------------
# LLVM install
# ---------------------------------------------------------
install_llvm() {
    local version="$1"

    if command -v clang >/dev/null 2>&1 && [ "$FORCE" -ne 1 ]; then
        log_ok "clang already installed"
        return
    fi

    mkdir -p "$INSTALL_ROOT"

    local archive="clang+llvm-$version-x86_64-linux-gnu-ubuntu-22.04.tar.xz"
    local url="https://github.com/llvm/llvm-project/releases/download/llvmorg-$version/$archive"

    log_info "Downloading LLVM $version..."

    if ! curl -L "$url" -o "$INSTALL_ROOT/$archive"; then
        log_err "Download failed"
        exit 1
    fi

    log_info "Extracting..."
    tar -xJf "$INSTALL_ROOT/$archive" -C "$INSTALL_ROOT"

    CLANG_PATH=$(find "$INSTALL_ROOT" -type d -name "bin" | head -n 1)
}

# ---------------------------------------------------------
# Doctor
# ---------------------------------------------------------
run_doctor() {
    echo ""
    log_info "=== SETUP DOCTOR ==="

    local clang_ver
    clang_ver=$(get_clang_version)

    log_info "clang version: $clang_ver"
    log_info "clang path: $(command -v clang 2>/dev/null)"

    local latest
    latest=$(get_latest_llvm_version)

    if [[ "$clang_ver" != "$latest"* && "$clang_ver" != "none" ]]; then
        log_warn "LLVM mismatch (expected $latest)"
    else
        log_ok "LLVM OK"
    fi

    echo ""
    log_info "=== GAWIN INFO ==="
    log_info "gawin path: $GLANG_BIN"
    log_info "gawin version: $(get_glang_version)"

    if [ -d "$GLANG_BIN" ]; then
        log_ok "gawin binaries found"
    else
        log_warn "gawin binaries missing"
    fi

    echo ""
    log_ok "Doctor complete"
    exit 0
}

# ---------------------------------------------------------
# MAIN
# ---------------------------------------------------------
echo ""
log_info "gawin setup wizard"

if [ "$DOCTOR" -eq 1 ]; then
    run_doctor
fi

VERSION=$(get_latest_llvm_version)

if [ "$REPAIR" -eq 1 ]; then
    log_warn "Repair mode -> reinstall LLVM"
    rm -rf "$INSTALL_ROOT"
fi

install_llvm "$VERSION"

# ---------------------------------------------------------
# PATH setup
# ---------------------------------------------------------
if [ -n "$CLANG_PATH" ]; then
    log_info "Configuring LLVM PATH..."
    add_to_path "$CLANG_PATH"
fi

if [ -d "$GLANG_BIN" ]; then
    log_info "Configuring Gawin PATH..."
    add_to_path "$GLANG_BIN"
else
    log_warn "Gawin not found: $GLANG_BIN"
fi

# ---------------------------------------------------------
# Summary
# ---------------------------------------------------------
log_blank ""
log_blank "=========================================="
log_ok "Setup complete"
log_info "clang path: $(command -v clang 2>/dev/null)"
log_info "clang version: $(get_clang_version)"
log_blank ""
log_info "gawin path: $GLANG_BIN"
log_info "gawin version: $(get_glang_version)"
log_blank "=========================================="
log_blank ""