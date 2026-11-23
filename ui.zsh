#!/bin/zsh
# zsh-ui — the shared look for zsh tools: output helpers (_ui_*) and the fzf look (_ui_fzf_*).
# Defines functions and arrays only, with no side effects, so tools and their helper processes
# can source it any number of times. The interface is listed in README.md ("Contract").
#
# Colors are the 16 ANSI colors, so the terminal theme decides the actual values.
# Output that is not a terminal (pipe, redirect), or NO_COLOR set, is not colored;
# UI_COLOR=always forces color (fzf lists and previews are not terminals but show color), UI_COLOR=never disables it.
# Fragments meant for the same line are returned in $REPLY instead of via $(...):
# a subshell's stdout is not a terminal, so it would lose its color.

typeset -g ZSH_UI_VERSION=1

# Color table $_ui for the output target (stdout by default, 2 for stderr)
_ui_palette() {
    typeset -gA _ui
    if [[ ${UI_COLOR-} != never && -z ${NO_COLOR-} ]] && [[ ${UI_COLOR-} == always || -t ${1:-1} ]]; then
        _ui=( r $'\e[0m' b $'\e[1m' it $'\e[3m' fg $'\e[39m' red $'\e[31m' grn $'\e[32m'
              ylw $'\e[33m' blu $'\e[34m' mag $'\e[35m' cyn $'\e[36m' gry $'\e[90m' )
    else
        _ui=( r '' b '' it '' fg '' red '' grn '' ylw '' blu '' mag '' cyn '' gry '' )
    fi
}

