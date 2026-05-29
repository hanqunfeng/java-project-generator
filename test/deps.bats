#!/usr/bin/env bats

load_deps_harness() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT_DIR="$PROJECT_ROOT"
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
