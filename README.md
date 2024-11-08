# Brian's dot files

This is a collection of scripts and config that I use to configure my environments. 
I've specifically targeted MacOS and Linux distro's that use `apt` as their package manager. Take
anything here that is useful to you, but do so at your own risk (don't be that person that
just takes code and scripts from the internet without understanding them is all I'm saying).

## What's in the box?

* My [ZSH](https://www.zsh.org/) and [OhMyZsh](https://github.com/ohmyzsh/ohmyzsh) config, based on the [PowerLevel10k](https://github.com/romkatv/powerlevel10k) theme
  and also includes my preferred extensions
* Install [MISE](https://github.com/jdx/mise) to help with installation of dev tools and other useful bits
* Includes a bunch of apps I like which I would install on a MacOS build (check `install/Caskfile` for those)
* Adds extensions I like to VSCode, again have a look in `install/code-extensions` for the list
* Does basic package updates and upgrades in linux distros

## Installation

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
