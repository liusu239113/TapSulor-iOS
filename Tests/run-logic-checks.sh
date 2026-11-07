#!/bin/bash
# 在 macOS 上编译并运行纯逻辑检查。只需要命令行工具（swiftc），不需要打开 Xcode 工程。
# 用法：bash Tests/run-logic-checks.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swiftc -o "$WORK/logic-checks" \
  "$HERE"/../TapSulor/Sources/Core/*.swift \
  "$HERE/logic-checks/main.swift"

"$WORK/logic-checks"
