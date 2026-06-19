#!/bin/bash

# =========================================================
# .glang Setup Script (Linux Edition - Production Grade)
# LLVM + Clang + Perl Interpreter + GLang Toolchain Manager
# =========================================================

FALLBACK_VERSION="20.1.8"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
GLANG_BIN="$ROOT_DIR/bin"
INSTALL_ROOT="$ROOT_DIR/g_clang_depend"
PERL_INSTALL_ROOT="$ROOT_DIR/g_perl_depend"
VERSION_FILE="$ROOT_DIR/glang_meta/VERSION.gwin"

# Initialize command-line flag defaults
DOCTOR=0
REPAIR=0
FORCE=0
BUILD_BINARIES=-1  # -1 = Unassigned (Will prompt unless flag specified)
SKIP_PERL=0
SKIP_LLVM=0

# ---------------------------------------------------------
# Help / Usage Menu
# ---------------------------------------------------------
show_help() {
    echo "Usage: ./setup.sh [OPTIONS]"
    echo ""
    echo "Production-grade toolchain environment wizard for GLang/Gawin."
    echo ""
    echo "Options:"
    echo "  -h, --help         Show this help message menu configuration and exit"
    echo "  --doctor           Execute an operational audit checking paths, versions, and dependencies"
    echo "  --repair           Trigger systematic restoration workflows on missing paths and binaries"
    echo "  --force            Force a clean re-download and isolated deployment of target stacks"
    echo "  --build            Bypass the execution prompt and immediately compile source binaries"
    echo "  --skip-build       Bypass the execution prompt and explicitly skip building binaries"
    echo "  --skip-perl        Bypass validation or standalone installation of the Perl interpreter"
    echo "  --skip-llvm        Bypass validation or standalone installation of the LLVM/Clang stack"
    echo ""
    echo "Examples:"
    echo "  ./setup.sh --build"
    echo "  ./setup.sh --skip-llvm --force"
    exit 0
}

# ---------------------------------------------------------
# Argument Parsing Matrix
# ---------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)       show_help ;;
        --doctor)        DOCTOR=1; shift ;;
        --repair)        REPAIR=1; shift ;;
        --force)         FORCE=1; shift ;;
        --build)         BUILD_BINARIES=1; shift ;;
        --skip-build)    BUILD_BINARIES=0; shift ;;
        --skip-perl)     SKIP_PERL=1; shift ;;
        --skip-llvm)     SKIP_LLVM=1; shift ;;
        *)               echo -e "\033[0;31m[FAIL] Unknown option: $1\033[0m"; echo "Use --help for usage details."; exit 1 ;;
    esac
done

# ---------------------------------------------------------
# Colors + Logging Subsystem
# ---------------------------------------------------------
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO] $1${NC}"; }
log_ok()    { echo -e "${GREEN}[ OK ] $1${NC}"; }
log_warn()  { echo -e "${YELLOW}[WARN] $1${NC}"; }
log_err()   { echo -e "${RED}[FAIL] $1${NC}"; }
log_blank() { echo -e "${NC}$1${NC}"; }

