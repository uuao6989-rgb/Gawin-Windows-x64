<#
.SYNOPSIS
    Production-grade development ecosystem setup script for GLang/Gawin.
.DESCRIPTION
    Automates deployment of required platform binaries (LLVM/Clang Compiler Toolchain, 
    Perl Interpreter Environment), sanitizes system and user environment target paths, 
    and handles toolchain compilation tasks.
.PARAMETER Scope
    Target environment registry scope allocation. Acceptable strings: 'user' or 'system'.
.PARAMETER Force
    Forces clean re-download and execution of both LLVM and Perl dependencies.
.PARAMETER Doctor
    Executes an operational audit checking compiler paths, dependency versions, and environment configurations.
.PARAMETER Repair
    Triggers systematic restoration workflows on your missing system paths and binaries.
.PARAMETER Build
    Bypasses the execution prompt and immediately triggers compiling source binaries.
.PARAMETER SkipBuild
    Bypasses the execution prompt and explicitly skips compiler source binaries.
.PARAMETER SkipPerl
    Bypasses checking or downloading the Perl Interpreter entirely.
.PARAMETER SkipLLVM
    Bypasses checking or downloading the LLVM/Clang ecosystem entirely.
.EXAMPLE
    .\setup.ps1 -Scope user
.EXAMPLE
    .\setup.ps1 -Scope system -Build -Force
.EXAMPLE
    Get-Help .\setup.ps1 -Detailed
#>

[CmdletBinding()]
param(
    [ValidateSet("user", "system")]
    [string]$Scope,

    [switch]$Force,
    [switch]$Doctor,
    [switch]$Repair,
    [switch]$Build,
    [switch]$SkipBuild,
    [switch]$SkipPerl,
    [switch]$SkipLLVM
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =========================================================
# Globals & Configurations
# =========================================================
$DefaultLLVMPath = Join-Path $env:ProgramFiles "LLVM\bin"
$DefaultPerlPath = "C:\Strawberry\perl\bin"
$GLangBin        = Join-Path $PSScriptRoot "\bin"
$FallbackLLVM    = "20.1.8"
$FallbackPerlUrl = "https://strawberryperl.com/download/5.40.0.1/strawberry-perl-5.40.0.1-64bit.msi"

# =========================================================
# Logging Engine
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
        "BLANK" { Write-Host "$Message" -ForegroundColor White }
    }
}

# =========================================================
# System Privilege Verification
# =========================================================
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Invoke-MakeAdmin {
    param([string]$ScopeArg)

    if ($ScopeArg -eq "system" -and -not (Test-IsAdmin)) {
        Write-Log WARN "Elevated administration permissions required for system scope modification."
        Write-Log WARN "Restarting script with RunAs Administrator context..."
        Start-Process powershell.exe -Verb RunAs -ArgumentList @(
            "-ExecutionPolicy", "Bypass",
            "-File", $PSCommandPath,
            "-Scope", $ScopeArg
        )
        exit
    }
}

# =========================================================
# Network Data Management
# =========================================================
function Invoke-SafeDownload {
    param($Uri, $OutFile)

    Write-Log INFO "Downloading: $Uri"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
}

# =========================================================
# Dependency Resolution & Validation
# =========================================================
function Get-LatestLLVMVersion {
    try {
        Write-Log INFO "Querying upstream GitHub API for latest LLVM release version info..."
        $r = Invoke-RestMethod "https://api.github.com/repos/llvm/llvm-project/releases/latest"
        if (-not $r.tag_name) { throw "Invalid payload structure received." }

        $v = $r.tag_name -replace "llvmorg-", ""
        Write-Log OK "Latest discovered upstream LLVM release: $v"
        return $v
    }
    catch {
        Write-Log WARN "Upstream discovery handshake failed -> Using safe fallback configuration version $FallbackLLVM"
        return $FallbackLLVM
    }
}

function Get-ClangVersion {
    $cmd = Get-Command clang -ErrorAction SilentlyContinue
    if (-not $cmd) { return $null }

    $out = & clang --version 2>$null
    $m = [regex]::Match($out, "version\s+([0-9]+\.[0-9]+\.[0-9]+)")
    if ($m.Success) { return $m.Groups[1].Value }
    return "unknown"
}

