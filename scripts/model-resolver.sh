#!/usr/bin/env bash
# shellcheck shell=bash
# model-resolver.sh — sourced (not run) by agy-delegate.sh and doctor.sh.
#
# The `flash` and `flash-lo` tiers default to the NEWEST Gemini Flash (High / Low) that
# `agy models` lists, so a new Flash release becomes the default without a plugin update.
# Derived from upstream 0.20.1's model-resolver.sh, with one change forced by measurement:
# `agy models` took 9.4 s here (it waits on agy's MCP servers), so a delegation must never
# wait for it. The wrapper only READS a cache; when the cache is missing or stale it starts
# a detached refresh and uses the cached value (or the pinned fallback) for this call.
# doctor already runs `agy models`, so it refreshes the cache for free.
#
# Exact settings still win: tier_flash / tier_flash_lo, default_model and --model are
# honoured before anything here is consulted. The `pro` tier is not resolved.

# Used when there is no cache yet, or `agy models` lists no Flash. Pinned to the newest
# known-good Flash so a fresh install, a dry run and an offline machine stay deterministic.
FLASH_HIGH_FALLBACK="Gemini 3.8 Flash (High)"
FLASH_LOW_FALLBACK="Gemini 3.8 Flash (Low)"

FLASH_CACHE="${AGY_FLASH_CACHE:-${TMPDIR:-/tmp}/agy-delegate-flash.cache}"
FLASH_CACHE_TTL_MIN=720        # cached value is trusted for 12 h, then refreshed in the background
FLASH_REFRESH_LOCK_MIN=5       # at most one refresh attempt per 5 min, so a failing agy is not hammered
FLASH_REFRESH_TIMEOUT=60       # seconds; agy models measured 9.4 s

# True if dotted version $1 is numerically greater than $2 (3.10 > 3.9).
version_gt() {
  local left="$1" right="$2" i max lv rv
  local IFS=.
  local left_parts=($left) right_parts=($right)
  max=${#left_parts[@]}
  [ "${#right_parts[@]}" -gt "$max" ] && max=${#right_parts[@]}
  for ((i = 0; i < max; i++)); do
    lv=${left_parts[i]:-0}; rv=${right_parts[i]:-0}
    lv=$((10#$lv)); rv=$((10#$rv))
    [ "$lv" -gt "$rv" ] && return 0
    [ "$lv" -lt "$rv" ] && return 1
  done
  return 1
}

# Read `agy models` output on stdin; print the newest `Gemini <ver> Flash (<effort>)` for
# effort $1 (High | Low), or nothing. Takes both the slug+display form
# (`gemini-3.8-flash-high<TAB>Gemini 3.8 Flash (High)`) and the older display-only form,
# whatever the order, and ignores any other line (agy prints a "Fetching..." header).
latest_flash_from_models() {
  local effort="$1" suffix line slug version best=""
  suffix="$(printf '%s' "$effort" | tr '[:upper:]' '[:lower:]')"
  local display_re="Gemini[[:space:]]+([0-9]+([.][0-9]+)*)[[:space:]]+Flash[[:space:]]*[(]${effort}[)]"
  while IFS= read -r line; do
    slug="${line%%[[:space:]]*}"
    case "$slug" in
      gemini-*-flash-"$suffix")
        version="${slug#gemini-}"; version="${version%-flash-"$suffix"}"
        ;;
      *)
        if [[ "$line" =~ $display_re ]]; then version="${BASH_REMATCH[1]}"; else continue; fi
        ;;
    esac
    case "$version" in ""|.*|*.|*..*|*[!0-9.]*) continue ;; esac
    if [ -z "$best" ] || version_gt "$version" "$best"; then best="$version"; fi
  done
  [ -n "$best" ] && printf 'Gemini %s Flash (%s)\n' "$best" "$effort"
  return 0
}

# Display name of the cached Flash for effort $1 (High | Low), else the pinned fallback.
# Never runs agy. The cache is a shared temp file, so a value is used only if it has
# exactly the shape we write; anything else is ignored.
flash_for_effort() {
  local effort="$1" v="" re
  re="^Gemini [0-9]+([.][0-9]+)* Flash \\(${effort}\\)$"
  [ -r "$FLASH_CACHE" ] && v="$(sed -n "s/^${effort}=//p" "$FLASH_CACHE" 2>/dev/null | head -1)"
  v="${v%$'\r'}"
  if [[ "$v" =~ $re ]]; then printf '%s\n' "$v"; return 0; fi
  case "$effort" in High) printf '%s\n' "$FLASH_HIGH_FALLBACK" ;; *) printf '%s\n' "$FLASH_LOW_FALLBACK" ;; esac
}

# Rewrite the cache from `agy models` output on stdin. Returns 1 (cache untouched) when it
# lists no High Flash, so a bad answer cannot wipe a good cache.
flash_cache_write() {
  local models hi lo tmp
  models="$(cat)"
  hi="$(latest_flash_from_models High <<<"$models")"
  lo="$(latest_flash_from_models Low <<<"$models")"
  [ -n "$hi" ] || return 1
  tmp="$FLASH_CACHE.$$"
  printf 'High=%s\nLow=%s\n' "$hi" "${lo:-$FLASH_LOW_FALLBACK}" > "$tmp" 2>/dev/null || return 1
  mv -f "$tmp" "$FLASH_CACHE" 2>/dev/null || { rm -f "$tmp"; return 1; }
}

# Run `agy models` (bounded) and refresh the cache. Synchronous; callers detach it.
# agy's stdout goes to a file, not a pipe: its MCP children inherit the descriptor and a
# pipe they hold open would stall the capture forever (issue #37).
flash_cache_refresh() {
  command -v agy >/dev/null 2>&1 || return 1
  local f guard=""
  f="$(mktemp "${TMPDIR:-/tmp}/agy-models.XXXXXX")" || return 1
  if   command -v timeout  >/dev/null 2>&1; then guard=timeout
  elif command -v gtimeout >/dev/null 2>&1; then guard=gtimeout
  fi
  if [ -n "$guard" ]; then
    "$guard" --kill-after=5 "$FLASH_REFRESH_TIMEOUT" agy models >"$f" 2>/dev/null </dev/null
  else
    agy models >"$f" 2>/dev/null </dev/null
  fi
  flash_cache_write < "$f"; local rc=$?
  rm -f "$f"
  return "$rc"
}

# Start a detached refresh when the cache is missing or older than the TTL, at most once per
# lock window. Returns at once; the call that triggers it keeps the cached/fallback model.
flash_cache_refresh_async() {
  if [ -e "$FLASH_CACHE" ] && [ -n "$(find "$FLASH_CACHE" -mmin "-$FLASH_CACHE_TTL_MIN" 2>/dev/null)" ]; then return 0; fi
  local lock="$FLASH_CACHE.lock"
  if [ -e "$lock" ] && [ -n "$(find "$lock" -mmin "-$FLASH_REFRESH_LOCK_MIN" 2>/dev/null)" ]; then return 0; fi
  : > "$lock" 2>/dev/null || return 0
  ( flash_cache_refresh ) >/dev/null 2>&1 </dev/null &
  disown 2>/dev/null || true
  return 0
}