# ---------------------------------------------------------
# Runtime Version Discovery Resolvers
# ---------------------------------------------------------
get_latest_llvm_version() {
    log_info "Querying upstream GitHub API for latest LLVM release version info..."
    local version
    version=$(curl -s https://api.github.com/repos/llvm/llvm-project/releases/latest \
        | grep '"tag_name":' \
        | sed -E 's/.*"llvmorg-([^"]+)".*/\1/')

    if [ -z "$version" ]; then
        log_warn "Upstream discovery handshake failed -> Using configuration version $FALLBACK_VERSION"
        echo "$FALLBACK_VERSION"
    else
        log_ok "Latest discovered upstream LLVM release: $version"
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

get_perl_version() {
    if ! command -v perl >/dev/null 2>&1; then
        echo "none"
        return
    fi
    perl -e 'print $^V' 2>/dev/null | sed 's/v//' || echo "unknown"
}

get_glang_version() {
    if [ ! -f "$VERSION_FILE" ]; then
        echo "unknown"
        return
    fi
    grep -oE 'version\s*:=\s*"\s*([0-9]+\.[0-9]+\.[0-9]+)\s*"'$VERSION_FILE \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
        | head -n1
}

# ---------------------------------------------------------
# Safe Environment Variable Configuration Profiles
# ---------------------------------------------------------
add_to_path() {
    local target="$1"
    local shell_rc="$HOME/.bashrc"

    if [[ "$SHELL" == *zsh* ]]; then
        shell_rc="$HOME/.zshrc"
    fi

    if [ ! -d "$target" ]; then
        log_warn "Failed mapping directory reference to system profile path. Directory missing: $target"
        return
    fi

    if [[ ":$PATH:" == *":$target:"* ]]; then
        log_info "Path assignment verification clean: $target"
        return
    fi

    if grep -q "$target" "$shell_rc" 2>/dev/null; then
        log_info "Path assignment target already safely appended inside profile: $shell_rc"
        return
    fi

    echo "" >> "$shell_rc"
    echo "# Gawin Ecosystem Environment Configuration Paths" >> "$shell_rc"
    echo "export PATH=\"\$PATH:$target\"" >> "$shell_rc"

    log_ok "Successfully appended binary target pathing rules to $shell_rc"
    echo "      Target: $target"
}

# ---------------------------------------------------------
# Ecosystem Provisioning Engines (LLVM & Standalone Perl)
# ---------------------------------------------------------
install_llvm() {
    local version="$1"

    if command -v clang >/dev/null 2>&1 && [ "$FORCE" -ne 1 ]; then
        log_ok "Clang compiler engine installation validated on host system path environment."
        return
    fi

    mkdir -p "$INSTALL_ROOT"
    local archive="clang+llvm-$version-x86_64-linux-gnu-ubuntu-22.04.tar.xz"
    local url="https://github.com/llvm/llvm-project/releases/download/llvmorg-$version/$archive"

    log_info "Executing remote archive discovery for LLVM $version..."
    if ! curl -L "$url" -o "$INSTALL_ROOT/$archive"; then
        log_err "Target subsystem package distribution downpour initialization failed!"
        exit 1
    fi

    log_info "Extracting payload files directly into local environment target path storage..."
    tar -xJf "$INSTALL_ROOT/$archive" -C "$INSTALL_ROOT"
    rm -f "$INSTALL_ROOT/$archive"

    CLANG_PATH=$(find "$INSTALL_ROOT" -type d -name "bin" | head -n 1)
}

install_perl() {
    if command -v perl >/dev/null 2>&1 && [ "$FORCE" -ne 1 ]; then
        log_ok "Perl binary interpreter runtime validated on host system path environment."
        return
    fi

    if [ -d "$PERL_INSTALL_ROOT/bin" ] && [ "$FORCE" -ne 1 ]; then
        log_ok "Self-contained workspace Perl executable directory verified: $PERL_INSTALL_ROOT/bin"
        PERL_PATH="$PERL_INSTALL_ROOT/bin"
        return
    fi

    mkdir -p "$PERL_INSTALL_ROOT"
    local perl_ver="5.40.0"
    local archive="perl-$perl_ver.tar.gz"
    local url="https://www.cpan.org/src/5.0/$archive"

    log_info "Downloading stable, up-to-date Unix Perl Interpreter core from CPAN distributions..."
    if ! curl -L "$url" -o "$PERL_INSTALL_ROOT/$archive"; then
        log_err "Failed to download Perl distribution from remote mirror endpoints."
        exit 1
    fi

    log_info "Extracting production Perl distribution source packages..."
    tar -xzf "$PERL_INSTALL_ROOT/$archive" -C "$PERL_INSTALL_ROOT"
    
    log_info "Configuring, compiling, and bootstrapping local isolated Perl (this may take a moment)..."
    pushd "$PERL_INSTALL_ROOT/perl-$perl_ver" > /dev/null
    
    # Configure and build automatically without manual user configurations/prompts
    if ./Configure -des -Dprefix="$PERL_INSTALL_ROOT" -Dman1dir=none -Dman3dir=none >/dev/null && \
       make -j$(nproc 2>/dev/null || echo 2) >/dev/null && \
       make install >/dev/null; then
        log_ok "Local standalone Perl Interpreter environment instantiation finalized securely."
    else
        log_err "Critical compiler runtime breakdown while building standard Perl source tree modules."
        popd > /dev/null
        exit 1
    fi
    
    popd > /dev/null
    rm -rf "$PERL_INSTALL_ROOT/$archive" "$PERL_INSTALL_ROOT/perl-$perl_ver"
    PERL_PATH="$PERL_INSTALL_ROOT/bin"
}

# ---------------------------------------------------------
# Cross-Compilation Layer Toolchain Pipeline Build Engine
# ---------------------------------------------------------
invoke_toolchain_build() {
    echo ""
    log_info "=========================================================="
    log_info "      INITIALIZING GAWIN TOOLCHAIN COMPILATION PIPELINE   "
    log_info "=========================================================="

    local src_exec_dir="$ROOT_DIR/src_exec"
    local build_sh="$src_exec_dir/build.sh"

    if [ ! -f "$build_sh" ]; then
        log_err "Toolchain source compiler execution module script missing from directory: $build_sh"
        exit 1
    fi

    log_info "Spawning independent subshell environment context to execute build.sh inside: $src_exec_dir"
    pushd "$src_exec_dir" > /dev/null
    chmod +x "build.sh"
    if ! ./build.sh; then
        log_err "Source toolchain execution error: build.sh threw execution termination token."
        popd > /dev/null
        exit 1
    fi
    popd > /dev/null
    log_ok "Core system binaries successfully generated by build.sh workflows."

    local bin_dir="$ROOT_DIR/bin"
    log_info "Moving down-pipeline to evaluate execution files inside: $bin_dir"

    if [ ! -d "$bin_dir" ]; then
        log_warn "Expected runtime binary folder missing. Creating directory wrapper path..."
        mkdir -p "$bin_dir"
    fi

    pushd "$bin_dir" > /dev/null
    log_info "Executing toolchain post-build operations via local 'gstdo' script runtime..."
    if [ -f "./gstdo" ]; then
        chmod +x "./gstdo"
        if ! ./gstdo; then
            log_warn "Post-build environment helper 'gstdo' generated termination warning codes."
        else
            log_ok "Post-build 'gstdo' step successfully processed."
        fi
    else
        log_warn "'gstdo' initialization binary missing or omitted from execution stack targets."
    fi
    popd > /dev/null

    log_ok "All application binaries and structural compilation steps are complete."
    echo ""
}

# ---------------------------------------------------------
# Diagnostics and Verification (Doctor Engine Audit)
# ---------------------------------------------------------
run_doctor() {
    echo ""
    log_info "=== SETUP DOCTOR DIAGNOSTIC AUDIT ==="

    local clang_ver
    clang_ver=$(get_clang_version)
    log_info "clang version: $clang_ver"
    log_info "clang path:    $(command -v clang 2>/dev/null || echo 'Missing from active PATH scope')"

    local latest
    latest=$(get_latest_llvm_version)

    if [[ "$clang_ver" != "$latest"* && "$clang_ver" != "none" ]]; then
        log_warn "Version structural mismatch checked (Upstream recommends targeting version $latest)"
    else
        log_ok "System LLVM version structure matches target standard rules."
    fi

    echo ""
    log_info "=== PERL INTERPRETER STATUS ==="
    local perl_ver
    perl_ver=$(get_perl_version)
    log_info "perl version:  $perl_ver"
    log_info "perl path:     $(command -v perl 2>/dev/null || echo 'Missing from active PATH scope')"
    if [ "$perl_ver" = "none" ]; then
        log_err "No validated system Perl interpreter paths found on this system configuration."
    else
        log_ok "Perl Interpreter operational profile confirmed status OK."
    fi

    echo ""
    log_info "=== GAWIN INFO ==="
    log_info "gawin path:    $GLANG_BIN"
    log_info "gawin version: $(get_glang_version)"

    if [ -d "$GLANG_BIN" ]; then
        log_ok "Gawin framework executable build targets detected."
    else
        log_warn "Gawin framework executable build targets are empty or unpopulated."
    fi

    echo ""
    log_ok "System environment audit validation workflow complete."
    exit 0
}

# ---------------------------------------------------------
# RUNTIME ENGINE (MAIN Execution Script Workflow Block)
# ---------------------------------------------------------
echo ""
log_info "Gawin Production Setup Configuration Wizard Initializing..."

if [ "$DOCTOR" -eq 1 ]; then
    run_doctor
fi

if [ "$REPAIR" -eq 1 ]; then
    log_warn "System path repair flags detected... forcing full asset validation checks..."
    if [ "$SKIP_LLVM" -ne 1 ]; then rm -rf "$INSTALL_ROOT"; fi
    if [ "$SKIP_PERL" -ne 1 ]; then rm -rf "$PERL_INSTALL_ROOT"; fi
fi

# Resolve LLVM Pipeline Dependencies
if [ "$SKIP_LLVM" -ne 1 ]; then
    VERSION=$(get_latest_llvm_version)
    install_llvm "$VERSION"
fi

# Resolve Perl Pipeline Dependencies
if [ "$SKIP_PERL" -ne 1 ]; then
    install_perl
fi

# Fallback pathing extraction rules to inject active environment parameters cleanly
if [ "$SKIP_LLVM" -ne 1 ]; then
    if command -v clang >/dev/null 2>&1; then
        CLANG_PATH=$(dirname "$(command -v clang)")
    elif [ -d "$INSTALL_ROOT" ]; then
        CLANG_PATH=$(find "$INSTALL_ROOT" -type d -name "bin" | head -n 1)
    fi
fi

if [ "$SKIP_PERL" -ne 1 ]; then
    if command -v perl >/dev/null 2>&1; then
        PERL_PATH=$(dirname "$(command -v perl)")
    elif [ -d "$PERL_INSTALL_ROOT/bin" ]; then
        PERL_PATH="$PERL_INSTALL_ROOT/bin"
    fi
fi

# Inject configurations immediately into running shell environment variables to enable safe post-compilation pipelines
if [ -n "$CLANG_PATH" ]; then export PATH="$CLANG_PATH:$PATH"; fi
if [ -n "$PERL_PATH" ]; then export PATH="$PERL_PATH:$PATH"; fi

# Update Profile Configuration Targets
log_info "Updating system environment target profile path value allocations..."
if [ -n "$CLANG_PATH" ] && [ "$SKIP_LLVM" -ne 1 ]; then add_to_path "$CLANG_PATH"; fi
if [ -n "$PERL_PATH" ] && [ "$SKIP_PERL" -ne 1 ]; then add_to_path "$PERL_PATH"; fi
if [ -d "$GLANG_BIN" ]; then add_to_path "$GLANG_BIN"; fi

# Interactive Post-Installation Compilation Handshake
if [ "$BUILD_BINARIES" -eq -1 ]; then
    echo ""
    read -r -p "Do you want to compile and build all toolchain binaries and object files now? (y/n): " input_build
    case "$input_build" in
        [yY][eE][sS]|[yY]|1)
            BUILD_BINARIES=1
            ;;
        *)
            BUILD_BINARIES=0
            ;;
    esac
fi

if [ "$BUILD_BINARIES" -eq 1 ]; then
    invoke_toolchain_build
else
    log_info "Skipping compilation stages as requested by configuration setup properties."
fi

# ---------------------------------------------------------
# Run Summary Report Block
# ---------------------------------------------------------
log_blank ""
log_blank "=========================================================="
log_ok "Production environment setup sequence finalized cleanly."
if [ "$SKIP_LLVM" -ne 1 ]; then
    log_info "clang path:    $(command -v clang 2>/dev/null || echo 'Not refreshed in current subshell execution parameters')"
    log_info "clang version: $(get_clang_version)"
fi
if [ "$SKIP_PERL" -ne 1 ]; then
    log_info "perl path:     $(command -v perl 2>/dev/null || echo 'Not refreshed in current subshell execution parameters')"
    log_info "perl version:  $(get_perl_version)"
fi
log_info "gawin path:    $GLANG_BIN"
log_info "gawin version: $(get_glang_version)"
log_blank "=========================================================="
log_blank ""