function Test-Clang {
    $cmd = Get-Command clang -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Log OK "Clang installation validated: $($cmd.Source)"
        return $true
    }
    Write-Log WARN "Clang executable missing from executable target paths."
    return $false
}

function Test-Perl {
    $cmd = Get-Command perl -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Log OK "Perl installation validated: $($cmd.Source)"
        return $true
    }
    if (Test-Path $DefaultPerlPath) {
        Write-Log OK "Perl directory found at standard static location: $DefaultPerlPath"
        return $true
    }
    Write-Log WARN "Perl binary interpreter is completely missing from this machine environment."
    return $false
}

function Get-GLangVersion {
    try {
        $versionFile = Join-Path $PSScriptRoot "glang_meta\VERSION.gwin"
        if (-not (Test-Path $versionFile)) { return "unknown" }

        $content = Get-Content $versionFile -Raw
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
# PATH Configuration Suite
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
        throw "Failed mapping directory reference to system profile path. Directory missing: $PathToAdd"
    }

    $list = Get-PathList $Scope
    if ($list -contains $PathToAdd) {
        Write-Log INFO "Path assignment verification clean: $PathToAdd"
        Set-PathList $list $Scope
        return
    }

    $list += $PathToAdd
    Set-PathList $list $Scope
    $env:Path = ($env:Path + ";" + $PathToAdd)

    Write-Log OK "Environment variable PATH targets successfully updated: $PathToAdd"
}

# =========================================================
# Deployment Managers
# =========================================================
function Install-LLVM {
    $version = Get-LatestLLVMVersion
    $winget  = Get-Command winget -ErrorAction SilentlyContinue

    if ($winget) {
        Write-Log INFO "Executing silent LLVM subsystem acquisition via native winget clients..."
        winget install LLVM.LLVM --silent --accept-source-agreements --accept-package-agreements

        if ($LASTEXITCODE -eq 0) {
            Write-Log OK "LLVM installation completed natively."
            return
        }
        Write-Log WARN "Winget package routine exited abnormally; failing over to fallback script routines..."
    }

    $file = "LLVM-$version-win64.exe"
    $url  = "https://github.com/llvm/llvm-project/releases/download/llvmorg-$version/$file"
    $tmp  = Join-Path $env:TEMP $file

    Invoke-SafeDownload $url $tmp
    Write-Log INFO "Executing independent installer binary cleanly..."
    $p = Start-Process $tmp -ArgumentList "/S" -Wait -PassThru

    if ($p.ExitCode -ne 0) {
        throw "Target subsystem setup script failure! Subprocess returned execution error token: $($p.ExitCode)"
    }

    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    Write-Log OK "LLVM toolchain runtime installation completed successfully."
}

