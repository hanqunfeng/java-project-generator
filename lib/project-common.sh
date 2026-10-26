#!/usr/bin/env bash
# ========= 项目级文件公共逻辑 =========

if ! declare -F t >/dev/null 2>&1; then
    # shellcheck source=lib/i18n.sh
    source "${SCRIPT_DIR}/lib/i18n.sh"
fi

# -----------------------------------------------------------------------------
# 函数: write_project_gitignore
# 作用: 在指定项目目录写入默认 .gitignore（覆盖写入）。
# 入参:
#   $1 -> 项目目录绝对/相对路径
# 返回:
#   0 -> 写入成功
#   1 -> 目标目录为空
# -----------------------------------------------------------------------------
write_project_gitignore() {
    local projectDir="$1"
    if [ -z "$projectDir" ]; then
        say "write_project_gitignore requires a projectDir argument" "write_project_gitignore 需要 projectDir 参数"
        return 1
    fi

    cat > "${projectDir}/.gitignore" <<'EOF'
# Build
target/
build/
out/

# Maven/Gradle caches
.mvn/
.gradle/

# IDE
.idea/
*.iml
.vscode/

# OS
.DS_Store
Thumbs.db
EOF
}
