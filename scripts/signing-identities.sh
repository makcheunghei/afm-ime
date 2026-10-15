#!/bin/bash
# Shared certificate selection for package.sh and make_pkg.sh.
# Identity listings are supplied by `security find-identity`; tests pass fixtures.

afm_identity_fields() {
  local line="$1"
  AFM_ID_HASH="$(printf '%s\n' "$line" | sed -nE 's/^[[:space:]]*[0-9]+\)[[:space:]]+([[:xdigit:]]+)[[:space:]]+"([^\"]+)".*/\1/p')"
  [[ -n "$AFM_ID_HASH" ]] || return 1
  AFM_ID_NAME="$(printf '%s\n' "$line" | sed -nE 's/^[[:space:]]*[0-9]+\)[[:space:]]+[[:xdigit:]]+[[:space:]]+"([^\"]+)".*/\1/p')"
  if [[ "${AFM_CERTIFICATE_TEAMS+x}" == x ]]; then
    AFM_ID_TEAM="$(printf '%s\n' "$AFM_CERTIFICATE_TEAMS" | awk -v identity="$AFM_ID_HASH" '$1 == identity {print $2; exit}')"
  else
    # Fixture-only fallback; production callers always supply actual certificate subjects.
    AFM_ID_TEAM="$(printf '%s\n' "$AFM_ID_NAME" | sed -nE 's/.*\(([A-Z0-9]{10})\)$/\1/p')"
  fi
  return 0
}

afm_identity_kind() {
  case "$1" in
    "Developer ID Application:"*) printf '%s' developer-id ;;
    "Apple Development:"*) printf '%s' apple-development ;;
    "AFM-IME-Dev") printf '%s' legacy ;;
    "Developer ID Installer:"*) printf '%s' installer ;;
    *) printf '%s' other ;;
  esac
}

afm_fail() {
  printf '!! %s\n' "$1" >&2
  return 1
}

# Sets AFM_SELECTED_IDENTITY, AFM_SELECTED_TEAM and AFM_SELECTED_KIND.
afm_select_app_identity() {
  local listing="$1" identity_override="$2" team_override="$3"
  local line name hash team kind rank best_rank=99 teams=' '
  local chosen_name='' chosen_team='' chosen_kind=''

  if [[ -n "$identity_override" ]]; then
    while IFS= read -r line; do
      afm_identity_fields "$line" || continue
      name="$AFM_ID_NAME"; hash="$AFM_ID_HASH"; team="$AFM_ID_TEAM"
      if [[ "$identity_override" == "$name" || "$identity_override" == "$hash" ]]; then
        kind="$(afm_identity_kind "$name")"
        [[ "$kind" == developer-id || "$kind" == apple-development || "$kind" == legacy ]] ||
          { afm_fail "指定的 App 簽署身份不是支援的應用程式憑證：$identity_override"; return 1; }
        [[ "$kind" == legacy || -n "$team" ]] ||
          { afm_fail "無法讀取指定 App 憑證的實際 Team"; return 1; }
        [[ -z "$team_override" || "$team" == "$team_override" ]] ||
          { afm_fail "指定的 App 簽署身份 Team 與 AFM_SIGN_TEAM 不匹配"; return 1; }
        AFM_SELECTED_IDENTITY="$hash"; AFM_SELECTED_TEAM="$team"; AFM_SELECTED_KIND="$kind"
        return 0
      fi
    done <<< "$listing"
    afm_fail "找不到明確指定的 App 簽署身份：$identity_override"
    return 1
  fi

  while IFS= read -r line; do
    afm_identity_fields "$line" || continue
    name="$AFM_ID_NAME"; hash="$AFM_ID_HASH"; team="$AFM_ID_TEAM"
    kind="$(afm_identity_kind "$name")"
    case "$kind" in
      developer-id) rank=1 ;;
      apple-development) rank=2 ;;
      legacy) rank=3 ;;
      *) continue ;;
    esac
    [[ "$kind" == legacy || -n "$team" ]] ||
      { afm_fail "無法讀取 App 憑證的實際 Team"; return 1; }
    [[ -n "$team_override" && "$team" != "$team_override" ]] && continue
    if (( rank < best_rank )); then
      best_rank="$rank"; teams=' '; chosen_name=''; chosen_team=''; chosen_kind=''
    fi
    (( rank == best_rank )) || continue
    if [[ -n "$team" ]]; then
      case "$teams" in *" $team "*) ;; *) teams+="$team ";; esac
    else
      case "$teams" in *' <no-team> '*) ;; *) teams+='<no-team> ';; esac
    fi
    if [[ -z "$chosen_name" ]]; then
      chosen_name="$hash"; chosen_team="$team"; chosen_kind="$kind"
    fi
  done <<< "$listing"

  if (( best_rank == 99 )); then
    if [[ -n "$team_override" ]]; then
      afm_fail "AFM_SIGN_TEAM=$team_override 沒有可用的 App 簽署身份"
      return 1
    fi
    AFM_SELECTED_IDENTITY='-'; AFM_SELECTED_TEAM=''; AFM_SELECTED_KIND='adhoc'
    return 0
  fi
  local team_count
  team_count="$(printf '%s\n' "$teams" | awk '{print NF}')"
  if (( team_count > 1 )); then
    afm_fail "同優先級 App 憑證分屬多個 Team；請設定 AFM_SIGN_TEAM 或 AFM_SIGN_IDENTITY"
    return 1
  fi
  AFM_SELECTED_IDENTITY="$chosen_name"; AFM_SELECTED_TEAM="$chosen_team"; AFM_SELECTED_KIND="$chosen_kind"
}

# Sets AFM_SELECTED_INSTALLER. A missing matching certificate is a normal unsigned-pkg result.
afm_select_installer_identity() {
  local listing="$1" app_team="$2" identity_override="$3"
  local line name hash team kind
  AFM_SELECTED_INSTALLER=''
  if [[ -n "$identity_override" ]]; then
    while IFS= read -r line; do
      afm_identity_fields "$line" || continue
      name="$AFM_ID_NAME"; hash="$AFM_ID_HASH"; team="$AFM_ID_TEAM"
      if [[ "$identity_override" == "$name" || "$identity_override" == "$hash" ]]; then
        kind="$(afm_identity_kind "$name")"
        [[ "$kind" == installer ]] || { afm_fail "指定的 pkg 簽署身份必須是 Developer ID Installer：$identity_override"; return 1; }
        [[ -n "$app_team" && "$team" == "$app_team" ]] ||
          { afm_fail "指定的 Developer ID Installer Team 必須與 App Team 一致"; return 1; }
        AFM_SELECTED_INSTALLER="$hash"
        return 0
      fi
    done <<< "$listing"
    afm_fail "找不到明確指定的 pkg 簽署身份：$identity_override"
    return 1
  fi
  [[ -n "$app_team" ]] || return 0
  while IFS= read -r line; do
    afm_identity_fields "$line" || continue
    name="$AFM_ID_NAME"; hash="$AFM_ID_HASH"; team="$AFM_ID_TEAM"
    kind="$(afm_identity_kind "$name")"
    if [[ "$kind" == installer && "$team" == "$app_team" ]]; then
      AFM_SELECTED_INSTALLER="$hash"
      return 0
    fi
  done <<< "$listing"
}
