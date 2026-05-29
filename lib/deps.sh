#!/usr/bin/env bash
# ========= 依赖 / Initializr 交互逻辑 =========
#
# 由 springboot 入口在 trap/日志初始化后 source。
# 不反向 source springboot。
#
# 依赖入口脚本提供的全局能力:
#   SCRIPT_DIR
#   register_tmp_file / tmp_files trap
#   log_info / log_warn / log_error / log_success
#   EXIT_PARAM / EXIT_NETWORK / EXIT_FS / EXIT_DEP
#
# 运行时变量（由 CLI 解析注入）:
#   bootVersion, projectType, projectLanguage, gradleDsl, javaVersion
#   depsOutput, depsPreviewCsv, depsForceRefresh

DEFAULT_DEPS="web,devtools"
INITIALIZR_BASE_URL="${INITIALIZR_BASE_URL:-https://start.spring.io}"
INITIALIZR_BASE_URL="${INITIALIZR_BASE_URL%/}"
DEPS_CACHE_TTL_SECONDS="${DEPS_CACHE_TTL_SECONDS:-86400}"

# Boot 参数名兼容探测结果：
# - BOOT_PARAM_KEY: metadata/client 接口参数键
# - STARTER_BOOT_PARAM_KEY: starter.zip 接口参数键
BOOT_PARAM_KEY=""
STARTER_BOOT_PARAM_KEY=""

DEP_CACHE_FILE=""
depsForceRefresh="${depsForceRefresh:-false}"

# -----------------------------------------------------------------------------
# 函数: normalize_deps_csv
# 作用: 规范化依赖 CSV，确保下游校验和请求参数稳定。
# 入参:
#   $1 -> 原始 CSV（可包含空格与重复项）
# 返回:
#   stdout -> 去空白、去重、保持首出现顺序后的 CSV
# -----------------------------------------------------------------------------
normalize_deps_csv() {
    normalize_csv_unique_common "$1"
}

initializr_url() {
    local path="$1"
    printf '%s/%s\n' "$INITIALIZR_BASE_URL" "${path#/}"
}

file_mtime_epoch() {
    local path="$1"
    if stat -f "%m" "$path" >/dev/null 2>&1; then
        stat -f "%m" "$path"
        return 0
    fi
    if stat -c "%Y" "$path" >/dev/null 2>&1; then
        stat -c "%Y" "$path"
        return 0
    fi
    return 1
}

is_cache_file_expired() {
    local cacheFile="$1"
    local ttlSeconds="$2"
    local nowEpoch fileEpoch
    nowEpoch=$(date +%s)
    fileEpoch=$(file_mtime_epoch "$cacheFile") || return 0
    [ $((nowEpoch - fileEpoch)) -ge "$ttlSeconds" ]
}

# -----------------------------------------------------------------------------
# 函数: open_browser
# 作用: 跨平台打开浏览器查看目标文件/URL。
# 入参:
#   $1 -> 本地文件路径或 URL
# 返回:
#   0 -> 找到可用打开命令并执行
#   1 -> 当前环境没有可用打开命令
# -----------------------------------------------------------------------------
open_browser() {
    local target="$1"
    if command -v open >/dev/null 2>&1; then
        open "$target"
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$target"
    elif command -v wslview >/dev/null 2>&1; then
        wslview "$target"
    elif command -v explorer.exe >/dev/null 2>&1; then
        explorer.exe "$target"
    else
        return 1
    fi
}