# Pad to a display width (CJK counts as 2 columns): _ui_pad <text> <width> → $REPLY
_ui_pad() {
    local e= n=$(( $2 - ${(m)#1} ))
    (( n < 1 )) && n=1
    REPLY="$1${(l:n:)e}"
}

# Title line: ▍title › sub ───────
_ui_head() {
    _ui_palette
    local t=$1 s=${2-} e=
    local w=$(( COLUMNS > 0 && COLUMNS < 60 ? COLUMNS : 60 ))
    local n=$(( w - ${(m)#t} - (${#s} ? ${(m)#s} + 3 : 0) - 2 ))
    (( n < 3 )) && n=3
    print -r -- "${_ui[blu]}${_ui[b]}▍${t}${_ui[r]}${s:+ ${_ui[gry]}›${_ui[r]} ${_ui[cyn]}${s}${_ui[r]}} ${_ui[gry]}${(l:n::─:)e}${_ui[r]}"
}

# Section title after a blank line: _ui_sect <name> [note]
_ui_sect() {
    _ui_palette
    print
    print -r -- "${_ui[mag]}[$1]${_ui[r]}${2:+ ${_ui[gry]}$2${_ui[r]}}"
}

# Key-value line: _ui_kv <key> <value> [color]; key width $_UI_KW (default 10), empty value shows -
_ui_kv() {
    _ui_palette
    _ui_pad "$1" ${_UI_KW:-10}
    print -r -- "  ${_ui[gry]}${REPLY}${_ui[r]}${3:+${_ui[$3]}}${2:--}${_ui[r]}"
}

# Help table row: _ui_cmd '<command args>' <description> [column width]
_ui_cmd() {
    _ui_palette
    local name=${1%% *}
    local args=${1#"$name"}
    _ui_pad "$1" ${3:-28}
    print -r -- "  ${_ui[grn]}${name}${_ui[r]}${_ui[cyn]}${args}${_ui[r]}${REPLY#"$1"}${_ui[gry]}$2${_ui[r]}"
}

# Status lines: ✓ done · › step · dim hint · ! warning · ✗ error (warnings and errors go to stderr)
_ui_ok()   { _ui_palette;   print -r -- "${_ui[grn]}✓${_ui[r]} $*"; }
_ui_step() { _ui_palette;   print -r -- "${_ui[blu]}›${_ui[r]} $*"; }
_ui_hint() { _ui_palette;   print -r -- "  ${_ui[gry]}$*${_ui[r]}"; }
_ui_warn() { _ui_palette 2; print -ru2 -- "${_ui[ylw]}!${_ui[r]} $*"; }
_ui_err()  { _ui_palette 2; print -ru2 -- "${_ui[red]}✗${_ui[r]} $*"; }

# Usage line on stderr: _ui_usage <command> [argument description...]
_ui_usage() {
    _ui_palette 2
    print -ru2 -- "${_ui[gry]}usage:${_ui[r]} ${_ui[b]}$1${_ui[r]}${2:+ ${_ui[cyn]}${(j: :)@[2,-1]}${_ui[r]}}"
}

# Confirmation, returns 0 on y/Y: _ui_confirm <question>
_ui_confirm() {
    _ui_palette 2
    local ans
    read -r "ans?${_ui[ylw]}?${_ui[r]} $1 ${_ui[gry]}[y/N]${_ui[r]} " || return 1
    [[ $ans == [yY] ]]
}

# Usage bar: _ui_bar <percent> [width] → $REPLY; yellow from 70%, red from 90%
_ui_bar() {
    _ui_palette
    local -i p=$1 w=${2:-20} n
    local c=grn e=
    n=$(( p * w / 100 ))
    (( n > w )) && n=$w
    (( p >= 70 )) && c=ylw
    (( p >= 90 )) && c=red
    REPLY="${_ui[$c]}${(l:n::█:)e}${_ui[gry]}${(l:w-n::░:)e}${_ui[r]} ${_ui[$c]}${(l:3:)p}%${_ui[r]}"
}

# Human-readable size (base 1024): _ui_size <bytes> → $REPLY
_ui_size() {
    local -F v=$1
    local -a u=( B K M G T )
    local i=1
    while (( v >= 1024 && i < $#u )); do
        (( v /= 1024, i++ ))
    done
    if (( i == 1 )); then
        printf -v REPLY '%dB' $v
    else
        printf -v REPLY '%.1f%s' $v $u[i]
    fi
}

# _ui_fzf_since <x.y[.z]>: the installed fzf is at least that version (false without fzf).
# For options newer than a tool's minimum fzf: _ui_fzf_since 0.61 && args+=( --ghost=... )
# The version is read once per shell and kept in _ui_fzf_v (0.66.1 -> 66001); _ui_fzf_ver puts it in $REPLY.
_ui_fzf_ver() {
    if [[ -z ${_ui_fzf_v-} ]]; then
        local v=$(FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= command fzf --version 2>/dev/null)
        local -a p=( ${(s:.:)${v%% *}} )
        typeset -gi _ui_fzf_v=$(( ${p[1]%%[^0-9]*}0 / 10 * 1000000 + ${p[2]%%[^0-9]*}0 / 10 * 1000 + ${p[3]%%[^0-9]*}0 / 10 ))
    fi
    REPLY=$_ui_fzf_v
}
_ui_fzf_since() {
    local -a p=( ${(s:.:)1} )
    _ui_fzf_ver
    (( REPLY && REPLY >= ${p[1]:-0} * 1000000 + ${p[2]:-0} * 1000 + ${p[3]:-0} ))
}

# fzf look (TUI style): input, list and preview each get a rounded box, bordered green, blue and cyan.
# The title goes on the input box's top border (--input-label, _ui_fzf_label / _ui_fzf_tabs), key hints
# on the list's bottom border (--list-label, _ui_fzf_keys) and the preview's keys on the right of its bottom
# border (--preview-label); the match count sits at the right of the input line. --header is for column titles.
# change:first moves the cursor back to the first match whenever the query changes.
typeset -ga _ui_fzf_look=(
    --cycle --height=80% --reverse
    --border=none --margin=0 --padding=0 --no-separator
    --input-border=rounded --list-border=rounded --preview-border=rounded
    --input-label-pos=3 --list-label-pos=3:bottom --preview-label-pos=-3:bottom
    --highlight-line --pointer='▌' --marker='✓' --prompt='❯ ' --info=inline-right
    --color='input-border:green,list-border:blue,preview-border:cyan,label:-1,info:bright-black'
    --color='hl:blue,hl+:blue,prompt:green,pointer:magenta,marker:magenta,spinner:yellow,header:bright-black'
    --color='bg+:#44475a,gutter:-1'
    --bind='ctrl-/:toggle-preview,change:first'
)
# The same pointer and colors without boxes, for menus that pop up at the cursor (e.g. fzf-tab)
typeset -ga _ui_fzf_inline=(
    --highlight-line --pointer='▌' --marker='✓' --prompt='❯ ' --info=inline-right --no-separator
    --color='hl:blue,hl+:blue,prompt:green,info:bright-black,pointer:magenta,marker:magenta,spinner:yellow,header:bright-black'
    --color='bg+:#44475a,gutter:-1'
)
# A blank gutter (no ▌ column on the left) needs fzf 0.66
_ui_fzf_since 0.66 && _ui_fzf_look+=( --gutter=' ' ) _ui_fzf_inline+=( --gutter=' ' )
# For pickers: fzf "${_ui_fzf_opts[@]}" <the picker's own options>; later options override these.
# Clears the file preview and labels from FZF_DEFAULT_OPTS. --preview-window merges with earlier values,
# so `default` first drops their wrap and alternative layouts; pickers that wrap say so in their own --preview-window.
typeset -ga _ui_fzf_opts=(
    "${_ui_fzf_look[@]}"
    --ansi --header= --no-preview --preview-window=default,nowrap
    --input-label= --list-label= --preview-label=
)

# Border title ┐text┌: brackets in the border color, bold text. fzf labels are not terminals, so always colored
# _ui_fzf_label <border color> <title> → $REPLY (border colors: input grn, list blu, preview cyn)
_ui_fzf_label() {
    local UI_COLOR=always
    _ui_palette
    REPLY="${_ui[$1]}┐${_ui[r]}${_ui[b]}$2${_ui[r]}${_ui[$1]}┌${_ui[r]}"
}

# View tabs after the title, current view highlighted, others dim
# _ui_fzf_tabs <border color> <title> <current view> <views...> → $REPLY
_ui_fzf_tabs() {
    local UI_COLOR=always c=$1 cur=$3 v out
    _ui_fzf_label $c "$2"
    out=$REPLY
    _ui_palette
    for v in "${@[4,-1]}"; do
        if [[ $v == $cur ]]; then
            out+="${_ui[$c]}┐${_ui[r]}${_ui[b]}${_ui[$c]}$v${_ui[r]}${_ui[$c]}┌${_ui[r]}"
        else
            out+="${_ui[$c]}┐${_ui[r]}${_ui[gry]}$v${_ui[r]}${_ui[$c]}┌${_ui[r]}"
        fi
    done
    REPLY=$out
}

# Key hints ┐key label┌┐key label┌: _ui_fzf_keys <border color> <key> <label> [<key> <label>...] → $REPLY
_ui_fzf_keys() {
    local UI_COLOR=always c=$1 out=
    _ui_palette
    shift
    while (( $# >= 2 )); do
        out+="${_ui[$c]}┐${_ui[r]}${_ui[b]}${_ui[mag]}$1${_ui[r]} $2${_ui[$c]}┌${_ui[r]}"
        shift 2
    done
    REPLY=$out
}
