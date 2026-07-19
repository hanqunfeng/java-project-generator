#!/usr/bin/env bash
# =============================================================================
# release-formula.sh — 自动发布 java-project-generator 的新版本到 Homebrew Tap
#
# 完整流程（对应 formula/README.md 中的手工步骤）：
#   1. 根据当前最新版本 + bump 类型（patch / minor / major）计算新版本号
#   2. 运行 scripts/check.sh 做发布前检查（可用 --skip-check 跳过）
#   3. 更新 springboot 中的 SCRIPT_VERSION
#   4. 提交并推送主仓库，创建并推送 git tag（如 v1.0.6）
#   5. 从 GitHub 下载该 tag 的源码包，计算 sha256
#   6. 调用 scripts/sync-version.sh 同步 formula 的 url / sha256
#   7. 提交并推送主仓库中的 formula 变更
#   8. 将 formula 复制到本地 tap 仓库并提交推送
#   9. （可选）执行 brew style / brew audit
#
# 用法:
#   bash scripts/release-formula.sh <patch|minor|major> [选项]
#   bash scripts/release-formula.sh --version 1.2.0 [选项]
#   bash scripts/release-formula.sh --resume 1.0.6 [选项]   # tag 已推送后续跑
#
# 示例:
#   # 当前最新 tag 为 v1.0.5 时：
#   bash scripts/release-formula.sh patch    # → v1.0.6
#   bash scripts/release-formula.sh minor    # → v1.1.0
#   bash scripts/release-formula.sh major    # → v2.0.0
#   bash scripts/release-formula.sh --version 1.2.0
#
#   # tag 已推送但 formula/tap 未完成时：
#   bash scripts/release-formula.sh --resume 1.0.6
#
#   # 仅预览将要执行的操作，不真正改动
#   bash scripts/release-formula.sh patch --dry-run
#
#   # 跳过 bats/shellcheck，并跳过交互确认
#   bash scripts/release-formula.sh patch --skip-check --yes
#
# 前置条件:
#   - 主仓库工作区干净（无未提交变更；--resume 时允许已改 formula）
#   - 已配置 origin 远程，且有 push 权限
#   - 本地已存在 tap：cd "$(brew --repo hanqunfeng/homebrew-tap)"
#   - 已安装：git、curl、shasum/sha256sum、brew、ruby
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# 路径与常量
# ---------------------------------------------------------------------------

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# GitHub 源码仓库（用于生成 archive URL）
GITHUB_OWNER="hanqunfeng"
GITHUB_REPO="java-project-generator"

# Homebrew Tap 名称（brew tap-new 后本地路径由 brew --repo 解析）
# 注意：tap 简写为 hanqunfeng/tap，完整仓库名为 hanqunfeng/homebrew-tap
TAP_NAME="hanqunfeng/homebrew-tap"
FORMULA_NAME="java-project-generator"
FORMULA_FILE="formula/java-project-generator.rb"

# ---------------------------------------------------------------------------
# 默认选项
# ---------------------------------------------------------------------------

BUMP_TYPE=""          # patch | minor | major（与 --version 二选一）
EXPLICIT_VERSION=""   # 通过 --version 直接指定，不带 v 前缀
RESUME_MODE=0         # 1 = 续跑：跳过 bump/tag，从计算 sha256 起继续
DRY_RUN=0             # 1 = 只打印计划，不执行写操作
SKIP_CHECK=0          # 1 = 跳过 scripts/check.sh
SKIP_TAP_AUDIT=0      # 1 = 跳过 brew style / brew audit
ASSUME_YES=0          # 1 = 跳过交互确认
PUSH_REMOTE=1         # 1 = 推送主仓库与 tap；0 = 只做本地提交与打 tag

# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------

# 日志一律走 stderr，避免被 $(...) 命令替换捕获（污染返回值）
log()  { printf '==> %s\n' "$*" >&2; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
    # 只打印文件头注释块（到分隔线为止），去掉行首 "# "
    awk '
        NR == 1 { next }
        /^# =+$/ && seen_title { exit }
        /^# =+$/ { seen_title = 1; next }
        /^#/ {
            sub(/^# ?/, "")
            print
            next
        }
        { exit }
    ' "$0"
    exit "${1:-0}"
}

