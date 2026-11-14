#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# Keep development terminal color settings out of LaunchServices and the GUI app.
exec /usr/bin/env -u NO_COLOR -u FORCE_COLOR -u CLICOLOR -u CLICOLOR_FORCE \
    -u TERM -u COLORTERM -u TERM_PROGRAM -u TERM_PROGRAM_VERSION \
    /usr/bin/open -g "${1:-build/觅见.app}"