function Install-Perl {
    $winget = Get-Command winget -ErrorAction SilentlyContinue

    if ($winget) {
        Write-Log INFO "Executing silent Strawberry Perl environment instantiation via winget..."
        winget install StrawberryPerl.StrawberryPerl --silent --accept-source-agreements --accept-package-agreements

        if ($LASTEXITCODE -eq 0) {
            Write-Log OK "Strawberry Perl distribution finalized securely."
            return
        }
        Write-Log WARN "Winget package installation tracking error; processing custom standalone installation sequence..."
    }

    $file = "strawberry-perl-installer.msi"
    $tmp  = Join-Path $env:TEMP $file

    Invoke-SafeDownload $FallbackPerlUrl $tmp
    Write-Log INFO "Executing headless unattended MSI installation tracking sequence..."
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$tmp`" /qn /norestart" -Wait -PassThru

    # 0 is normal success, 3010 means standard windows configuration success pending platform restart
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
        throw "Headless MSI execution failed. Unhandled package installer exception token: $($p.ExitCode)"
    }

    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    Write-Log OK "Perl Interpreter core setup completed successfully."
}

# =========================================================
# Toolchain Post-Install Build Pipeline
# =========================================================
function Invoke-ToolchainBuild {
    Write-Log BLANK
    Write-Log INFO "=========================================================="
    Write-Log INFO "      INITIALIZING GAWIN TOOLCHAIN COMPILATION PIPELINE   "
    Write-Log INFO "=========================================================="
    
    $srcExecDir = Join-Path $PSScriptRoot "src_exec"
    $buildBat   = Join-Path $srcExecDir "build.bat"
    
    if (-not (Test-Path $buildBat)) {
        Write-Log ERROR "Toolchain source compiler file missing from path: $buildBat"
        throw "Aborting build sequence execution due to missing structural files."
    }
    
    Write-Log INFO "Spawning independent environment to execute build.bat inside: $srcExecDir"
    pushd $srcExecDir
    try {
        cmd.exe /c "build.bat"
        if ($LASTEXITCODE -ne 0) {
            throw "Source toolchain execution error: build.bat threw termination token $LASTEXITCODE"
        }
        Write-Log OK "Core binaries successfully generated by build.bat workflow."
    }
    finally {
        popd
    }

    $binDir = Join-Path $PSScriptRoot "bin"
    Write-Log INFO "Moving down-pipeline to evaluate execution files inside: $binDir"
    
    if (-not (Test-Path $binDir)) {
        Write-Log WARN "Expected runtime binary folder missing. Creating directory wrapper path..."
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    }
    
    pushd $binDir
    try {
        Write-Log INFO "Executing toolchain post-build operations via local 'gstdo' script runtime..."
        if (Test-Path "gstdo.exe") {
            & .\gstdo.exe
        } elseif (Test-Path "gstdo.bat") {
            cmd.exe /c "gstdo.bat"
        } else {
            cmd.exe /c "gstdo"
        }
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log WARN "Post-build environment helper 'gstdo' generated termination warning code ($LASTEXITCODE)."
        } else {
            Write-Log OK "Post-build 'gstdo' step successfully processed."
        }
    }
    catch {
        Write-Log ERROR "Unexpected crash during gstdo validation workflow: $_"
    }
    finally {
        popd
    }
    
    Write-Log OK "All application binaries and structural compilation steps are complete."
    Write-Log BLANK
}

# =========================================================
# Diagnostics and Verification (Doctor Engine)
# =========================================================
function Invoke-Doctor {
    Write-Log INFO "=== RUNNING SYSTEM SETUP DIAGNOSTIC AUDIT ==="

    $clang = Get-Command clang -ErrorAction SilentlyContinue
    if (-not $clang) {
        Write-Log ERROR "Clang compiler engine missing from machine profile path variables."
    } else {
        $ver = Get-ClangVersion
        Write-Log INFO "Clang Executable Location: $($clang.Source)"
        Write-Log INFO "Clang Version Signature: $ver"
        
        $latest = Get-LatestLLVMVersion
        if ($ver -and $ver -notlike "$latest*") {
            Write-Log WARN "Version structural mismatch checked (Upstream recommends targeting version $latest)"
        } else {
            Write-Log OK "System LLVM version structure matches target standard rules."
        }
    }

    if ($env:Path -notmatch "LLVM") { Write-Log WARN "LLVM binaries are not clearly configured in the active environment execution string." }

    Write-Log BLANK
    Write-Log INFO "=== PERL INTERPRETER STATUS ==="
    $perl = Get-Command perl -ErrorAction SilentlyContinue
    if ($perl) {
        Write-Log INFO "Perl Binary Location: $($perl.Source)"
        $perlVer = & perl -e "print $^V" 2>$null
        Write-Log INFO "Perl Version String: $perlVer"
        Write-Log OK "Perl Interpreter operational profile confirmed status OK."
    } elseif (Test-Path $DefaultPerlPath) {
        Write-Log OK "Perl interpreter directory found at ($DefaultPerlPath) but not active in profile environment execution strings yet."
    } else {
        Write-Log ERROR "No validated system Perl interpreter paths found on this system configuration."
    }

    Write-Log BLANK
    Write-Log INFO "=== LANGUAGE COMPILER METADATA (GAWIN) ==="
    $glangPath = Get-GLangInstallPath
    $glangVer  = Get-GLangVersion

    Write-Log INFO "Gawin Target Bin Path: $glangPath"
    Write-Log INFO "Gawin Working Metadata Version: $glangVer"

    if (Test-Path $glangPath) { Write-Log OK "Gawin language runtime distribution binaries detected." } 
    else { Write-Log WARN "Gawin framework executable build targets are empty or unpopulated." }

    Write-Log OK "System environment audit validation workflow complete."
    Write-Log BLANK
}

# =========================================================
# RUNTIME ENGINE (MAIN)
# =========================================================
try {
    # Interactive fallback prompt for targeting scope profiles
    while (-not $Scope) {
        Write-Host ""
        $inputScope = Read-Host "Select installation target access environment profile [user/system]"
        if ($inputScope.Trim().ToLower() -in @("user", "system")) {
            $Scope = $inputScope.Trim().ToLower()
        } else {
            Write-Log WARN "Input validation failure. Target profile parameters must read explicitly as 'user' or 'system'."
        }
    }

    $scopeEnv = if ($Scope -eq "system") { "Machine" } else { "User" }
    Invoke-MakeAdmin $Scope

    Write-Log INFO "Initializing production setup runtime routines (Registry Scope: $scopeEnv)..."
    Write-Log BLANK

    if ($Doctor) {
        Invoke-Doctor
        exit 0
    }

    if ($Repair) {
        Write-Log WARN "System path repair flags detected... forcing full asset validation checks..."
        if (-not $SkipLLVM) { Install-LLVM }
        if (-not $SkipPerl) { Install-Perl }
    }

    # Process LLVM Stack Setup
    if (-not $SkipLLVM) {
        $clangInstalled = Test-Clang
        if (-not $clangInstalled -or $Force) {
            Install-LLVM
        }
    }

    # Process Perl Interpreter Stack Setup
    if (-not $SkipPerl) {
        $perlInstalled = Test-Perl
        if (-not $perlInstalled -or $Force) {
            Install-Perl
        }
    }

    # Resolve Environment Paths Dynamically
    $llvmBin = if (Get-Command clang -ErrorAction SilentlyContinue) { 
        Split-Path (Get-Command clang).Source -Parent 
    } else { $DefaultLLVMPath }

    $perlBin = if (Get-Command perl -ErrorAction SilentlyContinue) { 
        Split-Path (Get-Command perl).Source -Parent 
    } else { $DefaultPerlPath }

    Write-Log INFO "Updating environment configuration profile path values..."
    if ((-not $SkipLLVM) -and (Test-Path $llvmBin)) { Add-ToPathSafe $llvmBin $scopeEnv }
    if ((-not $SkipPerl) -and (Test-Path $perlBin)) { Add-ToPathSafe $perlBin $scopeEnv }
    if (Test-Path $GLangBin) { Add-ToPathSafe $GLangBin $scopeEnv }

    # Handle Interactive Post-Installation Compilation Handshake
    $shouldBuild = $false
    if ($Build) {
        $shouldBuild = $true
    } elseif ($SkipBuild) {
        $shouldBuild = $false
    } else {
        Write-Host ""
        $inputBuild = Read-Host "Do you want to compile and build all toolchain binaries and object files now? (y/n)"
        if ($inputBuild.Trim().ToLower() -in @("y", "yes", "1")) {
            $shouldBuild = $true
        }
    }

    if ($shouldBuild) {
        Invoke-ToolchainBuild
    } else {
        Write-Log INFO "Skipping compilation stages as requested by configuration setup properties."
    }

    Write-Log BLANK
    Write-Log BLANK "=========================================="
    Write-Log OK "Production environment setup sequence finalized cleanly."

    if (-not $SkipLLVM) {
        Write-Log INFO "Clang Path: $(Get-Command clang -ErrorAction SilentlyContinue | Select-Object -Expand Source)"
        Write-Log INFO "Clang Version: $(Get-ClangVersion)"
    }
    if (-not $SkipPerl) {
        Write-Log INFO "Perl Path:  $(Get-Command perl -ErrorAction SilentlyContinue | Select-Object -Expand Source)"
    }
    Write-Log INFO "Gawin Path: $(Get-GLangInstallPath)"
    Write-Log INFO "Gawin Ver:  $(Get-GLangVersion)"
    Write-Log BLANK "=========================================="
}
catch {
    Write-Log ERROR "Fatal Script Exception Encountered: $($_.Exception.Message)"
    exit 1
}

Pause