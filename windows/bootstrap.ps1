#Requires -Version 7.0
<#
.SYNOPSIS
    Sets up a native Windows machine from this dotfiles repo.

.DESCRIPTION
    The Windows counterpart to `make` on macOS/Linux. It deliberately does not
    reuse the Makefile - it shares the cross-platform data files instead
    (install/code-extensions) and keeps everything else Windows-native.

    Every step is idempotent: running this twice should report "already ..."
    rather than redoing work.

    Anything configurable - paths, the oh-my-posh theme, the app list - lives
    in windows/config.json and windows/winget.json, not in this script.

.PARAMETER SkipApps
    Skip the winget import step.

.PARAMETER SkipExtensions
    Skip installing VS Code extensions.

.PARAMETER SkipProfile
    Skip linking the PowerShell profile.

.PARAMETER SkipMise
    Skip installing mise.

.PARAMETER SkipGit
    Skip the git / 1Password SSH agent configuration.

.EXAMPLE
    pwsh -File windows/bootstrap.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipApps,
    [switch]$SkipExtensions,
    [switch]$SkipProfile,
    [switch]$SkipMise,
    [switch]$SkipGit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

$script:Warnings = [System.Collections.Generic.List[string]]::new()

function Write-Step { param([string]$Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Info { param([string]$Message) Write-Host "    $Message" }
function Write-Ok { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Note {
    param([string]$Message)
    Write-Host "    ! $Message" -ForegroundColor Yellow
    $script:Warnings.Add($Message)
}

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

$script:RepoRoot = (Resolve-Path (Split-Path -Parent $PSScriptRoot)).Path
$script:ConfigPath = Join-Path $PSScriptRoot 'config.json'

if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
    throw "Missing configuration file: $script:ConfigPath"
}

$script:Config = Get-Content -LiteralPath $script:ConfigPath -Raw | ConvertFrom-Json

function Resolve-DotfilesPath {
    # Config values are repo-relative unless they start with ~ or are rooted.
    param([Parameter(Mandatory)][string]$Path)

    if ($Path.StartsWith('~')) {
        return Join-Path $HOME $Path.TrimStart('~', '/', '\')
    }
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return Join-Path $script:RepoRoot $Path
}

function Update-SessionPath {
    # winget installs land on the machine/user PATH but not in the running
    # process, so refresh from the registry between steps.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:PATH = (@($machine, $user) | Where-Object { $_ }) -join [System.IO.Path]::PathSeparator
}

function Get-AppCommand {
    param([Parameter(Mandatory)][string]$Name)
    Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Test-IsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-DeveloperMode {
    $key = 'HKLM:/SOFTWARE/Microsoft/Windows/CurrentVersion/AppModelUnlock'
    $value = Get-ItemProperty -Path $key -Name 'AllowDevelopmentWithoutDevLicense' -ErrorAction SilentlyContinue
    if ($null -eq $value) { return $false }
    return [bool]$value.AllowDevelopmentWithoutDevLicense
}

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

function Register-DotfilesRoot {
    # The profile needs to find this repo even when it was installed as a copy
    # rather than a symlink, so record the location for the user.
    Write-Step 'Recording the dotfiles location'

    $current = [Environment]::GetEnvironmentVariable('DOTFILES_DIR', 'User')
    if ($current -eq $script:RepoRoot) {
        Write-Ok "DOTFILES_DIR already set to $script:RepoRoot"
    }
    else {
        [Environment]::SetEnvironmentVariable('DOTFILES_DIR', $script:RepoRoot, 'User')
        Write-Ok "Set user DOTFILES_DIR to $script:RepoRoot"
    }
    $env:DOTFILES_DIR = $script:RepoRoot
}

function Get-InstalledWingetPackage {
    <#
        The set of package identifiers winget already knows about, as a
        lookup keyed on the lowercased id. Uses `winget export` because it
        answers for every source in one call and returns JSON, rather than
        needing the human-readable `winget list` table to be parsed.

        Returns $null if the export could not be produced, which the caller
        treats as "unknown" rather than "nothing is installed".
    #>
    param([Parameter(Mandatory)]$Winget)

    $exportPath = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-winget-installed-$PID.json"
    try {
        & $Winget.Source export --output $exportPath --accept-source-agreements --disable-interactivity *>&1 |
            Out-Null

        if (-not (Test-Path -LiteralPath $exportPath)) { return $null }

        $export = Get-Content -LiteralPath $exportPath -Raw | ConvertFrom-Json
        $installed = @{}
        foreach ($source in $export.Sources) {
            foreach ($package in $source.Packages) {
                $installed[$package.PackageIdentifier.ToLowerInvariant()] = $true
            }
        }
        return $installed
    }
    catch {
        return $null
    }
    finally {
        Remove-Item -LiteralPath $exportPath -Force -ErrorAction SilentlyContinue
    }
}

function Install-Apps {
    Write-Step 'Installing applications with winget'

    $winget = Get-AppCommand 'winget'
    if (-not $winget) {
        Write-Note 'winget not found. Install "App Installer" from the Microsoft Store, then re-run.'
        return
    }

    $manifestPath = Resolve-DotfilesPath $script:Config.wingetPackages
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Write-Note "Package manifest not found: $manifestPath"
        return
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $wantedCount = @($manifest.Sources | ForEach-Object { $_.Packages }).Count

    # Import only what is missing. Handing winget the full manifest every time
    # makes it try to *upgrade* everything already installed, which turns a
    # repeat run into a pile of avoidable work - and fails outright for
    # packages whose upgrade needs elevation or a closed application.
    # Upgrading stays a deliberate `winget upgrade`, not a side effect of
    # bootstrapping.
    $installed = Get-InstalledWingetPackage -Winget $winget
    $importPath = $manifestPath

    if ($null -eq $installed) {
        Write-Note 'Could not read the installed package list; handing winget the whole manifest.'
    }
    else {
        $sources = @()
        foreach ($source in $manifest.Sources) {
            $missing = @($source.Packages |
                    Where-Object { -not $installed.ContainsKey($_.PackageIdentifier.ToLowerInvariant()) })
            if ($missing.Count -gt 0) {
                $sources += [pscustomobject]@{
                    Packages      = $missing
                    SourceDetails = $source.SourceDetails
                }
            }
        }

        if ($sources.Count -eq 0) {
            Write-Ok "All $wantedCount packages already installed"
            return
        }

        $missingIds = @($sources | ForEach-Object { $_.Packages } | ForEach-Object { $_.PackageIdentifier })
        Write-Info "Missing: $($missingIds -join ', ')"

        $importPath = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-winget-import-$PID.json"
        [pscustomobject]@{
            '$schema'     = $manifest.'$schema'
            CreationDate  = (Get-Date -Format 'o')
            Sources       = $sources
            WinGetVersion = $manifest.WinGetVersion
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $importPath -Encoding utf8
    }

    Write-Info "Importing $importPath"

    $arguments = @(
        'import'
        '--import-file', $importPath
        '--accept-package-agreements'
        '--accept-source-agreements'
        '--disable-interactivity'
        '--ignore-versions'
        '--ignore-unavailable'
    )

    try {
        # Stream winget's output as it arrives - this step can run for minutes -
        # while still keeping a copy for the exit code check below.
        $output = @()
        & $winget.Source @arguments 2>&1 |
            ForEach-Object {
                $line = $_.ToString()
                $output += $line
                Write-Info $line
            }
        $exit = $LASTEXITCODE
    }
    finally {
        if ($importPath -ne $manifestPath) {
            Remove-Item -LiteralPath $importPath -Force -ErrorAction SilentlyContinue
        }
    }

    if ($exit -eq 0) {
        Write-Ok 'winget import completed'
        return
    }

    $failures = @($output | Where-Object { $_ -match 'Installer failed' -or $_ -match 'No package found matching' })
    if ($failures.Count -gt 0) {
        foreach ($failure in $failures) { Write-Note "winget: $failure" }
    }
    else {
        Write-Note "winget import exited with code $exit - check the output above."
    }
}

function Confirm-OhMyPosh {
    <#
        The profile drives the prompt through `oh-my-posh init`, which only
        exists from v7 onwards. Another package manager (scoop, chocolatey)
        can leave an older binary earlier on PATH than the one winget just
        installed, in which case the prompt silently falls back to the default
        one. Say so rather than leaving it to be discovered.
    #>
    Write-Step 'Checking the oh-my-posh on PATH'

    Update-SessionPath
    $omp = Get-AppCommand 'oh-my-posh'
    if (-not $omp) {
        Write-Note 'oh-my-posh is not on PATH yet - open a new shell.'
        return
    }

    $version = (& $omp.Source --version 2>&1 | Select-Object -First 1).ToString().Trim()
    $major = 0
    if ($version -match '^v?(\d+)') { $major = [int]$Matches[1] }

    if ($major -ge 7) {
        Write-Ok "oh-my-posh $version ($($omp.Source))"
        return
    }

    $others = @(Get-Command 'oh-my-posh' -CommandType Application -All -ErrorAction SilentlyContinue |
            Select-Object -Skip 1 -ExpandProperty Source)
    $hint = if ($others.Count -gt 0) { " A newer one is also on PATH at $($others -join ', ') but is shadowed." } else { '' }
    Write-Note "oh-my-posh $version at $($omp.Source) is too old - the profile needs v7 or newer for 'oh-my-posh init'.$hint Remove the old one (for a scoop install: scoop uninstall oh-my-posh) or reorder PATH."
}

function Install-LinkOrCopy {
    <#
        Put $Source at $Target, preferring a symlink and falling back to a copy.
        Returns what it did so the caller can report it.

        An unrelated file already at the target is backed up once. After that
        the copy belongs to the repo and later runs overwrite it, so refreshing
        a config file does not leave a trail of .bak files behind.
    #>
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Target
    )

    $backedUp = $false
    $existing = Get-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue
    if ($existing) {
        if ($existing.LinkType -eq 'SymbolicLink') {
            $resolved = if ($existing.LinkTarget) {
                (Resolve-Path -LiteralPath $existing.LinkTarget -ErrorAction SilentlyContinue).Path
            }
            if ($resolved -eq $Source) { return 'already-linked' }
            Remove-Item -LiteralPath $Target -Force
        }
        else {
            $same = (Get-Content -LiteralPath $Target -Raw -ErrorAction SilentlyContinue) -eq
                    (Get-Content -LiteralPath $Source -Raw)
            if ($same) { return 'already-copied' }

            $backup = "$Target.bak"
            if (-not (Test-Path -LiteralPath $backup)) {
                Move-Item -LiteralPath $Target -Destination $backup
                $backedUp = $true
            }
            else {
                Remove-Item -LiteralPath $Target -Force
            }
        }
    }

    try {
        New-Item -ItemType SymbolicLink -Path $Target -Value $Source -ErrorAction Stop | Out-Null
        if ($backedUp) { return 'linked-after-backup' }
        return 'linked'
    }
    catch {
        Copy-Item -LiteralPath $Source -Destination $Target -Force
        if ($backedUp) { return 'copied-after-backup' }
        return 'copied'
    }
}

function Install-XdgConfig {
    <#
        The Windows half of the Makefile's `stow -t "$(XDG_CONFIG_HOME)" config`,
        so config/ lands in the same place on every platform. mise in particular
        reads ~/.config/mise/config.toml on Windows as well as on macOS and linux.
    #>
    Write-Step 'Linking config files into XDG_CONFIG_HOME'

    $configDir = Join-Path $script:RepoRoot 'config'
    if (-not (Test-Path -LiteralPath $configDir)) {
        Write-Note "No config directory at $configDir"
        return
    }

    $xdg = Resolve-DotfilesPath $script:Config.xdgConfigHome
    if (-not (Test-Path -LiteralPath $xdg)) {
        New-Item -ItemType Directory -Path $xdg -Force | Out-Null
        Write-Info "Created $xdg"
    }

    $files = @(Get-ChildItem -LiteralPath $configDir -File -Recurse |
            Where-Object { $_.Name -ne '.placeholder' })

    if ($files.Count -eq 0) {
        Write-Ok 'Nothing to link'
        return
    }

    $unchanged = 0
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($configDir.Length).TrimStart('\', '/')
        $target = Join-Path $xdg $relative
        $targetDir = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        $result = Install-LinkOrCopy -Source $file.FullName -Target $target
        switch -Wildcard ($result) {
            'already-*' { $unchanged++ }
            '*-after-backup' { Write-Note "Backed up an existing $target to $target.bak" }
            default { Write-Info "$result $relative" }
        }
    }

    if ($unchanged -eq $files.Count) {
        Write-Ok "All $($files.Count) config file(s) already in place"
    }
    else {
        Write-Ok "Linked $($files.Count) config file(s) into $xdg"
    }
}

function Install-MiseTools {
    <#
        Install whatever config/mise/config.toml asks for. This is how the
        GitHub CLI arrives on every platform, since it is not in the Debian or
        Ubuntu archives.
    #>
    Update-SessionPath
    $mise = Get-AppCommand 'mise'
    if (-not $mise) { return }

    $miseConfig = Join-Path (Resolve-DotfilesPath $script:Config.xdgConfigHome) 'mise/config.toml'
    if (-not (Test-Path -LiteralPath $miseConfig)) {
        Write-Info 'No global mise config, skipping tool install'
        return
    }

    Write-Info 'Installing tools from the global mise config'
    & $mise.Source install 2>&1 | ForEach-Object { Write-Info $_.ToString() }
    if ($LASTEXITCODE -eq 0) {
        Write-Ok 'mise tools installed'
    }
    else {
        Write-Note "mise install exited with code $LASTEXITCODE"
    }

    Add-MiseShimsToPath -Mise $mise
}

function Add-MiseShimsToPath {
    <#
        `mise activate` only puts tools on PATH inside shells that ran it, which
        on Windows means an interactive PowerShell session and nothing else -
        not cmd, not VS Code tasks, not anything launched from Explorer. Putting
        the shims directory on the user PATH covers those, which is what a tool
        installed by winget or brew would have given us.

        Both mechanisms coexist: activate puts the real binaries ahead of the
        shims for interactive shells, and the shims answer everywhere else.
    #>
    param([Parameter(Mandatory)]$Mise)

    # Ask mise where its shims live rather than assuming a layout.
    $shims = $null
    try {
        $doctor = & $Mise.Source doctor --json 2>$null | Out-String
        if ($doctor.Trim()) { $shims = ($doctor | ConvertFrom-Json).dirs.shims }
    }
    catch {
        $shims = $null
    }

    if (-not $shims) {
        Write-Note 'Could not determine the mise shims directory; skipping the PATH update.'
        return
    }

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @($userPath -split ';' | Where-Object { $_ })

    if ($entries -contains $shims) {
        Write-Ok "mise shims already on PATH ($shims)"
        return
    }

    [Environment]::SetEnvironmentVariable('Path', (@($entries) + $shims) -join ';', 'User')
    Write-Ok "Added the mise shims directory to your PATH ($shims)"
    Write-Info 'Tools installed by mise are available outside PowerShell in new processes.'
    Update-SessionPath
}

function Install-Mise {
    Write-Step 'Installing mise'

    Update-SessionPath
    $mise = Get-AppCommand 'mise'
    if ($mise) {
        Write-Ok "mise already installed ($($mise.Source))"
        Install-MiseTools
        return
    }

    $winget = Get-AppCommand 'winget'
    if (-not $winget) {
        Write-Note 'winget not found, cannot install mise.'
        return
    }

    $id = $script:Config.mise.wingetId
    Write-Info "Installing $id"
    & $winget.Source install --id $id --exact --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 |
        ForEach-Object { Write-Info $_.ToString() }

    Update-SessionPath
    if (Get-AppCommand 'mise') {
        Write-Ok 'mise installed'
    }
    else {
        Write-Note 'mise was installed but is not on PATH yet - open a new shell.'
    }
}

function Install-VSCodeExtensions {
    Write-Step 'Installing VS Code extensions'

    Update-SessionPath
    $code = Get-AppCommand 'code'
    if (-not $code) {
        Write-Note 'The "code" command was not found on PATH. Open VS Code once (or restart the shell) and re-run.'
        return
    }

    $listPath = Resolve-DotfilesPath $script:Config.vscodeExtensions
    if (-not (Test-Path -LiteralPath $listPath)) {
        Write-Note "Extension list not found: $listPath"
        return
    }

    # Shared with the macOS/Linux tracks - do not duplicate this list here.
    $wanted = @(Get-Content -LiteralPath $listPath |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith('#') })

    $installed = @(& $code.Source --list-extensions 2>$null |
            ForEach-Object { $_.Trim().ToLowerInvariant() })

    $missing = @($wanted | Where-Object { $installed -notcontains $_.ToLowerInvariant() })

    if ($missing.Count -eq 0) {
        Write-Ok "All $($wanted.Count) extensions already installed"
        return
    }

    foreach ($extension in $missing) {
        Write-Info "Installing $extension"
        & $code.Source --install-extension $extension --force | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Note "Failed to install VS Code extension: $extension"
        }
    }
    Write-Ok "Installed $($missing.Count) extension(s); $($wanted.Count - $missing.Count) already present"
}

function Install-Profile {
    Write-Step 'Linking the PowerShell profile'

    $source = Resolve-DotfilesPath $script:Config.profileSource
    if (-not (Test-Path -LiteralPath $source)) {
        Write-Note "Profile source not found: $source"
        return
    }
    $source = (Resolve-Path -LiteralPath $source).Path

    $target = $PROFILE.CurrentUserAllHosts
    $targetDir = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Write-Info "Created $targetDir"
    }

    # A copied profile has no link back to the repo, and the DOTFILES_DIR user
    # environment variable only reaches shells started after this run. Drop a
    # pointer file beside the profile so it can always find the repo.
    $pointer = Join-Path $targetDir '.dotfiles-path'
    $pointerValue = if (Test-Path -LiteralPath $pointer) { (Get-Content -LiteralPath $pointer -Raw).Trim() }
    if ($pointerValue -ne $script:RepoRoot) {
        Set-Content -LiteralPath $pointer -Value $script:RepoRoot -Encoding utf8 -NoNewline
        Write-Info "Wrote $pointer"
    }

    # Anything we installed previously carries this marker, so it can be
    # replaced without ceremony. Anything else is the user's and gets backed
    # up, matching what the Makefile link-files target does on Unix.
    $marker = 'managed by the dotfiles repo'
    $existing = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue

    if ($existing) {
        if ($existing.LinkType -eq 'SymbolicLink') {
            $linkTarget = $existing.LinkTarget
            $resolved = if ($linkTarget) {
                (Resolve-Path -LiteralPath $linkTarget -ErrorAction SilentlyContinue).Path
            }
            if ($resolved -eq $source) {
                Write-Ok "Already symlinked: $target"
                return
            }
            Write-Info "Replacing symlink that pointed at $linkTarget"
            Remove-Item -LiteralPath $target -Force
        }
        else {
            $existingContent = Get-Content -LiteralPath $target -Raw -ErrorAction SilentlyContinue
            $sourceContent = Get-Content -LiteralPath $source -Raw

            if ($existingContent -eq $sourceContent) {
                Write-Ok "Already installed as a copy: $target"
                return
            }

            if ($existingContent -and $existingContent.Contains($marker)) {
                Write-Info 'Refreshing the managed copy of the profile'
                Remove-Item -LiteralPath $target -Force
            }
            else {
                $backup = "$target.bak"
                if (Test-Path -LiteralPath $backup) {
                    $backup = "$target.$(Get-Date -Format 'yyyyMMddHHmmss').bak"
                }
                Move-Item -LiteralPath $target -Destination $backup
                Write-Note "Backed up your existing profile to $backup"
            }
        }
    }

    try {
        New-Item -ItemType SymbolicLink -Path $target -Value $source -ErrorAction Stop | Out-Null
        Write-Ok "Symlinked $target -> $source"
    }
    catch {
        Copy-Item -LiteralPath $source -Destination $target -Force
        $reason = if (Test-IsElevated) { 'symlink creation was refused even though this shell is elevated' }
        elseif (Test-DeveloperMode) { 'symlink creation was refused even though Developer Mode is on' }
        else { 'Developer Mode is off and this shell is not elevated' }
        Write-Info "Copied $source -> $target"
        Write-Note "Copied the profile instead of symlinking it ($reason). Re-run this script after editing windows/Microsoft.PowerShell_profile.ps1, or turn on Developer Mode (Settings > System > For developers) to get a live symlink."
    }
}

function Set-GitSshAgent {
    # The Windows equivalent of the SSH_AUTH_SOCK export in dotfiles/.zshrc.
    # 1Password exposes its agent on a named pipe, and the ssh that ships with
    # Git for Windows cannot talk to one, so git is pointed at the Windows
    # OpenSSH client instead.
    Write-Step 'Configuring git to use the 1Password SSH agent'

    Update-SessionPath
    $git = Get-AppCommand 'git'
    if (-not $git) {
        Write-Note 'git not found on PATH - open a new shell and re-run.'
        return
    }

    $sshCommand = $script:Config.git.sshCommand
    if (-not (Test-Path -LiteralPath $sshCommand)) {
        Write-Note "OpenSSH client not found at $sshCommand. Add it via Settings > System > Optional features > OpenSSH Client."
    }

    # git needs the value quoted if the path contains spaces.
    $desired = if ($sshCommand -match '\s') { '"' + $sshCommand + '"' } else { $sshCommand }

    $current = & $git.Source config --global --get core.sshCommand 2>$null | Select-Object -First 1
    if ($current -eq $desired) {
        Write-Ok "git core.sshCommand already set to $desired"
    }
    else {
        & $git.Source config --global core.sshCommand $desired
        Write-Ok "Set git core.sshCommand to $desired"
    }

    # Report whether the agent is actually listening. Turning it on is a manual
    # step inside 1Password (Settings > Developer > Use the SSH agent).
    $pipePath = $script:Config.git.agentPipe
    $pipeName = Split-Path -Leaf $pipePath
    $pipeDir = (Split-Path -Parent $pipePath) + [System.IO.Path]::DirectorySeparatorChar
    $running = $false
    try {
        $running = @([System.IO.Directory]::GetFiles($pipeDir) |
                Where-Object { (Split-Path -Leaf $_) -eq $pipeName }).Count -gt 0
    }
    catch {
        $running = $false
    }

    if ($running) {
        Write-Ok "1Password SSH agent is listening on $pipePath"
    }
    else {
        Write-Note "Nothing is listening on $pipePath. Turn on 'Use the SSH agent' in 1Password (Settings > Developer)."
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

Write-Host 'dotfiles - Windows bootstrap' -ForegroundColor Magenta
Write-Info "Repo:       $script:RepoRoot"
Write-Info "PowerShell: $($PSVersionTable.PSVersion)"
Write-Info "Elevated:   $(Test-IsElevated)"
Write-Info "Dev Mode:   $(Test-DeveloperMode)"

Register-DotfilesRoot
if (-not $SkipApps) { Install-Apps }
if (-not $SkipApps) { Confirm-OhMyPosh }
# config/ has to be in place before mise is asked to install what it declares.
if (-not $SkipProfile) { Install-XdgConfig }
if (-not $SkipMise) { Install-Mise }
if (-not $SkipExtensions) { Install-VSCodeExtensions }
if (-not $SkipProfile) { Install-Profile }
if (-not $SkipGit) { Set-GitSshAgent }

Write-Step 'Done'
if ($script:Warnings.Count -gt 0) {
    Write-Host "    Finished with $($script:Warnings.Count) thing(s) worth a look:" -ForegroundColor Yellow
    foreach ($warning in $script:Warnings) { Write-Host "      - $warning" -ForegroundColor Yellow }
}
else {
    Write-Ok 'Everything is in place.'
}
Write-Info 'Open a new PowerShell 7 session to pick up the profile.'