# 确认操作；--yes 时直接通过
confirm() {
    local prompt="$1"
    if [[ "$ASSUME_YES" -eq 1 ]]; then
        return 0
    fi
    local reply
    printf '%s [y/N] ' "$prompt"
    read -r reply
    [[ "$reply" == "y" || "$reply" == "Y" ]]
}

# dry-run 包装：真正执行前打印命令；dry-run 模式下只打印
run() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '[dry-run] %s\n' "$*"
        return 0
    fi
    "$@"
}

# 从字符串中提取 semver（支持 v1.2.3 / 1.2.3）
normalize_version() {
    local raw="$1"
    raw="${raw#v}"
    if [[ ! "$raw" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        die "非法版本号: $1（期望格式: X.Y.Z 或 vX.Y.Z）"
    fi
    printf '%s\n' "$raw"
}

# 读取当前最新版本：优先用最新 git tag，其次用 springboot 中的 SCRIPT_VERSION
detect_current_version() {
    local tag version
    tag="$(git tag -l 'v*' --sort=-v:refname | head -n 1 || true)"
    if [[ -n "$tag" ]]; then
        normalize_version "$tag"
        return 0
    fi

    version="$(
        awk -F'"' '/^SCRIPT_VERSION="/ { print $2; exit }' springboot
    )"
    if [[ -z "$version" ]]; then
        die "无法从 git tag 或 springboot SCRIPT_VERSION 检测到当前版本"
    fi
    warn "未找到 git tag，改用 SCRIPT_VERSION=${version}"
    normalize_version "$version"
}

# 按 bump 类型计算下一个版本号
#   patch: 1.0.5 → 1.0.6
#   minor: 1.0.5 → 1.1.0
#   major: 1.0.5 → 2.0.0
bump_version() {
    local current="$1"
    local bump="$2"
    local major minor patch

    IFS='.' read -r major minor patch <<< "$current"

    case "$bump" in
        patch)
            patch=$((patch + 1))
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        *)
            die "未知 bump 类型: $bump（支持: patch | minor | major）"
            ;;
    esac

    printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

# 仅更新 springboot 中的 SCRIPT_VERSION（打 tag 前需要；sha256 此时尚不可知）
update_script_version() {
    local version="$1"
    local tmp_file

    tmp_file="$(mktemp)"
    awk -v ver="$version" '
    {
        if ($0 ~ /^SCRIPT_VERSION="/) {
            print "SCRIPT_VERSION=\"" ver "\""
        } else {
            print $0
        }
    }
    ' springboot > "$tmp_file"
    mv "$tmp_file" springboot
}

# 下载 GitHub tag 源码包并计算 sha256
# GitHub 在 tag push 后偶发短暂延迟，因此带有限次重试
compute_archive_sha256() {
    local tag="$1"
    local url="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/archive/refs/tags/${tag}.tar.gz"
    local tmp_archive
    local attempt max_attempts=8
    local sleep_secs=3

    tmp_archive="$(mktemp -t "${FORMULA_NAME}-${tag}.XXXXXX.tar.gz")"

    for ((attempt = 1; attempt <= max_attempts; attempt++)); do
        log "下载源码包 (${attempt}/${max_attempts}): ${url}"
        if curl -fsSL --retry 3 --retry-delay 2 -o "$tmp_archive" "$url"; then
            # 空文件或过小通常表示 tag 尚未在 GitHub 上可用
            if [[ -s "$tmp_archive" ]] && [[ "$(wc -c < "$tmp_archive")" -gt 1000 ]]; then
                break
            fi
        fi
        if [[ "$attempt" -eq "$max_attempts" ]]; then
            rm -f "$tmp_archive"
            die "多次重试后仍无法下载 ${url}，请确认 tag 已推送到 GitHub"
        fi
        warn "下载失败或文件过小，${sleep_secs}s 后重试..."
        sleep "$sleep_secs"
        sleep_secs=$((sleep_secs + 2))
    done

    local hash
    if command -v shasum >/dev/null 2>&1; then
        hash="$(shasum -a 256 "$tmp_archive" | awk '{ print $1 }')"
    elif command -v sha256sum >/dev/null 2>&1; then
        hash="$(sha256sum "$tmp_archive" | awk '{ print $1 }')"
    else
        rm -f "$tmp_archive"
        die "需要 shasum 或 sha256sum 来计算 sha256"
    fi

    rm -f "$tmp_archive"

    # 仅向 stdout 输出纯 hash，供 $(...) 捕获；其它日志已走 stderr
    if [[ ! "$hash" =~ ^[0-9a-f]{64}$ ]]; then
        die "计算出的 sha256 非法: ${hash}"
    fi
    printf '%s\n' "$hash"
}

