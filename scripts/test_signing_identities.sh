#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/signing-identities.sh

FIXTURE=$'  1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Apple Development: Fixture One (TEAMAAAAAA)"\n  2) BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB "Developer ID Application: Fixture One (TEAMAAAAAA)"\n  3) CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC "Developer ID Installer: Fixture One (TEAMAAAAAA)"\n  4) DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD "Apple Development: Fixture Two (TEAMBBBBBB)"\n  5) EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE "AFM-IME-Dev"'

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" != "$actual" ]]; then
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

afm_select_app_identity "$FIXTURE" '' ''
assert_eq BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB "$AFM_SELECTED_IDENTITY" 'Developer ID has priority'
assert_eq TEAMAAAAAA "$AFM_SELECTED_TEAM" 'selected app Team'
assert_eq developer-id "$AFM_SELECTED_KIND" 'selected app certificate kind'

afm_select_app_identity "$FIXTURE" '' TEAMBBBBBB
assert_eq DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD "$AFM_SELECTED_IDENTITY" 'Team override selects matching available priority'
assert_eq TEAMBBBBBB "$AFM_SELECTED_TEAM" 'Team override is retained'

MULTI_TEAM=$'  1) BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB "Developer ID Application: Fixture One (TEAMAAAAAA)"\n  2) FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF "Developer ID Application: Fixture Two (TEAMBBBBBB)"'
if afm_select_app_identity "$MULTI_TEAM" '' '' 2>/dev/null; then
  printf 'FAIL multiple Developer ID Teams must be an error\n' >&2; exit 1
fi
afm_select_app_identity "$MULTI_TEAM" '' TEAMBBBBBB
assert_eq FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF "$AFM_SELECTED_IDENTITY" 'Team resolves same-priority ambiguity'

if afm_select_app_identity "$FIXTURE" 'MISSING-IDENTITY' '' 2>/dev/null; then
  printf 'FAIL invalid explicit app identity must be an error\n' >&2; exit 1
fi
if afm_select_app_identity "$FIXTURE" BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB TEAMBBBBBB 2>/dev/null; then
  printf 'FAIL mismatched explicit app Team must be an error\n' >&2; exit 1
fi
afm_select_app_identity "$FIXTURE" 'AFM-IME-Dev' ''
assert_eq EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE "$AFM_SELECTED_IDENTITY" 'legacy identity remains explicitly selectable'

APPLE_ONLY=$'  1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Apple Development: Fixture One (TEAMAAAAAA)"\n  2) EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE "AFM-IME-Dev"'
afm_select_app_identity "$APPLE_ONLY" '' ''
assert_eq AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "$AFM_SELECTED_IDENTITY" 'Apple Development precedes legacy identity'
LEGACY_ONLY='  1) EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE "AFM-IME-Dev"'
afm_select_app_identity "$LEGACY_ONLY" '' ''
assert_eq EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE "$AFM_SELECTED_IDENTITY" 'legacy identity precedes ad-hoc'
afm_select_app_identity '' '' ''
assert_eq - "$AFM_SELECTED_IDENTITY" 'ad-hoc is the final fallback'
assert_eq adhoc "$AFM_SELECTED_KIND" 'ad-hoc signing kind'
if afm_select_app_identity "$APPLE_ONLY" '' TEAMBADBAD1 2>/dev/null; then
  printf 'FAIL unavailable explicit Team must be an error\n' >&2; exit 1
fi

afm_select_installer_identity "$FIXTURE" TEAMAAAAAA ''
assert_eq CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC "$AFM_SELECTED_INSTALLER" 'matching Developer ID Installer selected'
afm_select_installer_identity "$FIXTURE" TEAMBBBBBB ''
assert_eq '' "$AFM_SELECTED_INSTALLER" 'no matching installer is a clean unsigned result'
if afm_select_installer_identity "$FIXTURE" TEAMAAAAAA BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB 2>/dev/null; then
  printf 'FAIL app signing certificate cannot sign pkg\n' >&2; exit 1
fi
if afm_select_installer_identity "$FIXTURE" TEAMBBBBBB CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC 2>/dev/null; then
  printf 'FAIL mismatched installer Team must be an error\n' >&2; exit 1
fi

# The subject OU, rather than Apple Development's name suffix, defines the actual Team.
AFM_CERTIFICATE_TEAMS=$'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA TEAMCCCCCC\nEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE '
afm_select_app_identity "$APPLE_ONLY" '' TEAMCCCCCC
assert_eq TEAMCCCCCC "$AFM_SELECTED_TEAM" 'actual certificate Team overrides the display-name suffix'
if afm_select_app_identity "$APPLE_ONLY" '' TEAMAAAAAA 2>/dev/null; then
  printf 'FAIL display-name suffix must not be treated as actual Team\n' >&2; exit 1
fi
AFM_CERTIFICATE_TEAMS=''
if afm_select_app_identity "$APPLE_ONLY" '' '' 2>/dev/null; then
  printf 'FAIL missing actual Team metadata must not select an Apple identity\n' >&2; exit 1
fi
unset AFM_CERTIFICATE_TEAMS

printf 'Signing identity selector tests passed.\n'
