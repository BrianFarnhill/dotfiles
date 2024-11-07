DOTFILES_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
OS := $(shell bin/is-supported bin/is-macos macos linux)
HOMEBREW_PREFIX := $(shell bin/is-supported bin/is-macos $(shell bin/is-supported bin/is-arm64 /opt/homebrew /usr/local) /home/linuxbrew/.linuxbrew)
PATH := $(HOMEBREW_PREFIX)/bin:$(DOTFILES_DIR)/bin:$(N_PREFIX)/bin:$(PATH)
export ACCEPT_EULA=Y

all: $(OS)

macos: core-macos link

linux: core-linux link

core-macos: brew 

core-linux:
	sudo apt-get update
	sudo apt-get upgrade -y
	sudo apt-get dist-upgrade -f

stow-macos: brew
	is-executable stow || brew install stow

stow-linux: core-linux
	is-executable stow || sudo apt-get -y install stow

zsh: zsh-$(OS)
	sudo chsh -s $$(which zsh) $$(whoami)
	test -d $(HOME)/.oh-my-zsh || sh -c "$$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
	test -d $${ZSH_CUSTOM:-$(HOME)/.oh-my-zsh/custom}/themes/powerlevel10k || git clone --depth=1 https://github.com/romkatv/powerlevel10k.git $${ZSH_CUSTOM:-$(HOME)/.oh-my-zsh/custom}/themes/powerlevel10k
	test -d $${ZSH_CUSTOM:-$(HOME)/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting || git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $${ZSH_CUSTOM:-$(HOME)/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
	test -d $${ZSH_CUSTOM:-$(HOME)/.oh-my-zsh/custom}/plugins/zsh-autosuggestions || git clone https://github.com/zsh-users/zsh-autosuggestions $${ZSH_CUSTOM:-$(HOME)/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

zsh-macos:
	is-executable zsh || brew install zsh

zsh-linux:
	is-executable zsh || apt install zsh

brew:
	is-executable brew || curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh | bash

link: zsh stow-$(OS)
	for FILE in $$(\ls -A dotfiles); do if [ -f $(HOME)/$$FILE -a ! -h $(HOME)/$$FILE ]; then \
		mv -v $(HOME)/$$FILE $(HOME)/$$FILE.bak; fi; done
	stow -t "$(HOME)" dotfiles

unlink: stow-$(OS)
	stow --delete -t "$(HOME)" dotfiles
	for FILE in $$(\ls -A dotfiles); do if [ -f $(HOME)/$$FILE.bak ]; then \
		mv -v $(HOME)/$$FILE.bak $(HOME)/$$FILE; fi; done