# 解析本地 tap 仓库路径
resolve_tap_repo() {
    local tap_path
    if ! command -v brew >/dev/null 2>&1; then
        die "未找到 brew 命令"
    fi
    if ! tap_path="$(brew --repo "$TAP_NAME" 2>/dev/null)"; then
        die "本地未找到 tap「${TAP_NAME}」。请先执行: brew tap-new ${TAP_NAME}"
    fi
    if [[ ! -d "$tap_path" ]]; then
        die "tap 路径不存在: $tap_path"
    fi
    if [[ ! -d "$tap_path/Formula" ]]; then
        die "tap 中缺少 Formula/ 目录: $tap_path"
    fi
    printf '%s\n' "$tap_path"
}

# 确保主仓库工作区干净，避免把无关改动打进发布 commit
assert_clean_worktree() {
    if [[ -n "$(git status --porcelain)" ]]; then
        die "主仓库工作区不干净。请先提交或暂存变更后再发布。
当前状态:
$(git status --short)"
    fi
}

# 确保要创建的 tag 尚不存在
assert_tag_available() {
    local tag="$1"
    if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null 2>&1; then
        die "tag 已存在: ${tag}"
    fi
}

# ---------------------------------------------------------------------------
# 参数解析
# ---------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage 0
            ;;
        --version)
            [[ $# -ge 2 ]] || die "--version 需要参数"
            EXPLICIT_VERSION="$(normalize_version "$2")"
            shift 2
            ;;
        --resume)
            [[ $# -ge 2 ]] || die "--resume 需要版本号参数，例如: --resume 1.0.6"
            RESUME_MODE=1
            EXPLICIT_VERSION="$(normalize_version "$2")"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --skip-check)
            SKIP_CHECK=1
            shift
            ;;
        --skip-tap-audit)
            SKIP_TAP_AUDIT=1
            shift
            ;;
        --yes|-y)
            ASSUME_YES=1
            shift
            ;;
        --no-push)
            PUSH_REMOTE=0
            shift
            ;;
        patch|minor|major)
            if [[ -n "$BUMP_TYPE" ]]; then
                die "只能指定一个 bump 类型"
            fi
            BUMP_TYPE="$1"
            shift
            ;;
        *)
            die "未知参数: $1（使用 --help 查看用法）"
            ;;
    esac
done

if [[ -z "$BUMP_TYPE" && -z "$EXPLICIT_VERSION" ]]; then
    die "请指定 bump 类型（patch|minor|major）、--version X.Y.Z 或 --resume X.Y.Z"
fi
if [[ -n "$BUMP_TYPE" && -n "$EXPLICIT_VERSION" ]]; then
    die "不能同时指定 bump 类型与 --version/--resume"
fi

# ---------------------------------------------------------------------------
# 计算目标版本
# ---------------------------------------------------------------------------

CURRENT_VERSION="$(detect_current_version)"

if [[ -n "$EXPLICIT_VERSION" ]]; then
    NEW_VERSION="$EXPLICIT_VERSION"
else
    NEW_VERSION="$(bump_version "$CURRENT_VERSION" "$BUMP_TYPE")"
fi

NEW_TAG="v${NEW_VERSION}"
ARCHIVE_URL="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/archive/refs/tags/${NEW_TAG}.tar.gz"

if [[ "$RESUME_MODE" -eq 1 ]]; then
    # 续跑：要求本地已有该 tag（通常已 push）
    if [[ "$DRY_RUN" -eq 0 ]] && ! git rev-parse -q --verify "refs/tags/${NEW_TAG}" >/dev/null 2>&1; then
        die "续跑失败：本地不存在 tag ${NEW_TAG}。请确认 tag 已创建。"
    fi
else
    # 版本只能前进（允许 --version 跳到任意更新版本，但不允许回退）
    if [[ "$(printf '%s\n%s\n' "$CURRENT_VERSION" "$NEW_VERSION" | sort -V | head -n 1)" == "$NEW_VERSION" \
        && "$CURRENT_VERSION" != "$NEW_VERSION" ]]; then
        die "新版本 ${NEW_VERSION} 不能低于当前版本 ${CURRENT_VERSION}"
    fi
    if [[ "$CURRENT_VERSION" == "$NEW_VERSION" ]]; then
        die "新版本与当前版本相同: ${NEW_VERSION}"
    fi
