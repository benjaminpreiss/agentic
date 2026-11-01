#!/usr/bin/env bash
# Read-only GitHub App audit across every repository in one installation.
# Default: prove default-branch ruleset coverage + sample work-branch rules.
# --all-branches: inspect every existing branch's effective rules (slower).
set -euo pipefail
umask 077
[[ $# == 0 || ($# == 1 && $1 == --all-branches) ]] || { echo 'Usage: bash github-protection/check.sh [--all-branches]' >&2; exit 2; }
all_branches=false
[[ $# == 0 ]] || all_branches=true
POLICY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS="${AGENTIC_GITHUB_SECRETS_DIR:-$POLICY_DIR/../secrets/github-app}"
for cmd in curl jq openssl date base64; do command -v "$cmd" >/dev/null || { echo "ERROR: missing $cmd" >&2; exit 2; }; done
# Sourced modules define functions only. They require the main script's
# api response globals (BODY/STATUS) and reporting functions (ok/warn/fail).
source "$POLICY_DIR/github-api.sh"
source "$POLICY_DIR/ci.sh"

failures=0; warnings=0; passed=0
ok()   { printf '  ✅ %s\n' "$1"; ((passed+=1)); }
warn() { printf '  ⚠️  %s\n' "$1"; ((warnings+=1)); }
fail() { printf '  ❌ %s\n' "$1"; ((failures+=1)); }

report() {
  local label="$1" results="$2" status message
  if ! jq -e 'type == "array" and length > 0 and all(.[]; (.status == "ok" or .status == "warn" or .status == "fail") and (.message | type == "string"))' >/dev/null <<<"$results"; then
    fail "$label: policy evaluator returned invalid results"; return 1
  fi
  while IFS=$'\t' read -r status message; do
    case "$status" in
      ok) ok "$label: $message" ;;
      warn) warn "$label: $message" ;;
      fail) fail "$label: $message" ;;
    esac
  done < <(jq -r '.[] | [.status, .message] | @tsv' <<<"$results")
}

check_effective() {
  local repo="$1" branch="$2" encoded results
  encoded="$(jq -rn --arg v "$branch" '$v|@uri')"
  if ! api GET "$API/repos/$repo/rules/branches/$encoded?per_page=100" "$token"; then
    fail "$branch: effective rules API transport error"; return 1
  elif [[ "$STATUS" != 200 ]]; then
    fail "$branch: effective rules HTTP $STATUS"; return 1
  elif ! jq -e 'type=="array"' >/dev/null <<<"$BODY"; then
    fail "$branch: invalid effective rules response"; return 1
  fi
  EFFECTIVE_RULES="$BODY"
  if ! results="$(jq -c --arg branch "$branch" --arg default_branch "$default_branch" -f "$POLICY_DIR/policy.jq" <<<"$EFFECTIVE_RULES")"; then
    fail "$branch: policy evaluation failed"; return 1
  fi
  report "$branch" "$results"
}

audit_repo() {
  local repo="$1" results default_branch default_sha encoded_default branch work_sample=''
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo 'ERROR: invalid repository identifier' >&2; exit 2; }
  printf '\n📦 %s\n' "$repo"
  if ! api GET "$API/repos/$repo" "$token"; then
    fail 'repository metadata: API transport error'; return
  elif [[ "$STATUS" != 200 ]]; then
    fail "repository metadata: HTTP $STATUS"; return
  fi
  default_branch="$(jq -r '.default_branch // empty' <<<"$BODY")"
  if [[ -z "$default_branch" ]]; then fail 'repository metadata: missing default branch'; return; fi
  encoded_default="$(jq -rn --arg v "$default_branch" '$v|@uri')"
  if load_rulesets "$repo"; then
    if results="$(jq -c --argjson app_id "$APP_ID" -f "$POLICY_DIR/rulesets.jq" <<<"$details")"; then
      report 'rulesets' "$results" || true
    else fail 'ruleset policy evaluation failed'; fi
  fi

  # The repository's actual default branch supplies CI requirements.
  if ! api GET "$API/repos/$repo/branches/$encoded_default" "$token"; then
    fail "$default_branch: branch API transport error"
  elif [[ "$STATUS" != 200 ]]; then
    fail "$default_branch: branch HTTP $STATUS"
  else
    default_sha="$(jq -r '.commit.sha // empty' <<<"$BODY")"
    if check_effective "$repo" "$default_branch"; then check_main_ci "$repo" "$default_sha" "$EFFECTIVE_RULES"; fi
  fi

  if load_branches "$repo" "$all_branches"; then
    if [[ "$all_branches" == true ]]; then
      for branch in "${branches[@]}"; do [[ "$branch" == "$default_branch" ]] || check_effective "$repo" "$branch" || true; done
    else
      for branch in "${branches[@]}"; do
        if [[ "$branch" != "$default_branch" && -z "$work_sample" ]]; then work_sample="$branch"; fi
      done
      if [[ -n "$work_sample" ]]; then check_effective "$repo" "$work_sample" || true; else warn 'no work branch sampled'; fi
    fi
  fi
  warn 'Effective rules do not prove reviewer identity or actual merge authorization; test with App credentials and use a trusted merge gate'
}

authenticate
list_repos
printf 'GitHub App installation %s: %s repositories\nRead-only %s audit; no GitHub settings are changed.\n' "$INSTALL_ID" "${#repos[@]}" "$(if $all_branches; then echo full-branch; else echo ruleset-focused; fi)"
for repo in "${repos[@]}"; do audit_repo "$repo"; done
unset token
printf '\nSummary: ✅ %s passed  ⚠️ %s warnings  ❌ %s failures (%s repositories)\n' "$passed" "$warnings" "$failures" "${#repos[@]}"
((failures == 0))
