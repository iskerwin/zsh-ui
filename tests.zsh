#!/bin/zsh
# Contract tests: ui.zsh and ui-fallback.zsh define the same names, and zsh-ui wins in either load order.
emulate -L zsh
setopt err_return pipe_fail
local here=${${(%):-%x}:A:h}
local -i passed=0
assert() {
    [[ $2 == $3 ]] || { print -ru2 -- "$1: expected ${(qqq)2}, got ${(qqq)3}"; exit 1; }
    (( ++passed ))
}
local -a contract_fns=( _ui_palette _ui_pad _ui_head _ui_sect _ui_kv _ui_cmd _ui_ok _ui_step _ui_hint
    _ui_warn _ui_err _ui_usage _ui_confirm _ui_bar _ui_size _ui_fzf_label _ui_fzf_tabs _ui_fzf_keys )
local -a contract_arrays=( _ui_fzf_look _ui_fzf_inline _ui_fzf_opts )
local -a palette_keys=( b blu cyn fg grn gry it mag r red ylw )

# Each file on its own defines the whole contract (functions, arrays, palette keys).
for f in ui.zsh ui-fallback.zsh; do
    assert "$f defines the contract" ok "$(zsh -f -c '
        source $1/$2; shift 2
        for n in ${@[1,18]}; do (( $+functions[$n] )) || { print missing $n; exit; }; done
        for n in ${@[19,21]}; do [[ ${(t)${(P)n}} == array* ]] || { print missing $n; exit; }; done
        _ui_palette; [[ ${(j: :)${(ko)_ui}} == "${@[22,-1]}" ]] || { print palette ${(ko)_ui}; exit; }
        print ok' _ $here $f $contract_fns $contract_arrays "${(j: :)palette_keys}")"
done

# ui.zsh defines nothing outside the contract (new names must be added to both files and here).
assert 'no names outside the contract' '' "$(zsh -f -c '
    local -a before=( ${(k)functions} ) contract=( ${@[2,-1]} ) added
    source $1/ui.zsh
    added=( ${(k)functions} ); added=( ${added:|before} ); print -r -- ${added:|contract}' _ $here $contract_fns)"

# zsh-ui wins whether it loads before or after the fallback.
local order
for order in 'ui.zsh ui-fallback.zsh' 'ui-fallback.zsh ui.zsh'; do
    assert "zsh-ui wins ($order)" $'\e[32m✓\e[0m x\n|--pointer=▌' "$(zsh -f -c '
        for f in ${=2}; do source $1/$f; done
        UI_COLOR=always _ui_ok x; print -rn -- "|${_ui_fzf_opts[(r)--pointer=*]}"' _ $here "$order")"
done

# The fallback is plain: no escape sequences.
assert 'fallback output is plain' '✓ done|  key       value| Files |[All]' "$(zsh -f -c '
    source $1/ui-fallback.zsh; UI_COLOR=always
    print -rn -- "$(_ui_ok done)|$(_ui_kv key value)|"; _ui_fzf_label grn Files; print -rn -- "$REPLY|"
    _ui_fzf_tabs grn T All All B; print -rn -- ${${(M)${=REPLY}:#\[*}}' _ $here)"

# The plugin entry exports its directory for helper processes.
assert 'ZSH_UI_DIR exported' "$here" "$(zsh -f -c 'source $1/zsh-ui.plugin.zsh; zsh -f -c "print -r -- \$ZSH_UI_DIR"' _ $here)"
print -r -- "$passed passed"