fi

TAP_PATH="$(resolve_tap_repo)"

if [[ "$RESUME_MODE" -eq 1 ]]; then
    RELEASE_MODE_LABEL="resume"
else
    RELEASE_MODE_LABEL="full"
fi

# ---------------------------------------------------------------------------
# 发布计划摘要
# ---------------------------------------------------------------------------

cat <<EOF

========================================
  java-project-generator 发布计划
========================================
  当前版本 : ${CURRENT_VERSION}
  新版本   : ${NEW_VERSION}  (tag: ${NEW_TAG})
  bump     : ${BUMP_TYPE:-explicit}
  模式     : ${RELEASE_MODE_LABEL}
  源码包   : ${ARCHIVE_URL}
  主仓库   : ${PROJECT_ROOT}
  Tap 仓库 : ${TAP_PATH}
  dry-run  : ${DRY_RUN}
  推送远程 : ${PUSH_REMOTE}
  跳过检查 : ${SKIP_CHECK}
========================================

EOF

confirm "确认按上述计划发布？" || die "已取消"

# ---------------------------------------------------------------------------
# 1. 前置校验 / 2-5. 全量发布路径（bump → tag → push）
# ---------------------------------------------------------------------------

if [[ "$RESUME_MODE" -eq 0 ]]; then
    if [[ "$DRY_RUN" -eq 0 ]]; then
        assert_clean_worktree
        assert_tag_available "$NEW_TAG"
    fi

    if [[ "$SKIP_CHECK" -eq 0 ]]; then
        log "运行 scripts/check.sh ..."
        run bash scripts/check.sh
    else
        warn "已跳过 scripts/check.sh"
    fi

    log "更新 springboot SCRIPT_VERSION → ${NEW_VERSION}"
    if [[ "$DRY_RUN" -eq 0 ]]; then
        update_script_version "$NEW_VERSION"
    fi

    log "提交主仓库版本变更并创建 tag ${NEW_TAG}"
    if [[ "$DRY_RUN" -eq 0 ]]; then
        git add springboot
        git commit -m "chore: bump version to ${NEW_VERSION}"
        git tag -a "$NEW_TAG" -m "Release ${NEW_TAG}"
    else
        run git add springboot
        run git commit -m "chore: bump version to ${NEW_VERSION}"
        run git tag -a "$NEW_TAG" -m "Release ${NEW_TAG}"
    fi

    if [[ "$PUSH_REMOTE" -eq 1 ]]; then
        log "推送主仓库到 origin（含 tag）"
        run git push origin HEAD
        run git push origin "$NEW_TAG"
    else
        warn "已跳过 git push（--no-push）。后续无法从 GitHub 下载 archive，将中止。"
        if [[ "$DRY_RUN" -eq 0 ]]; then
            die "使用 --no-push 时无法完成 sha256 计算与 tap 发布。本地已创建 commit 与 tag ${NEW_TAG}。"
        fi
    fi
else
    log "续跑模式：跳过 bump / check / tag / push，从计算 sha256 继续"
fi

# ---------------------------------------------------------------------------
# 6. 下载 archive 并计算 sha256
# ---------------------------------------------------------------------------

log "计算 ${NEW_TAG} 源码包 sha256"
if [[ "$DRY_RUN" -eq 1 ]]; then
    NEW_SHA256="<dry-run-sha256>"
    printf '[dry-run] curl + shasum → %s\n' "$NEW_SHA256"
else
    NEW_SHA256="$(compute_archive_sha256 "$NEW_TAG")"
    log "sha256 = ${NEW_SHA256}"
fi

# ---------------------------------------------------------------------------
# 7. 同步 formula（url + sha256）与 SCRIPT_VERSION（再次确认一致）
# ---------------------------------------------------------------------------

log "同步 formula/java-project-generator.rb"
run bash scripts/sync-version.sh "$NEW_VERSION" "$NEW_SHA256"

# 语法检查
log "检查 formula Ruby 语法"
run ruby -c "$FORMULA_FILE"

# ---------------------------------------------------------------------------
# 8. 提交并推送主仓库中的 formula 更新
#
# 说明：formula 的正确 sha256 只能在 tag 推送后得到，因此该 commit
#       落在 tag 之后。Homebrew 实际使用的是 tap 仓库中的 formula，
#       主仓库 formula/ 仅作为示例与同步源，不影响已发布 tag 的内容。
# ---------------------------------------------------------------------------

