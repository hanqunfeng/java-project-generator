#!/usr/bin/env bash
# ========= 嵌套模块公共逻辑 =========
# 依赖入口脚本中已解析的变量：
#   projectName, modulePath

source "${SCRIPT_DIR}/lib/arg-common.sh"

# 统一退出码（来源入口脚本，缺失时使用默认值）。
exit_param="${EXIT_PARAM:-1}"
exit_fs="${EXIT_FS:-3}"

# -----------------------------------------------------------------------------
# 函数: exit_with_message_common
# 作用: 统一错误输出并按约定退出。
# 入参:
#   $1 -> 错误消息
#   $2 -> 退出码
# -----------------------------------------------------------------------------
exit_with_message_common() {
    local message="$1"
    local exitCode="$2"
    echo "$message"
    exit "$exitCode"
}

# -----------------------------------------------------------------------------
# 函数: resolve_parent_dir_common
# 作用: 解析“当前要挂载子模块”的父模块目录。
# 规则:
#   - 未传 modulePath -> 项目根目录
#   - 传 modulePath   -> <projectName>/<modulePath>
# 输出:
#   全局变量 targetParentDir
# -----------------------------------------------------------------------------
resolve_parent_dir_common() {
    targetParentDir="${projectName}"
    if [ -n "${modulePath:-}" ]; then
        targetParentDir="${projectName}/${modulePath}"
    fi
}

# -----------------------------------------------------------------------------
# 函数: build_module_dir_common
# 作用: 基于 targetParentDir 拼接目标子模块目录。
# 入参:
#   $1 -> 子模块名
# 返回:
#   stdout -> <targetParentDir>/<moduleName>
# -----------------------------------------------------------------------------
build_module_dir_common() {
    local mod="$1"
    printf '%s/%s\n' "${targetParentDir}" "${mod}"
}

# -----------------------------------------------------------------------------
# 函数: ensure_dir_exists_common
# 作用: 校验目录存在，不存在则输出错误并退出。
# 入参:
#   $1 -> 目录路径
#   $2 -> 错误前缀文案
# -----------------------------------------------------------------------------
ensure_dir_exists_common() {
    local dirPath="$1"
    local errPrefix="$2"
    if [ ! -d "$dirPath" ]; then
        exit_with_message_common "${errPrefix}: ${dirPath}" "$exit_fs"
    fi
}

# -----------------------------------------------------------------------------
# 函数: ensure_file_exists_common
# 作用: 校验文件存在，不存在则输出错误并退出。
# 入参:
#   $1 -> 文件路径
#   $2 -> 错误前缀文案
# -----------------------------------------------------------------------------
ensure_file_exists_common() {
    local filePath="$1"
    local errPrefix="$2"
    if [ ! -f "$filePath" ]; then
        exit_with_message_common "${errPrefix}: ${filePath}" "$exit_fs"
    fi
}

# -----------------------------------------------------------------------------
# 函数: ensure_module_dir_absent_common
# 作用: 校验目标子模块目录不存在，避免重复创建。
# 入参:
#   $1 -> 目标子模块目录
# -----------------------------------------------------------------------------
ensure_module_dir_absent_common() {
    local moduleDir="$1"
    if [ -d "$moduleDir" ]; then
        exit_with_message_common "子模块目录已存在: ${moduleDir}" "$exit_param"
    fi
}

# -----------------------------------------------------------------------------
# 函数: build_gradle_include_path_common
# 作用: 构建 Gradle include 路径。
# 示例:
#   parentPath=platform/common, mod=api -> :platform:common:api
# 入参:
#   $1 -> parentPath
#   $2 -> moduleName
# 返回:
#   stdout -> Gradle include path
# -----------------------------------------------------------------------------
build_gradle_include_path_common() {
    local parentPath="$1"
    local mod="$2"
    local includePath=""

    if [ -n "$parentPath" ]; then
        includePath="${parentPath}/${mod}"
    else
        includePath="${mod}"
    fi
    includePath="${includePath//\//:}"
    printf ':%s\n' "$includePath"
}