# -----------------------------------------------------------------------------
# 函数: resolve_boot_param_key
# 作用: 探测 metadata/client 接口支持的 Boot 参数名。
# 策略:
#   1) 优先读取缓存文件
#   2) 顺序探测 bootVersion / boot-version
#   3) 成功后写回缓存
# 返回:
#   0 -> 总能返回可用键（探测失败时回退 bootVersion）
# -----------------------------------------------------------------------------
resolve_boot_param_key_generic() {
    local probeKind="$1"
    local cacheKeyFile="$2"
    local key
    local cachedKey
    local cacheDir="${SCRIPT_DIR}/deps-cache"
    local resolvedKey=""
    local probeUrl
    local tmpProbe

    if [ -s "$cacheKeyFile" ]; then
        cachedKey=$(awk 'NF{print; exit}' "$cacheKeyFile")
        if [ "$cachedKey" = "bootVersion" ] || [ "$cachedKey" = "boot-version" ]; then
            printf '%s\n' "$cachedKey"
            return 0
        fi
    fi

    for key in "bootVersion" "boot-version"; do
        if [ "$probeKind" = "starter" ]; then
            if curl --fail --show-error --location --retry 1 --retry-delay 1 --no-progress-meter "$(initializr_url "starter.zip")" \
                -d type="maven-project" \
                -d "${key}=${bootVersion}" \
                -d javaVersion="17" \
                -d language="java" \
                -d groupId="com.example" \
                -d artifactId="probe-boot-param" \
                -d version="0.0.1" \
                -d name="probe-boot-param" \
                -d packageName="com.example.probe" \
                -d configurationFileFormat="properties" \
                -d dependencies="web" \
                -o /dev/null >/dev/null 2>&1; then
                resolvedKey="$key"
                break
            fi
            continue
        fi

        tmpProbe=$(mktemp)
        register_tmp_file "$tmpProbe"
        probeUrl="$(initializr_url "metadata/client")?${key}=${bootVersion}"
        if curl --fail --show-error --location --retry 1 --retry-delay 1 --no-progress-meter "$probeUrl" -o "$tmpProbe" >/dev/null 2>&1; then
            if command -v python3 >/dev/null 2>&1 && python3 - "$tmpProbe" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        data = json.load(f)
    ok = bool(data.get("dependencies", {}).get("values"))
except Exception:
    ok = False
sys.exit(0 if ok else 1)
PY
            then
                resolvedKey="$key"
                break
            fi
            if command -v jq >/dev/null 2>&1 && jq -e '.dependencies.values | length > 0' "$tmpProbe" >/dev/null 2>&1; then
                resolvedKey="$key"
                break
            fi
        fi
    done

    if [ -z "$resolvedKey" ]; then
        resolvedKey="bootVersion"
    fi
    mkdir -p "$cacheDir" >/dev/null 2>&1 || true
    printf '%s\n' "$resolvedKey" > "$cacheKeyFile" 2>/dev/null || true
    printf '%s\n' "$resolvedKey"
}

resolve_boot_param_key() {
    local cacheKeyFile="${SCRIPT_DIR}/deps-cache/boot-param-key.cache"
    if [ -n "$BOOT_PARAM_KEY" ]; then
        return 0
    fi
    BOOT_PARAM_KEY="$(resolve_boot_param_key_generic "metadata" "$cacheKeyFile")"
    [ "$BOOT_PARAM_KEY" = "bootVersion" ] || [ "$BOOT_PARAM_KEY" = "boot-version" ] || BOOT_PARAM_KEY="bootVersion"
}

# -----------------------------------------------------------------------------
# 函数: resolve_starter_boot_param_key
# 作用: 探测 starter.zip 接口支持的 Boot 参数名。
# 说明:
#   metadata/client 与 starter.zip 在历史版本上可能存在参数差异，
#   因此单独探测并独立缓存。
# 返回:
#   0 -> 总能返回可用键（探测失败时回退 bootVersion）
# -----------------------------------------------------------------------------
resolve_starter_boot_param_key() {
    local cacheKeyFile="${SCRIPT_DIR}/deps-cache/starter-boot-param-key.cache"
    if [ -n "$STARTER_BOOT_PARAM_KEY" ]; then
        return 0
    fi

    STARTER_BOOT_PARAM_KEY="$(resolve_boot_param_key_generic "starter" "$cacheKeyFile")"
    [ "$STARTER_BOOT_PARAM_KEY" = "bootVersion" ] || [ "$STARTER_BOOT_PARAM_KEY" = "boot-version" ] || STARTER_BOOT_PARAM_KEY="bootVersion"
}

