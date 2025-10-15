DOTFILES_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
OS := $(shell bin/is-supported bin/is-macos macos linux)
HOMEBREW_PREFIX := $(shell bin/is-supported bin/is-macos $(shell bin/is-supported bin/is-arm64 /opt/homebrew /usr/local) /home/linuxbrew/.linuxbrew)
PATH := $(HOMEBREW_PREFIX)/bin:$(DOTFILES_DIR)/bin:$(N_PREFIX)/bin:$(PATH)
ARCH := $(shell bin/is-supported bin/is-arm64 aarch64 x86_64)
export ACCEPT_EULA=Y
export XDG_CONFIG_HOME = $(HOME)/.config

all: $(OS)

macos: core-macos devtools packages vscode-extensions link aws-macos

linux: core-linux devtools vscode-extensions link aws-linux

core-macos: brew 
	brew install docker && brew link docker
	brew install colima && brew services restart colima && colima start

core-linux:
	sudo apt-get update
	sudo apt-get upgrade -y
	sudo apt-get dist-upgrade -f
	for NAME in $$(cat install/apt-packages); do sudo apt-get install $$NAME; done

packages: brew-packages

stow-macos: brew
	brew install stow

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

aws-linux:
	is-executable aws || curl "https://awscli.amazonaws.com/awscli-exe-linux-$(ARCH).zip" -o "awscliv2.zip" && unzip awscliv2.zip && sudo ./aws/install

aws-macos:
	is-executable aws || curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg" && sudo installer -pkg AWSCLIV2.pkg -target / && rm AWSCLIV2.pkg 

brew:
	is-executable brew || curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh | bash

brew-packages: brew
	brew bundle --file=$(DOTFILES_DIR)/install/Brewfile || true

vscode-extensions:
	-is-executable code && for EXT in $$(cat install/code-extensions); do code --install-extension $$EXT; done

link: zsh stow-$(OS)
	for FILE in $$(\ls -A dotfiles); do if [ -f $(HOME)/$$FILE -a ! -h $(HOME)/$$FILE ]; then \
		mv -v $(HOME)/$$FILE $(HOME)/$$FILE.bak; fi; done
	stow -t "$(HOME)" dotfiles
	mkdir -p "$(XDG_CONFIG_HOME)"
	stow -t "$(XDG_CONFIG_HOME)" config

unlink: stow-$(OS)
	stow --delete -t "$(HOME)" dotfiles
	for FILE in $$(\ls -A dotfiles); do if [ -f $(HOME)/$$FILE.bak ]; then \
		mv -v $(HOME)/$$FILE.bak $(HOME)/$$FILE; fi; done

devtools: mise

mise: 
	is-executable mise || curl https://mise.run | sh