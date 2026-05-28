#!/usr/bin/env bash
# ========= 参数处理公共逻辑 =========

# -----------------------------------------------------------------------------
# 函数: normalize_csv_unique_common
# 作用: 规范化 CSV，去空白、去重，并保持首出现顺序。
# 入参:
#   $1 -> 原始 CSV
# 返回:
#   stdout -> 规范化后的 CSV
# -----------------------------------------------------------------------------
normalize_csv_unique_common() {
    local raw="$1"
    local token
    local normalized=""
    local seen=","
    while IFS= read -r token; do
        token=$(printf '%s' "$token" | tr -d '[:space:]')
        [ -z "$token" ] && continue
        if [[ "$seen" != *",$token,"* ]]; then
            if [ -n "$normalized" ]; then
                normalized+=","
            fi
            normalized+="$token"
            seen+="${token},"
        fi
    done < <(printf '%s\n' "$raw" | tr ',' '\n')
    printf '%s\n' "$normalized"
}

# -----------------------------------------------------------------------------
# 函数: iterate_csv_items_common
# 作用: 迭代逗号分隔字符串并逐行输出规范化条目。
# 入参:
#   $1 -> CSV 字符串
# 返回:
#   stdout -> 每行一个去空白后的非空条目
# -----------------------------------------------------------------------------
iterate_csv_items_common() {
    local raw="$1"
    local item
    while IFS= read -r item; do
        item=$(printf '%s' "$item" | tr -d '[:space:]')
        [ -z "$item" ] && continue
        printf '%s\n' "$item"
    done < <(printf '%s\n' "$raw" | tr ',' '\n')
}