# -----------------------------------------------------------------------------
# 函数: ensure_dependency_catalog_cache
# 作用: 保障依赖缓存存在且格式有效。
# 流程:
#   1) 若缓存可用直接复用
#   2) 否则拉取 metadata/client JSON
#   3) 用内嵌 Python 转换为 Markdown 表格并落盘
# 输出:
#   全局变量 DEP_CACHE_FILE -> 可用缓存文件路径
# -----------------------------------------------------------------------------
ensure_dependency_catalog_cache() {
    resolve_boot_param_key
    local metadataUrl
    metadataUrl="$(initializr_url "metadata/client")?${BOOT_PARAM_KEY}=${bootVersion}"
    local cacheDir="${SCRIPT_DIR}/deps-cache"
    local cacheFile="${cacheDir}/boot-${bootVersion}.md"
    local legacyCacheFile="${cacheDir}/boot-${bootVersion}.txt"
    local firstDataLine
    local tmpFile
    local tmpOutput

    if [ ! -e "$cacheFile" ] && [ -s "$legacyCacheFile" ]; then
        mkdir -p "$cacheDir" >/dev/null 2>&1
        mv "$legacyCacheFile" "$cacheFile"
        echo "已迁移旧缓存到 Markdown 文件: ${cacheFile}"
    fi

    if [[ "$depsForceRefresh" != "true" && -s "$cacheFile" ]]; then
        firstDataLine=$(awk 'NF{print; exit}' "$cacheFile")
        if [ "$firstDataLine" = "| Group | ID | Name | Description |" ] && ! is_cache_file_expired "$cacheFile" "$DEPS_CACHE_TTL_SECONDS"; then
            DEP_CACHE_FILE="$cacheFile"
            return 0
        fi
        echo "检测到旧版或过期缓存，正在刷新: ${cacheFile}"
    fi

    tmpFile=$(mktemp)
    tmpOutput=$(mktemp)
    register_tmp_file "$tmpFile"
    register_tmp_file "$tmpOutput"
    if ! curl --fail --show-error --location --retry 3 --retry-delay 1 --no-progress-meter "$metadataUrl" -o "$tmpFile"; then
        echo "依赖列表获取失败: 请检查网络或 Boot 版本 (${bootVersion}) 是否可用"
        exit "$EXIT_NETWORK"
    fi

    if command -v python3 >/dev/null 2>&1 && python3 - "$tmpFile" > "$tmpOutput" <<'PY'
import json
import sys

def esc(text: str) -> str:
    return (text or "").replace("|", "\\|").replace("\n", " ").strip()

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)

groups = data.get("dependencies", {}).get("values", [])
if not groups:
    print("未获取到依赖数据，请检查 Spring Initializr 返回内容")
    sys.exit(1)

print("| Group | ID | Name | Description |")
print("| --- | --- | --- | --- |")

for group in groups:
    group_name = esc(group.get("name", "Other"))
    for item in group.get("values", []):
        dep_id = esc(item.get("id", ""))
        dep_name = esc(item.get("name", ""))
        desc = esc(item.get("description", ""))
        print(f"| {group_name} | {dep_id} | {dep_name} | {desc} |")
PY
    then
        :
    elif command -v jq >/dev/null 2>&1 && {
        {
            printf '%s\n' "| Group | ID | Name | Description |"
            printf '%s\n' "| --- | --- | --- | --- |"
            jq -r '
            .dependencies.values[]? as $g |
            $g.values[]? |
            "| \($g.name // "Other") | \(.id // "") | \(.name // "") | \((.description // "") | gsub("\n"; " ") | gsub("\\|"; "\\\\|")) |"
            ' "$tmpFile"
        } > "$tmpOutput"
    }; then
        :
    else
        echo "依赖列表解析失败: 需要可用的 python3 或 jq 以解析 Initializr 元数据"
        exit "$EXIT_DEP"
    fi

    if ! mkdir -p "$cacheDir"; then
        echo "缓存目录创建失败: ${cacheDir}"
        exit "$EXIT_FS"
    fi

    if ! mv "$tmpOutput" "$cacheFile"; then
        echo "依赖缓存写入失败: ${cacheFile}"
        exit "$EXIT_FS"
    fi

    # tmpOutput 已成功 move，避免在退出时重复清理该路径。
    tmp_files=("${tmp_files[@]/$tmpOutput}")
    echo "已缓存依赖列表: ${cacheFile}"
    DEP_CACHE_FILE="$cacheFile"
}

# -----------------------------------------------------------------------------
# 函数: print_dependency_catalog
# 作用: 在终端渲染依赖缓存 Markdown 表格。
# 依赖:
#   glow
# -----------------------------------------------------------------------------
print_dependency_catalog() {
    ensure_dependency_catalog_cache
    echo "使用本地缓存: ${DEP_CACHE_FILE}"
    if ! command -v glow >/dev/null 2>&1; then
        echo "未检测到 glow 命令，请先安装 glow 后再查看缓存文件: ${DEP_CACHE_FILE}"
        exit "$EXIT_DEP"
    fi
    glow "$DEP_CACHE_FILE" -w 150 </dev/null
}

