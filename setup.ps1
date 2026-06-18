[CmdletBinding()]
param(
    [ValidateSet("user", "system")]
    [string]$Scope,

    [switch]$Force,
    [switch]$Doctor,
    [switch]$Repair
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =========================================================
# Globals
# =========================================================
$DefaultLLVMPath = Join-Path $env:ProgramFiles "LLVM\bin"
$GLangBin = Join-Path $PSScriptRoot "g_win_x86-64\bin"
$FallbackLLVM = "20.1.8"

# =========================================================
# Logging
# =========================================================
function Write-Log {
    param(
        [ValidateSet("INFO","OK","WARN","ERROR","BLANK")]
        [string]$Level,
        [string]$Message
    )

    switch ($Level) {
        "INFO"  { Write-Host "[INFO] $Message" -ForegroundColor Cyan }
        "OK"    { Write-Host "[ OK ] $Message" -ForegroundColor Green }
        "WARN"  { Write-Host "[WARN] $Message" -ForegroundColor Yellow }
        "ERROR" { Write-Host "[FAIL] $Message" -ForegroundColor Red }
        "BLANK" { Write-Host "$Message" -ForegroundColor Green }
    }
}

# =========================================================
# Admin check
# =========================================================
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Invoke-MakeAdmin {
    param([string]$ScopeArg)

    if ($ScopeArg -eq "system" -and -not (Test-IsAdmin)) {
        Write-Log WARN "Restarting as Administrator..."
        Start-Process powershell.exe -Verb RunAs -ArgumentList @(
            "-ExecutionPolicy", "Bypass",
            "-File", $PSCommandPath,
            "-Scope", $ScopeArg
        )
        exit
    }
}

# =========================================================
# Web helper
# =========================================================
function Invoke-SafeDownload {
    param($Uri, $OutFile)

    Write-Log INFO "Downloading: $Uri"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
}

# =========================================================
# LLVM version detection
# =========================================================
function Get-LatestLLVMVersion {
    try {
        Write-Log INFO "Fetching latest LLVM version..."

        $r = Invoke-RestMethod "https://api.github.com/repos/llvm/llvm-project/releases/latest"

        if (-not $r.tag_name) { throw "bad response" }

        $v = $r.tag_name -replace "llvmorg-", ""
        Write-Log OK "Latest LLVM: $v"
        return $v
    }
    catch {
        Write-Log WARN "GitHub failed → fallback $FallbackLLVM"
        return $FallbackLLVM
    }
}

function Get-ClangVersion {
    $cmd = Get-Command clang -ErrorAction SilentlyContinue
    if (-not $cmd) { return $null }

    $out = & clang --version 2>$null

    $m = [regex]::Match($out, "version\s+([0-9]+\.[0-9]+\.[0-9]+)")

    if ($m.Success) {
        return $m.Groups[1].Value
    }

    return "unknown"
}

function Get-GLangVersion {
    try {
        $versionFile = Join-Path $PSScriptRoot "glang_meta\VERSION.gwin"

        if (-not (Test-Path $versionFile)) {
            return "unknown"
        }

        $content = Get-Content $versionFile -Raw

        # matches: version := r"1.2.3"
        if ($content -match 'version\s*:=\s*"\s*([0-9]+\.[0-9]+\.[0-9]+)\s*"') {
            return $matches[1]
        }

        return "unknown"
    }
    catch {
        return "unknown"
    }
}

function Get-GLangInstallPath {
    return $GLangBin
}

# =========================================================
# PATH utilities (SAFE + PRUNING)
# =========================================================

function Get-PathList($scope) {
    $p = [Environment]::GetEnvironmentVariable("Path", $scope)
    if (-not $p) { return @() }
    return $p -split ';' | Where-Object { $_ -and $_.Trim() }
}

function Set-PathList($list, $scope) {
    $newPath = ($list | Select-Object -Unique) -join ';'
    [Environment]::SetEnvironmentVariable("Path", $newPath, $scope)
}

function Add-ToPathSafe {
    param(
        [string]$PathToAdd,
        [EnvironmentVariableTarget]$Scope
    )

    if (-not (Test-Path $PathToAdd)) {
        throw "Path missing: $PathToAdd"
    }

    $list = Get-PathList $Scope

    if ($list -contains $PathToAdd) {
        Write-Log INFO "Already in PATH: $PathToAdd"
        Set-PathList $list $Scope
        return
    }

    $list += $PathToAdd
    Set-PathList $list $Scope

    $env:Path = ($env:Path + ";" + $PathToAdd)

    Write-Log OK "Added to PATH: $PathToAdd"
}

# =========================================================
# Install LLVM
# =========================================================
function Install-LLVM {
    $version = Get-LatestLLVMVersion

    $winget = Get-Command winget -ErrorAction SilentlyContinue

    if ($winget) {
        Write-Log INFO "Installing LLVM via winget..."

        winget install LLVM.LLVM `
            --silent `
            --accept-source-agreements `
            --accept-package-agreements

        if ($LASTEXITCODE -eq 0) {
            Write-Log OK "LLVM installed via winget"
            return
        }

        Write-Log WARN "winget failed... fallback installer"
    }

    $file = "LLVM-$version-win64.exe"
    $url  = "https://github.com/llvm/llvm-project/releases/download/llvmorg-$version/$file"
    $tmp  = Join-Path $env:TEMP $file

    Invoke-SafeDownload $url $tmp

    Write-Log INFO "Running installer..."
    $p = Start-Process $tmp -ArgumentList "/S" -Wait -PassThru

    if ($p.ExitCode -ne 0) {
        throw "Installer failed: $($p.ExitCode)"
    }

    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    Write-Log OK "LLVM installed"
}

# =========================================================
# Clang test
# =========================================================
function Test-Clang {
    $cmd = Get-Command clang -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Log OK "clang found: $($cmd.Source)"
        return $true
    }

    Write-Log WARN "clang not found"
    return $false
}

# =========================================================
# Setup Doctor
# =========================================================
function Invoke-Doctor {
    Write-Log INFO "=== SETUP DOCTOR ==="

    $clang = Get-Command clang -ErrorAction SilentlyContinue

    if (-not $clang) {
        Write-Log ERROR "clang not installed"
        return
    }

    $ver = Get-ClangVersion

    Write-Log INFO "clang path: $($clang.Source)"
    Write-Log INFO "clang version: $ver"

    $latest = Get-LatestLLVMVersion

    if ($ver -and $ver -notlike "$latest*") {
        Write-Log WARN "Version mismatch (expected $latest)"
    }
    else {
        Write-Log OK "LLVM version OK"
    }

    if ($env:Path -notmatch "LLVM") {
        Write-Log WARN "LLVM not clearly in PATH"
    }

    Write-Log BLANK
    Write-Log INFO "=== GAWIN INFO ==="

    $glangPath = Get-GLangInstallPath
    $glangVer  = Get-GLangVersion

    Write-Log INFO "gawin path: $glangPath"
    Write-Log INFO "gawin version: $glangVer"

    if (Test-Path $glangPath) {
        Write-Log OK "gawin binaries found"
    } else {
        Write-Log WARN "gawin binaries missing"
    }

    Write-Log OK "Doctor complete"
    Write-Log BLANK
}

# =========================================================
# Resolve LLVM
# =========================================================
function Resolve-LLVMBin {
    $cmd = Get-Command clang -ErrorAction SilentlyContinue

    if ($cmd) {
        return Split-Path $cmd.Source -Parent
    }

    return $DefaultLLVMPath
}

# =========================================================
# MAIN
# =========================================================
try {

    # Ask for scope if not provided via CLI
    while (-not $Scope) {

        Write-Host ""
        $inputScope = Read-Host "Select install scope (user/system)"

        if ($inputScope -in @("user", "system")) {
            $Scope = $inputScope
        }
        else {
            Write-Log WARN "Invalid input. Please enter 'user' or 'system'."
        }
    }

    $scopeEnv = if ($Scope -eq "system") { "Machine" } else { "User" }

    Invoke-MakeAdmin $Scope

    Write-Log INFO "Starting setup (Scope=$scopeEnv)"
    Write-Log BLANK

    if ($Doctor) {
        Invoke-Doctor
        exit 0
    }

    if ($Repair) {
        Write-Log WARN "Repair mode enabled... reinstalling LLVM"
        Install-LLVM
    }

    $clangInstalled = Test-Clang

    if (-not $clangInstalled -or $Force) {
        Install-LLVM
    }

    if (-not $clangInstalled) {
        Write-Log WARN "Retrying install..."
        Install-LLVM
    }

    $llvmBin = Resolve-LLVMBin

    Write-Log INFO "Configuring PATH..."
    if (Test-Path $llvmBin) {
        Add-ToPathSafe $llvmBin $scopeEnv
    }

    if (Test-Path $GLangBin) {
        Add-ToPathSafe $GLangBin $scopeEnv
    }

    Write-Log BLANK
    Write-Log BLANK "=========================================="
    Write-Log OK "Setup complete"

    Write-Log INFO "clang path: $(Get-Command clang -ErrorAction SilentlyContinue | Select-Object -Expand Source)"
    Write-Log INFO "clang version: $(Get-ClangVersion)"

    Write-Log BLANK

    Write-Log INFO "gawin path: $(Get-GLangInstallPath)"
    Write-Log INFO "gawin version: $(Get-GLangVersion)"
    Write-Log BLANK "=========================================="
}
catch {
    Write-Log ERROR $_.Exception.Message
    exit 1
}

Pause