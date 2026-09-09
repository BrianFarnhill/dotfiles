# ---------------------------------------------------------------------------
# PowerShell profile - managed by the dotfiles repo.
#
# Installed to $PROFILE.CurrentUserAllHosts by windows/bootstrap.ps1, either as
# a symlink (Developer Mode / elevated) or as a copy. This is the Windows
# counterpart to dotfiles/.zshrc; keep the two roughly in step.
#
# Everything configurable (theme, editor, local-profile path) lives in
# windows/config.json, not in here.
# ---------------------------------------------------------------------------

function Test-DotfilesRoot {
    param([string]$Path)
    return $Path -and (Test-Path (Join-Path $Path 'windows/config.json'))
}

function Resolve-DotfilesRoot {
    # 1. Explicit pointer in the environment.
    if (Test-DotfilesRoot $env:DOTFILES_DIR) {
        return (Resolve-Path $env:DOTFILES_DIR).Path
    }

    if ($PSCommandPath) {
        # 2. The pointer file bootstrap.ps1 drops next to the profile. This is
        #    what makes the "copy" install mode work: a copied profile has no
        #    link back to the repo, and the DOTFILES_DIR user environment
        #    variable is not visible to shells that were already open when
        #    bootstrap ran.
        $pointer = Join-Path (Split-Path -Parent $PSCommandPath) '.dotfiles-path'
        if (Test-Path -LiteralPath $pointer) {
            $candidate = (Get-Content -LiteralPath $pointer -Raw).Trim()
            if (Test-DotfilesRoot $candidate) {
                return (Resolve-Path $candidate).Path
            }
        }

        # 3. Symlink install: follow this file back to the repo.
        $item = Get-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
        $self = if ($item -and $item.LinkTarget) { $item.LinkTarget } else { $PSCommandPath }
        $candidate = Split-Path -Parent (Split-Path -Parent $self)
        if (Test-DotfilesRoot $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    return $null
}

$script:DotfilesRoot = Resolve-DotfilesRoot

if (-not $script:DotfilesRoot) {
    Write-Warning 'dotfiles: could not locate the repo (set $env:DOTFILES_DIR or re-run windows/bootstrap.ps1). Skipping profile setup.'
    return
}

$env:DOTFILES_DIR = $script:DotfilesRoot
$script:DotfilesConfig = Get-Content -LiteralPath (Join-Path $script:DotfilesRoot 'windows/config.json') -Raw |
    ConvertFrom-Json

function Resolve-DotfilesPath {
    param([Parameter(Mandatory)][string]$Path)

    if ($Path.StartsWith('~')) {
        return Join-Path $HOME $Path.TrimStart('~', '/', '\')
    }
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return Join-Path $script:DotfilesRoot $Path
}

# --- editor ----------------------------------------------------------------
# Mirrors: export EDITOR="code --wait"
if ($script:DotfilesConfig.editor) {
    $env:EDITOR = $script:DotfilesConfig.editor
    $env:VISUAL = $script:DotfilesConfig.editor
}

# --- XDG -------------------------------------------------------------------
# Mirrors: export XDG_CONFIG_HOME="$HOME/.config"
if ($script:DotfilesConfig.xdgConfigHome) {
    $env:XDG_CONFIG_HOME = Resolve-DotfilesPath $script:DotfilesConfig.xdgConfigHome
}

# --- prompt (oh-my-posh, standing in for powerlevel10k) --------------------
$ompCommand = Get-Command oh-my-posh -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($ompCommand) {
    $theme = Resolve-DotfilesPath $script:DotfilesConfig.ohMyPoshTheme
    if (Test-Path -LiteralPath $theme) {
        # `init` only exists from oh-my-posh v7 onwards. An older binary
        # earlier on PATH (a stale scoop shim, say) treats this as a request
        # to render a prompt and cheerfully exits 0, so check the output for a
        # marker from the real init script rather than trusting the exit code.
        $init = (& $ompCommand.Source init pwsh --config $theme --print 2>&1) | Out-String
        if ($LASTEXITCODE -eq 0 -and $init -match 'Set-PoshContext') {
            try {
                Invoke-Expression $init
            } catch {
                Write-Warning "dotfiles: oh-my-posh init failed: $_"
            }
        } else {
            Write-Warning "dotfiles: '$($ompCommand.Source) init' did not return an init script. oh-my-posh v7 or newer is required; run 'oh-my-posh --version' to see which one is first on PATH."
        }
    } else {
        Write-Warning "dotfiles: oh-my-posh theme not found at $theme"
    }
}

# --- mise ------------------------------------------------------------------
# Mirrors: eval "$(mise activate zsh)"
$miseCommand = Get-Command mise -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($miseCommand) {
    (& $miseCommand.Source activate pwsh) | Out-String | Invoke-Expression
}

# --- local machine specific content ----------------------------------------
# Mirrors: test -f ~/.local.zshrc && source ~/.local.zshrc
if ($script:DotfilesConfig.localProfile) {
    $localProfile = Resolve-DotfilesPath $script:DotfilesConfig.localProfile
    if (Test-Path -LiteralPath $localProfile) {
        . $localProfile
    }
}
