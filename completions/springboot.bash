#!/usr/bin/env bash

# Bash 补全入口函数。
# 使用 COMP_WORDS / COMP_CWORD 获取当前光标位置并返回候选。
_springboot_cached_deps() {
    local script_dir cache_file files
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    files=("$script_dir"/deps-cache/boot-*.md)
    [ ! -e "${files[0]}" ] && return 0
    cache_file="${files[0]}"
    [ -z "$cache_file" ] && return 0
    awk -F'|' '
        /^\|/ {
            id=$3
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
            if (id != "" && id != "ID" && id != "---") {
                print id
            }
        }
    ' "$cache_file"
}

_springboot_completion() {
    local cur prev cmd subcmd
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    cmd="${COMP_WORDS[1]}"
    subcmd="${COMP_WORDS[2]}"

    local root_opts="--help --version create module deps boot"
    local create_opts="--help --dry-run --name= --boot= --type= --packaging= --modules= --config= --java= --language= --gradle-dsl= --group= --artifact= --artifact-version= --desc= --pkg= --deps="
    local module_opts="--help add list remove"
    local module_add_opts="--help --dry-run --name= --module= --module-packaging= --module-path= --boot= --type= --packaging= --config= --java= --language= --gradle-dsl= --group= --artifact= --artifact-version= --desc= --pkg= --deps="
    local module_list_opts="--help --name= --type= --module-path="
    local module_remove_opts="--help --dry-run --name= --type= --module= --module-path="
    local deps_opts="--help list preview search"
    local deps_list_opts="--help --boot= --output= --refresh"
    local deps_preview_opts="--help --deps= --boot= --type= --java= --language= --gradle-dsl="
    local deps_search_opts="--help --query= --boot= --refresh"
    local boot_opts="--help list"
    local boot_list_opts="--help --refresh"

    if [[ $COMP_CWORD -le 1 ]]; then
        COMPREPLY=( $(compgen -W "$root_opts" -- "$cur") )
        return 0
    fi

    case "$cur" in
        --deps=*)
            local deps_list
            deps_list="$(_springboot_cached_deps)"
            if [[ -n "$deps_list" ]]; then
                COMPREPLY=( $(compgen -W "$deps_list" -- "${cur#--deps=}") )
                COMPREPLY=( "${COMPREPLY[@]/#/--deps=}" )
            fi
            return 0
            ;;
        --output=*)
            COMPREPLY=( $(compgen -W "terminal web" -- "${cur#--output=}") )
            COMPREPLY=( "${COMPREPLY[@]/#/--output=}" )
            return 0
            ;;
        --module-packaging=*)
            COMPREPLY=( $(compgen -W "jar pom" -- "${cur#--module-packaging=}") )
            COMPREPLY=( "${COMPREPLY[@]/#/--module-packaging=}" )
            return 0
            ;;
        --type=*)
            COMPREPLY=( $(compgen -W "maven gradle" -- "${cur#--type=}") )
            COMPREPLY=( "${COMPREPLY[@]/#/--type=}" )
            return 0
            ;;
        --language=*)
            COMPREPLY=( $(compgen -W "java kotlin groovy" -- "${cur#--language=}") )
            COMPREPLY=( "${COMPREPLY[@]/#/--language=}" )
            return 0
            ;;
        --gradle-dsl=*)
            COMPREPLY=( $(compgen -W "groovy kotlin" -- "${cur#--gradle-dsl=}") )
            COMPREPLY=( "${COMPREPLY[@]/#/--gradle-dsl=}" )
            return 0
            ;;
        --packaging=*)
            COMPREPLY=( $(compgen -W "jar war pom" -- "${cur#--packaging=}") )
            COMPREPLY=( "${COMPREPLY[@]/#/--packaging=}" )
            return 0
            ;;
        --config=*)
            COMPREPLY=( $(compgen -W "properties yaml" -- "${cur#--config=}") )
            COMPREPLY=( "${COMPREPLY[@]/#/--config=}" )
            return 0
            ;;
        --java=*)
            COMPREPLY=( $(compgen -W "17 21 25" -- "${cur#--java=}") )
            COMPREPLY=( "${COMPREPLY[@]/#/--java=}" )
            return 0
            ;;
    esac

    case "$cmd" in
        create)
            COMPREPLY=( $(compgen -W "$create_opts" -- "$cur") )
            ;;
        module)
            if [[ $COMP_CWORD -le 2 ]]; then
                COMPREPLY=( $(compgen -W "$module_opts" -- "$cur") )
            elif [[ "$subcmd" == "add" ]]; then
                COMPREPLY=( $(compgen -W "$module_add_opts" -- "$cur") )
            elif [[ "$subcmd" == "list" ]]; then
                COMPREPLY=( $(compgen -W "$module_list_opts" -- "$cur") )
            elif [[ "$subcmd" == "remove" ]]; then
                COMPREPLY=( $(compgen -W "$module_remove_opts" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "$module_opts" -- "$cur") )
            fi
            ;;
        deps)
            if [[ $COMP_CWORD -le 2 ]]; then
                COMPREPLY=( $(compgen -W "$deps_opts" -- "$cur") )
            elif [[ "$subcmd" == "list" ]]; then
                COMPREPLY=( $(compgen -W "$deps_list_opts" -- "$cur") )
            elif [[ "$subcmd" == "preview" ]]; then
                COMPREPLY=( $(compgen -W "$deps_preview_opts" -- "$cur") )
            elif [[ "$subcmd" == "search" ]]; then
                COMPREPLY=( $(compgen -W "$deps_search_opts" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "$deps_opts" -- "$cur") )
            fi
            ;;
        boot)
            if [[ $COMP_CWORD -le 2 ]]; then
                COMPREPLY=( $(compgen -W "$boot_opts" -- "$cur") )
            elif [[ "$subcmd" == "list" ]]; then
                COMPREPLY=( $(compgen -W "$boot_list_opts" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "$boot_opts" -- "$cur") )
            fi
            ;;
        *)
            COMPREPLY=( $(compgen -W "$root_opts" -- "$cur") )
            ;;
    esac
}

# 注册到 springboot 命令。
complete -F _springboot_completion springboot