# -----------------------------------------------------------------------------
# 函数: extract_dependencies_declaration_block
# 作用: 请求 Initializr 构建模板并提取依赖声明片段（仅返回 dependencies 内部内容）。
# 说明:
#   - maven: 输出 pom.xml 中 <dependencies> ... </dependencies> 内部内容
#   - gradle: 输出 build.gradle 中 dependencies { ... } 内部内容
# 入参:
#   $1 -> 依赖 CSV（如 web,data-jpa,mysql）
#   $2 -> 构建类型（maven | gradle）
# -----------------------------------------------------------------------------
extract_dependencies_declaration_block() {
    local depsCsv="$1"
    local targetType="$2"
    local endpoint
    local tmpFile
    local descriptorUrl
    local bootParamKey

    if [ -z "$depsCsv" ]; then
        log_error "依赖列表不能为空，请传入至少一个依赖ID（如 --deps=web）"
        exit "$EXIT_PARAM"
    fi

    if [[ "$targetType" != "maven" && "$targetType" != "gradle" ]]; then
        log_error "构建工具不合法: 仅支持 maven 或 gradle"
        exit "$EXIT_PARAM"
    fi

    if [[ "$targetType" == "maven" ]]; then
        endpoint="pom.xml"
    elif [[ "${gradleDsl:-groovy}" == "kotlin" ]]; then
        endpoint="build.gradle.kts"
    else
        endpoint="build.gradle"
    fi

    resolve_starter_boot_param_key
    bootParamKey="${STARTER_BOOT_PARAM_KEY:-bootVersion}"
    descriptorUrl="$(initializr_url "${endpoint}")?type=${targetType}-project&language=${projectLanguage}&${bootParamKey}=${bootVersion}&groupId=com.example&artifactId=deps-preview&name=deps-preview&packageName=com.example.depspreview&packaging=jar&javaVersion=${javaVersion}&dependencies=${depsCsv}"

    tmpFile=$(mktemp)
    register_tmp_file "$tmpFile"
    if ! curl --fail --show-error --location --retry 3 --retry-delay 1 --no-progress-meter "$descriptorUrl" -o "$tmpFile"; then
        log_error "依赖声明获取失败: 请检查网络、Boot 版本 (${bootVersion}) 或依赖ID是否可用"
        exit "$EXIT_NETWORK"
    fi

    if ! python3 - "$tmpFile" "$targetType" <<'PY'
import sys

path = sys.argv[1]
project_type = sys.argv[2]

with open(path, "r", encoding="utf-8") as f:
    lines = f.read().splitlines()

if project_type == "maven":
    start = next((i for i, line in enumerate(lines) if "<dependencies>" in line), -1)
    if start < 0:
        print("未在 pom.xml 中找到 <dependencies> 节点")
        sys.exit(1)
    end = next((i for i in range(start + 1, len(lines)) if "</dependencies>" in lines[i]), -1)
    if end < 0:
        print("未在 pom.xml 中找到 </dependencies> 节点")
        sys.exit(1)
    print("\n".join(lines[start + 1:end]).rstrip())
    sys.exit(0)

start = next((i for i, line in enumerate(lines) if line.strip().startswith("dependencies {")), -1)
if start < 0:
    print("未在 build.gradle 中找到 dependencies { 块")
    sys.exit(1)

depth = lines[start].count("{") - lines[start].count("}")
inner = []
for line in lines[start + 1:]:
    depth += line.count("{")
    depth -= line.count("}")
    if depth <= 0:
        break
    inner.append(line)

if not inner:
    print("未提取到依赖声明内容")
    sys.exit(1)

print("\n".join(inner).rstrip())
PY
    then
        if [[ "$targetType" == "maven" ]]; then
            log_error "pom.xml 解析失败: 未能提取 dependencies 内容"
        else
            log_error "build.gradle 解析失败: 未能提取 dependencies 内容"
        fi
        exit "$EXIT_DEP"
    fi
}

