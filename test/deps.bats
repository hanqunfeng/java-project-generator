#!/usr/bin/env bats

load_deps_harness() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT_DIR="$PROJECT_ROOT"
  DEPS_CACHE_DIR="$(mktemp -d)"
  export DEPS_CACHE_DIR
  EXIT_PARAM=1
  EXIT_NETWORK=2
  EXIT_FS=3
  EXIT_DEP=4
  tmp_files=()
  register_tmp_file() {
    local file="$1"
    [ -n "$file" ] && tmp_files+=("$file")
  }
  log_info() { :; }
  log_warn() { :; }
  log_error() { printf '%s\n' "$*" >&2; }
  log_success() { :; }
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/lib/arg-common.sh"
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/lib/deps.sh"
}

@test "normalize_deps_csv 去空白并去重" {
  load_deps_harness
  run normalize_deps_csv " web, web ,data-jpa,web "
  [ "$status" -eq 0 ]
  [ "$output" = "web,data-jpa" ]
}

@test "validate_dependencies_format 接受合法依赖 ID" {
  load_deps_harness
  run bash -c '
    source "$1/lib/arg-common.sh"
    SCRIPT_DIR="$1"
    EXIT_PARAM=1
    EXIT_NETWORK=2
    EXIT_FS=3
    EXIT_DEP=4
    tmp_files=()
    register_tmp_file() { :; }
    log_error() { :; }
    source "$1/lib/deps.sh"
    validate_dependencies_format "web,data-jpa,mysql"
  ' bash "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
}

@test "validate_dependencies_format 拒绝非法依赖 ID" {
  load_deps_harness
  run bash -c '
    source "$1/lib/arg-common.sh"
    SCRIPT_DIR="$1"
    EXIT_PARAM=1
    EXIT_NETWORK=2
    EXIT_FS=3
    EXIT_DEP=4
    tmp_files=()
    register_tmp_file() { :; }
    log_error() { :; }
    source "$1/lib/deps.sh"
    validate_dependencies_format "Bad-ID"
  ' bash "$PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"依赖ID不合法"* ]]
}

@test "is_cache_file_expired 对刚创建文件未过期" {
  load_deps_harness
  cacheFile="$(mktemp)"
  printf 'cached\n' > "$cacheFile"
  DEPS_CACHE_TTL_SECONDS=86400
  run is_cache_file_expired "$cacheFile" "$DEPS_CACHE_TTL_SECONDS"
  [ "$status" -eq 1 ]
  rm -f "$cacheFile"
}

@test "is_cache_file_expired TTL 为 0 时视为过期" {
  load_deps_harness
  cacheFile="$(mktemp)"
  printf 'cached\n' > "$cacheFile"
  run is_cache_file_expired "$cacheFile" 0
  [ "$status" -eq 0 ]
  rm -f "$cacheFile"
}

@test "list_boot_versions 解析元数据并标记默认版本" {
  load_deps_harness
  fake_bin="$(mktemp -d)"
  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cat > "$out" <<'JSON'
{"bootVersion":{"default":"4.0.7.RELEASE","values":[{"id":"4.1.0.RELEASE","name":"4.1.0"},{"id":"4.0.7.RELEASE","name":"4.0.7"}]}}
JSON
EOF
  chmod +x "$fake_bin/curl"
  rm -f "$DEPS_CACHE_DIR/boot-versions.tsv"
  PATH="$fake_bin:$PATH" run list_boot_versions
  [ "$status" -eq 0 ]
  [[ "$output" == *"默认版本:   4.0.7.RELEASE"* ]]
  [[ "$output" == *"*4.0.7.RELEASE"* ]]
  [[ "$output" == *"4.1.0.RELEASE"* ]]
  rm -rf "$fake_bin"
}

@test "list_boot_versions 对非 JSON 响应给出明确错误" {
  load_deps_harness
  fake_bin="$(mktemp -d)"
  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf '<html>error</html>\n' > "$out"
EOF
  chmod +x "$fake_bin/curl"
  rm -f "$DEPS_CACHE_DIR/boot-versions.tsv"
  PATH="$fake_bin:$PATH" run list_boot_versions
  [ "$status" -eq 2 ]
  [[ "$output" == *"不是有效 JSON"* ]]
  rm -rf "$fake_bin"
}

@test "resolve_project_boot_version 未指定时使用默认版本" {
  load_deps_harness
  mkdir -p "$DEPS_CACHE_DIR"
  cat > "$DEPS_CACHE_DIR/boot-versions.tsv" <<'EOF'
DEFAULT	4.0.7.RELEASE
4.0.7.RELEASE	4.0.7
EOF
  bootVersionSpecified=false
  bootVersion=""
  run bash -c '
    source "$1/lib/arg-common.sh"
    SCRIPT_DIR="$1"
    DEPS_CACHE_DIR="$2"
    export DEPS_CACHE_DIR
    EXIT_PARAM=1
    EXIT_NETWORK=2
    EXIT_FS=3
    EXIT_DEP=4
    tmp_files=()
    register_tmp_file() { :; }
    log_error() { printf "%s\n" "$*" >&2; }
    source "$1/lib/deps.sh"
    bootVersionSpecified=false
    bootVersion=""
    resolve_project_boot_version
    printf "%s\n" "$bootVersion"
  ' bash "$PROJECT_ROOT" "$DEPS_CACHE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "4.0.7" ]
}

@test "resolve_project_boot_version 拒绝已下线版本" {
  load_deps_harness
  mkdir -p "$DEPS_CACHE_DIR"
  cat > "$DEPS_CACHE_DIR/boot-versions.tsv" <<'EOF'
DEFAULT	4.0.7.RELEASE
4.0.7.RELEASE	4.0.7
EOF
  run bash -c '
    source "$1/lib/arg-common.sh"
    SCRIPT_DIR="$1"
    DEPS_CACHE_DIR="$2"
    export DEPS_CACHE_DIR
    EXIT_PARAM=1
    EXIT_NETWORK=2
    EXIT_FS=3
    EXIT_DEP=4
    tmp_files=()
    register_tmp_file() { :; }
    log_error() { printf "%s\n" "$*" >&2; }
    source "$1/lib/deps.sh"
    bootVersionSpecified=true
    bootVersion="3.5.14"
    resolve_project_boot_version
  ' bash "$PROJECT_ROOT" "$DEPS_CACHE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"已不被当前 Initializr 支持"* ]]
}
