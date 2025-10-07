#!/usr/bin/env bash
set -euo pipefail
# always start at repo root
cd "$(git rev-parse --show-toplevel)"

matlab -batch "addpath(genpath('src')); addpath(genpath('tests')); results = runtests('tests', IncludeSubfolders=true); disp(results);"