# -----------------------------------------------------------------------------
# 函数: print_dependencies_declaration
# 作用: 按当前 --type 输出依赖声明片段。
# 入参:
#   $1 -> 依赖 CSV（如 web,data-jpa,mysql）
# -----------------------------------------------------------------------------
print_dependencies_declaration() {
    local depsCsv="$1"
    if [[ "$projectType" != "maven" && "$projectType" != "gradle" ]]; then
        log_error "构建工具不合法: 仅支持 --type=maven 或 --type=gradle"
        exit "$EXIT_PARAM"
    fi
    extract_dependencies_declaration_block "$depsCsv" "$projectType"
}

# -----------------------------------------------------------------------------
# 函数: open_dependency_catalog_web
# 作用: 把依赖 Markdown 渲染成 HTML 并自动打开浏览器。
# 依赖:
#   pandoc + 浏览器打开命令（open/xdg-open/wslview/explorer.exe）
# -----------------------------------------------------------------------------
open_dependency_catalog_web() {
    local cacheDir="${SCRIPT_DIR}/deps-cache"
    local cacheMarkdown="boot-${bootVersion}.md"
    local htmlFile="boot-web.html"
    local cssPath="${SCRIPT_DIR}/assets/web_style.css"
    local cssArg="../assets/web_style.css"

    ensure_dependency_catalog_cache

    if ! command -v pandoc >/dev/null 2>&1; then
        log_error "未检测到 pandoc，请先安装后再执行 'springboot deps list --output=web'"
        exit "$EXIT_DEP"
    fi

    if [ ! -f "${cssPath}" ]; then
        log_error "未找到样式文件: ${cssPath}"
        log_warn "请确认 assets/web_style.css 存在"
        exit "$EXIT_FS"
    fi

    (
        cd "$cacheDir" || exit "$EXIT_FS"
        pandoc "$cacheMarkdown" --standalone --metadata title="SpringBoot ${bootVersion} 官方依赖列表" -o "$htmlFile" --css="$cssArg" && open_browser "$htmlFile"
    ) || {
        log_error "依赖网页渲染或打开失败，请检查 pandoc 或系统浏览器打开命令是否可用"
        exit "$EXIT_DEP"
    }

    log_success "已使用浏览器打开: ${cacheDir}/${htmlFile}"
    if ! command -v glow >/dev/null 2>&1; then
        log_warn "未检测到 glow 命令，请先安装 glow 后再查看缓存文件: ${DEP_CACHE_FILE}"
        return 0
    fi
    log_info "如需在终端查看 Markdown 表格: glow ${DEP_CACHE_FILE} -w 150"
}

# -----------------------------------------------------------------------------
# 函数: validate_dependencies_against_initializr
# 作用: 校验依赖参数中的每个依赖 ID 是否被当前 Boot 版本支持。
# 入参:
#   $1 -> 依赖 CSV（来自 --deps）
# 返回:
#   0 -> 全部合法
#   非 0 -> 存在无效依赖，附带相近候选提示
# -----------------------------------------------------------------------------
validate_dependencies_against_initializr() {
    local requestedCsv="$1"
    resolve_boot_param_key
    local metadataUrl
    metadataUrl="$(initializr_url "metadata/client")?${BOOT_PARAM_KEY}=${bootVersion}"
    local tmpFile
    tmpFile=$(mktemp)
    register_tmp_file "$tmpFile"
    if ! curl --fail --show-error --location --retry 3 --retry-delay 1 --no-progress-meter "$metadataUrl" -o "$tmpFile"; then
        echo "依赖元数据获取失败: 请检查网络或 Boot 版本 (${bootVersion}) 是否可用"
        exit "$EXIT_NETWORK"
    fi

    if command -v python3 >/dev/null 2>&1 && python3 - "$tmpFile" "$requestedCsv" <<'PY'
import difflib
import json
import sys

metadata_path = sys.argv[1]
requested = [x for x in sys.argv[2].split(",") if x]

with open(metadata_path, "r", encoding="utf-8") as f:
    data = json.load(f)

available = {}
for group in data.get("dependencies", {}).get("values", []):
    for item in group.get("values", []):
        dep_id = item.get("id")
        if dep_id:
            available[dep_id] = item

unknown = [x for x in requested if x not in available]
if not unknown:
    sys.exit(0)

print(f"存在无效依赖ID: {', '.join(unknown)}")
all_ids = sorted(available.keys())
for bad in unknown:
    guesses = difflib.get_close_matches(bad, all_ids, n=3, cutoff=0.45)
    if guesses:
        print(f"  - {bad}，你可能想要: {', '.join(guesses)}")

print("可先执行 'springboot deps list --boot=<版本>' 查看当前 Boot 版本支持的依赖ID。")
sys.exit(1)
PY
    then
        return 0
    elif command -v jq >/dev/null 2>&1; then
        local availableIds
        local unknownIds
        availableIds=$(jq -r '.dependencies.values[]?.values[]?.id // empty' "$tmpFile" | sort -u)
        unknownIds=""
        while IFS= read -r dep; do
            [ -z "$dep" ] && continue
            if ! printf '%s\n' "$availableIds" | awk -v target="$dep" '$0 == target {found=1} END {exit found?0:1}'; then
                unknownIds="${unknownIds}${dep},"
            fi
        done < <(printf '%s\n' "$requestedCsv" | tr ',' '\n')
        if [ -n "$unknownIds" ]; then
            unknownIds="${unknownIds%,}"
            echo "存在无效依赖ID: ${unknownIds}"
            echo "可先执行 'springboot deps list --boot=<版本>' 查看当前 Boot 版本支持的依赖ID。"
            exit "$EXIT_PARAM"
        fi
        return 0
    else
        echo "依赖校验失败: 需要可用的 python3 或 jq 解析 Initializr 元数据"
        exit "$EXIT_DEP"
    fi
}

