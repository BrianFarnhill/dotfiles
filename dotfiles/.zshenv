# Sourced by every zsh, interactive or not.
#
# That is the point: `mise activate` in .zshrc only reaches interactive shells,
# so tools installed by mise are invisible to scripts, editor tasks and anything
# else that spawns a non-interactive shell. Putting the shims directory on PATH
# here covers those. Interactive shells still run `mise activate`, which puts the
# real binaries ahead of these shims.
#
# This is mise's documented default data directory. Asking `mise doctor` for it
# would mean spawning a process on every single zsh start, which is too high a
# price to pay in a file sourced this often.
_mise_shims="${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims"
if [ -d "$_mise_shims" ]; then
  case ":$PATH:" in
    *":$_mise_shims:"*) ;;
    *) export PATH="$PATH:$_mise_shims" ;;
  esac
fi
unset _mise_shims
