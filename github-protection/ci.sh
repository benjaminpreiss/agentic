#!/usr/bin/env bash
# Sourced by check.sh. Inventories CI observed on main's current tip.
# Interface: check_main_ci(repo, sha, effective_rules_json).
# This is a snapshot, not a complete inventory of PR-only workflows.
check_main_ci() {
  local repo="$1" sha="$2" rules="$3" required available names count page error='' covered unobserved kind
  required="$(jq -c '[.[] | select(.type=="required_status_checks") | .parameters.required_status_checks[]? | (.context // empty)] | unique' <<<"$rules")"
  available='[]'
  if [[ ! "$sha" =~ ^[0-9a-fA-F]{40}$ ]]; then error='main tip SHA unavailable'; fi
  if [[ -z "$error" ]]; then
    for kind in check-runs statuses; do
      page=1
      while :; do
        if ! api GET "$API/repos/$repo/commits/$sha/$kind?per_page=100&page=$page" "$token"; then
          error="$kind request failed"; break
        elif [[ "$STATUS" != 200 ]]; then
          error="$kind HTTP $STATUS"; break
        fi
        if [[ "$kind" == check-runs ]]; then
          if ! jq -e '.check_runs | type=="array"' >/dev/null <<<"$BODY"; then error='invalid check-runs response'; break; fi
          names="$(jq -c '[.check_runs[].name | select(type=="string")] | unique' <<<"$BODY")"
          count="$(jq '.check_runs | length' <<<"$BODY")"
        else
          if ! jq -e 'type=="array"' >/dev/null <<<"$BODY"; then error='invalid statuses response'; break; fi
          names="$(jq -c '[.[].context | select(type=="string")] | unique' <<<"$BODY")"
          count="$(jq 'length' <<<"$BODY")"
        fi
        available="$(jq -cn --argjson a "$available" --argjson b "$names" '$a + $b | unique')"
        ((count < 100)) && break
        ((page+=1)); if ((page > 50)); then error="$kind pagination limit exceeded"; break; fi
      done
      [[ -z "$error" ]] || break
    done
  fi
  if [[ -n "$error" ]]; then warn "main CI coverage unavailable ($error)"; return; fi
  covered="$(jq -cn --argjson a "$available" --argjson r "$required" '[$a[] | select(. as $x | $r | index($x) != null)] | length')"
  count="$(jq 'length' <<<"$available")"
  if ((count > 0 && covered == count)); then ok "main CI checks required/available: $covered/$count"; else warn "main CI checks required/available: $covered/$count"; fi
  unobserved="$(jq -rn --argjson a "$available" --argjson r "$required" '[$r[] | select(. as $x | $a | index($x) == null)] | join(", ")')"
  [[ -z "$unobserved" ]] || warn "main required CI contexts not observed on tip: $unobserved"
}