deps_search_command() {
    local query="$1"
    ensure_dependency_catalog_cache
    [ -n "$query" ] || { echo "缺少 --query 参数"; exit "$EXIT_PARAM"; }
    awk -F'|' -v keyword="$query" '
        BEGIN { kw=tolower(keyword) }
        /^\|/ {
            line=tolower($0)
            if (index(line, kw) > 0 && $0 !~ /\| --- \|/ && $0 !~ /\| Group \|/) {
                print $0
            }
        }
    ' "$DEP_CACHE_FILE"
}

validate_dependencies_format() {
    local csv="$1"
    if [[ "$csv" == "" ]]; then
        return 0
    fi
    while IFS= read -r dep; do
        [ -z "$dep" ] && continue
        if [[ ! "$dep" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
            echo "依赖ID不合法: '$dep'，仅允许小写字母、数字、短横线，且首字符必须是字母或数字"
            exit "$EXIT_PARAM"
        fi
    done < <(echo "$csv" | tr ',' '\n')
}

validate_deps_list_args() {
    if [[ ! "$bootVersion" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]]; then
        log_error "Boot版本不合法: 仅支持 x.y.z 或 x.y.z-标识，例如 3.5.14 或 3.5.14-SNAPSHOT"
        exit "$EXIT_PARAM"
    fi
    if [[ "$depsOutput" != "terminal" && "$depsOutput" != "web" ]]; then
        echo "--output 不合法: 仅支持 terminal 或 web"
        exit "$EXIT_PARAM"
    fi
}

validate_deps_preview_args() {
    if [[ ! "$bootVersion" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]]; then
        log_error "Boot版本不合法: 仅支持 x.y.z 或 x.y.z-标识，例如 3.5.14 或 3.5.14-SNAPSHOT"
        exit "$EXIT_PARAM"
    fi
    if [[ "$projectType" != "maven" && "$projectType" != "gradle" ]]; then
        echo "构建工具不合法: 仅支持 maven 或 gradle"
        exit "$EXIT_PARAM"
    fi
    if [[ "$javaVersion" != "17" && "$javaVersion" != "21" && "$javaVersion" != "25" ]]; then
        echo "Java版本不合法: 仅支持 17、21 或 25"
        exit "$EXIT_PARAM"
    fi
    if [[ "$projectLanguage" != "java" && "$projectLanguage" != "kotlin" && "$projectLanguage" != "groovy" ]]; then
        echo "language 不合法: 仅支持 java、kotlin 或 groovy"
        exit "$EXIT_PARAM"
    fi
    if [[ "$gradleDsl" != "groovy" && "$gradleDsl" != "kotlin" ]]; then
        echo "gradle-dsl 不合法: 仅支持 groovy 或 kotlin"
        exit "$EXIT_PARAM"
    fi
    if [ -z "$depsPreviewCsv" ]; then
        log_error "deps preview 模式必须提供 --deps=<依赖ID列表>"
        exit "$EXIT_PARAM"
    fi
    validate_dependencies_format "$depsPreviewCsv"
}
