#!/usr/bin/env bash
# SplitHorizon demo helpers
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/.local/bin:${PATH}"
export JAC_HOME="${JAC_HOME:-/tmp/jac_home}"
export HOME="${JAC_HOME}"
cd "$ROOT"

cmd="${1:-run}"
fixture="${2:-logistics}"

case "$cmd" in
  hello)
    SPLITHORIZON_MODE=hello jac run main.jac
    ;;
  run)
    SPLITHORIZON_FIXTURE="$fixture" jac run main.jac
    ;;
  ui)
    # serve.py needs real user path bits; use system python with JAC_HOME for subprocess
    JAC_HOME="$JAC_HOME" /usr/bin/env python3 serve.py
    ;;
  all)
    for fx in logistics fintech shelter; do
      echo "======== $fx ========"
      SPLITHORIZON_FIXTURE="$fx" jac run main.jac | rg -v '^note:' | rg '\[(blue|red|arbiter)\]|Recommended:|Branches:'
    done
    ;;
  *)
    echo "Usage: $0 {hello|run|ui|all} [fixture]"
    exit 1
    ;;
esac
