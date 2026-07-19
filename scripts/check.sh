#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

if ! command -v bats >/dev/null 2>&1; then
    echo "缺少 bats，请先安装 bats-core。"
    exit 4
fi

if ! command -v shellcheck >/dev/null 2>&1; then
    echo "缺少 shellcheck，请先安装 shellcheck。"
    exit 4
fi

if ! command -v rg >/dev/null 2>&1; then
    echo "缺少 ripgrep（rg），测试中会用到 rg。"
    exit 4
fi

# SC1090/SC2154: 本项目大量 source + 入口变量注入模式，属于有意设计。
# SC2034/SC2207: 补全脚本与兼容写法会触发噪音，先排除，后续可分阶段收敛。
shellcheck -x -e SC1090,SC2154,SC2034 springboot lib/*.sh
shellcheck -e SC2034,SC2207 completions/springboot.bash

# macOS 默认 bash 3.2 在 UTF-8 locale 下无法稳定处理中文 @test 名称，
# 会导致 bats 预处理与执行阶段的函数名不一致（unknown test name）。
# 强制 C locale 后 bats 会使用十六进制编码函数名，描述文本仍正常显示中文。
export LC_ALL=C
export LANG=C

bats test/springboot.bats
bats test/deps.bats

if [[ "${RUN_INTEGRATION_TESTS:-0}" == "1" ]]; then
    bats test/integration.bats
fi
