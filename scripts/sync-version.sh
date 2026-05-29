#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

if [ "$#" -lt 2 ]; then
    echo "用法: bash scripts/sync-version.sh <version> <sha256>"
    echo "示例: bash scripts/sync-version.sh 1.0.2 abcdef123..."
    exit 1
fi

version="$1"
sha256="$2"
tag="v${version}"
archive_url="https://github.com/hanqunfeng/java-project-generator/archive/refs/tags/${tag}.tar.gz"

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

tmp_file="$(mktemp)"
awk -v url="$archive_url" -v hash="$sha256" '
{
    if ($0 ~ /^[[:space:]]*url "/) {
        print "  url \"" url "\""
    } else if ($0 ~ /^[[:space:]]*sha256 "/) {
        print "  sha256 \"" hash "\""
    } else {
        print $0
    }
}
' formula/java-project-generator.rb > "$tmp_file"
mv "$tmp_file" formula/java-project-generator.rb

echo "已同步版本:"
echo "  springboot SCRIPT_VERSION=${version}"
echo "  formula url=${archive_url}"
echo "  formula sha256=${sha256}"
