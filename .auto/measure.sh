#!/bin/bash
set -euo pipefail

# Isolation bootstrap only. Replace this measurement and call init_experiment
# when selecting the next bounded macOS UI hypothesis.
printf 'METRIC macos_autoresearch_isolation_gaps=0\n'
printf 'METRIC shared_root_auto_dependencies=0\n'
