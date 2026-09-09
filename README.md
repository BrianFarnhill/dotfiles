# Brian's dot files

This is a collection of scripts and config that I use to configure my environments. 
I've specifically targeted MacOS and Linux distro's that use `apt` as their package manager, and
there's a separate native Windows track too. Take anything here that is useful to you, but do so
at your own risk (don't be that person that just takes code and scripts from the internet without
understanding them is all I'm saying).

## What's in the box?

* My [ZSH](https://www.zsh.org/) and [OhMyZsh](https://github.com/ohmyzsh/ohmyzsh) config, based on the [PowerLevel10k](https://github.com/romkatv/powerlevel10k) theme
  and also includes my preferred extensions
* Install [MISE](https://github.com/jdx/mise) to help with installation of dev tools and other useful bits
* Includes a bunch of apps I like which I would install on a MacOS build (check `install/Brewfile` for those)
* Adds extensions I like to VSCode, again have a look in `install/code-extensions` for the list
* Does basic package updates and upgrades in linux distros
* A parallel native Windows setup in `windows/`, driven by PowerShell 7 and `winget` instead of
  `make` and Homebrew, with an [oh-my-posh](https://ohmyposh.dev/) prompt in place of PowerLevel10k

## Installation

### macOS and Linux

On a fresh install of MacOS you'll need the dev tools to get `git` and `make`, so start there in a
terminal window.

```bash
sudo softwareupdate -i -a
xcode-select --install
```

If you're on linux just make sure you have the appropriate dev tools installed. For example, on debian
this looks like this:

```bash
sudo apt install build-essential
```

Once the tools are in place, clone this repo and run the make command:

```bash
git clone https://github.com/BrianFarnhill/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
make
```

### Windows (native)

Native Windows has its own entrypoint - there is no `make` here. `windows/bootstrap.ps1` is the
Windows equivalent, and it shares the cross-platform pieces of this repo (the VS Code extension
list in `install/code-extensions`, and mise) while installing everything else the Windows way.

Prerequisites:

* **PowerShell 7** (`winget install Microsoft.PowerShell`) - Windows PowerShell 5.1 is not enough
* **winget**, which ships as *App Installer* from the Microsoft Store on current Windows builds
* Optionally **Developer Mode** (Settings > System > For developers), or an elevated shell, so the
  PowerShell profile can be symlinked. Without it the profile is copied instead and the script
  tells you so - re-run the script after changing the profile to refresh the copy.

```powershell
git clone https://github.com/BrianFarnhill/dotfiles.git $HOME\.dotfiles
cd $HOME\.dotfiles
pwsh -File windows/bootstrap.ps1
```

The script installs the apps listed in `windows/winget.json`, installs the shared VS Code
extensions, installs mise and the tools in `config/mise/config.toml`, puts mise's shims
directory on your PATH so those tools work outside PowerShell too, links `config/` into
`$XDG_CONFIG_HOME` the way `stow` does on the other platforms, links
`windows/Microsoft.PowerShell_profile.ps1` to `$PROFILE.CurrentUserAllHosts`, and points git at
the 1Password SSH agent. It is idempotent, so
re-running it is a no-op: only missing packages are imported, and upgrading stays a deliberate
`winget upgrade` rather than something bootstrapping does behind your back. Individual steps can
be skipped with `-SkipApps`, `-SkipMise`, `-SkipExtensions`, `-SkipProfile` and `-SkipGit`.


Paths, the app list and the oh-my-posh theme all live in files rather than in the script:
`windows/config.json`, `windows/winget.json` and `windows/oh-my-posh.json`. Machine specific
additions go in `~/.local.profile.ps1`, which the profile sources if it exists - the same idea as
`~/.local.zshrc` on the other platforms.

You still need to turn on the SSH agent inside 1Password (Settings > Developer > Use the SSH
agent); the script reports whether it is listening.

**Using WSL?** Then this section is not for you - run the linux track (`make`) inside your WSL
distro and leave the Windows side alone.

## Post-Install

After installation is done, have a think about running the below additional config items:

### Git config

Configure your local git identity

```bash
git config --global user.name "your name"
git config --global user.email "your@email.com"
git config --global github.user "your-github-username"
```

### Install dev tools with MISE

If you need node or python, install them with MISE. Check out the [MISE doco](https://mise.jdx.dev/) for
the full details, but here are a couple of my common examples

```bash
mise use --global node@lts

# This will install multiple versions along side each other and set up version specific commands
mise use --global python@3.12 python@3.11 python@3.10
```

## Credits

Definitely go and check out [Lars Kappert's dotfiles repo](https://github.com/webpro/dotfiles) which is
where I got the makefile approach and a bunch of the cool helpers here from, as well as the
[DotFiles Community](https://dotfiles.github.io/) too for more resources.
