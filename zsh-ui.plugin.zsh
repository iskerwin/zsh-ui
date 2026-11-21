# zsh-ui: the shared look for zsh tools. Tools that support it use these definitions when they are
# loaded, whatever the load order; without zsh-ui they fall back to their own plain look.
# ZSH_UI_DIR lets a tool's helper processes (which cannot see shell functions) source ui.zsh.
export ZSH_UI_DIR=${${(%):-%x}:A:h}
source $ZSH_UI_DIR/ui.zsh
