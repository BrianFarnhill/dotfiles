# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="$HOME/.oh-my-zsh"
ZSH_DISABLE_COMPFIX="true"
ZSH_THEME="powerlevel10k/powerlevel10k"

# Which plugins would you like to load?
plugins=(
    git
    aws
    git-extras
    jfrog
    pip
    python
    zsh-syntax-highlighting
    encode64
    jsontools
    node
    npm
    urltools
    zsh-autosuggestions
)
source $ZSH/oh-my-zsh.sh

export EDITOR="code --wait"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

export XDG_CONFIG_HOME="$HOME/.config"

# MISE - https://github.com/jdx/mise/tree/main
test -f ~/.local/bin/mise && eval "$(~/.local/bin/mise activate zsh)"

# Local machine specific content can be added to .local.zshrc
test -f ~/.local.zshrc && source ~/.local.zshrc

[[ -S "${HOME}/.1password/agent.sock" ]] && export SSH_AUTH_SOCK="${HOME}/.1password/agent.sock"