log "提交主仓库 formula 更新"
if [[ "$DRY_RUN" -eq 0 ]]; then
    git add "$FORMULA_FILE" springboot
    # springboot 通常已在步骤 4 提交；此处主要提交 formula
    if [[ -n "$(git status --porcelain)" ]]; then
        git commit -m "chore: update formula for ${NEW_TAG}"
    else
        warn "没有需要提交的 formula 变更"
    fi
    if [[ "$PUSH_REMOTE" -eq 1 ]]; then
        git push origin HEAD
    fi
else
    run git add "$FORMULA_FILE" springboot
    run git commit -m "chore: update formula for ${NEW_TAG}"
    run git push origin HEAD
fi

# ---------------------------------------------------------------------------
# 9. 同步到本地 Homebrew Tap
#    顺序按 formula/README.md：先拷贝 → style/audit → 再 commit/push
# ---------------------------------------------------------------------------

log "同步 formula 到 tap: ${TAP_PATH}/Formula/${FORMULA_NAME}.rb"
run cp "$FORMULA_FILE" "${TAP_PATH}/Formula/${FORMULA_NAME}.rb"

# ---------------------------------------------------------------------------
# 10. 提交前执行 brew style / brew audit（style --fix 可能改写 formula）
# ---------------------------------------------------------------------------

if [[ "$SKIP_TAP_AUDIT" -eq 0 ]]; then
    log "运行 brew style --fix / brew audit（提交前）"
    # tap 简写：hanqunfeng/homebrew-tap → hanqunfeng/tap
    run brew style --fix hanqunfeng/tap || warn "brew style 未完全通过，请人工检查"
    run brew audit --tap=hanqunfeng/tap || warn "brew audit 未完全通过，请人工检查"
else
    warn "已跳过 brew style / brew audit"
fi

# 若 brew style --fix 改写了 tap 中的 formula，回拷到主仓库以保持两边一致
if [[ "$DRY_RUN" -eq 0 && "$SKIP_TAP_AUDIT" -eq 0 ]]; then
    if ! cmp -s "$FORMULA_FILE" "${TAP_PATH}/Formula/${FORMULA_NAME}.rb"; then
        log "brew style 修改了 formula，回同步到主仓库"
        cp "${TAP_PATH}/Formula/${FORMULA_NAME}.rb" "$FORMULA_FILE"
        git add "$FORMULA_FILE"
        if [[ -n "$(git status --porcelain)" ]]; then
            git commit -m "chore: apply brew style fixes for ${NEW_TAG}"
            if [[ "$PUSH_REMOTE" -eq 1 ]]; then
                git push origin HEAD
            fi
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 11. 提交并推送 tap
# ---------------------------------------------------------------------------

log "提交并推送 tap 仓库"
if [[ "$DRY_RUN" -eq 0 ]]; then
    (
        cd "$TAP_PATH"
        git add "Formula/${FORMULA_NAME}.rb"

        if [[ -z "$(git status --porcelain)" ]]; then
            warn "tap 中 formula 无变化，跳过提交"
        else
            git commit -m "${FORMULA_NAME} ${NEW_TAG}"
            if [[ "$PUSH_REMOTE" -eq 1 ]]; then
                # 默认推送到当前分支（通常为 main）
                git push
            fi
        fi
    )
else
    run git -C "$TAP_PATH" add "Formula/${FORMULA_NAME}.rb"
    run git -C "$TAP_PATH" commit -m "${FORMULA_NAME} ${NEW_TAG}"
    run git -C "$TAP_PATH" push
fi

# ---------------------------------------------------------------------------
# 完成
# ---------------------------------------------------------------------------

cat <<EOF

发布完成。

  版本     : ${NEW_TAG}
  源码包   : ${ARCHIVE_URL}
  sha256   : ${NEW_SHA256}
  主仓库   : 已更新 SCRIPT_VERSION 与 formula/
  Tap      : ${TAP_PATH}/Formula/${FORMULA_NAME}.rb

用户安装:
  brew tap hanqunfeng/tap
  brew install java-project-generator
  # 或: brew install hanqunfeng/tap/java-project-generator

已安装用户升级:
  brew update && brew upgrade java-project-generator

EOF
