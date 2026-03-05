#!/usr/bin/env bash
set -euo pipefail

USERNAME="tbroadley"
USER_EMAIL="thomas@metr.org"
TIMEZONE="America/Los_Angeles"
TARGET_DATE=""

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--date YYYY-MM-DD] [--username USER] [--email EMAIL] [--timezone TZ]

Examples:
  $(basename "$0")
  $(basename "$0") --date 2026-03-04
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --date)
      TARGET_DATE="$2"
      shift 2
      ;;
    --username)
      USERNAME="$2"
      shift 2
      ;;
    --email)
      USER_EMAIL="$2"
      shift 2
      ;;
    --timezone)
      TIMEZONE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$TARGET_DATE" ]]; then
  TARGET_DATE=$(TZ="$TIMEZONE" date +%Y-%m-%d)
fi

if START_UTC=$(TZ="$TIMEZONE" date -u -j -f "%Y-%m-%d %H:%M:%S" "$TARGET_DATE 00:00:00" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null); then
  END_UTC=$(TZ="$TIMEZONE" date -u -j -v+1d -f "%Y-%m-%d %H:%M:%S" "$TARGET_DATE 00:00:00" +"%Y-%m-%dT%H:%M:%SZ")
else
  START_UTC=$(TZ="$TIMEZONE" date -u -d "$TARGET_DATE 00:00:00" +"%Y-%m-%dT%H:%M:%SZ")
  END_UTC=$(TZ="$TIMEZONE" date -u -d "$TARGET_DATE 00:00:00 +1 day" +"%Y-%m-%dT%H:%M:%SZ")
fi

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

pr_rows_file="$tmp_dir/pr_rows.tsv"
pr_today_shas="$tmp_dir/pr_today_shas.txt"
all_rows="$tmp_dir/all_rows.tsv"
nonpr_rows="$tmp_dir/nonpr_rows.tsv"

: > "$pr_rows_file"
: > "$pr_today_shas"
: > "$all_rows"
: > "$nonpr_rows"

prs_json=$(gh search prs --author="$USERNAME" --updated=">=$TARGET_DATE" --json number,title,repository,createdAt,updatedAt,url --limit 100)

printf '%s' "$prs_json" | jq -r '.[] | @base64' | while IFS= read -r pr_b64; do
  pr=$(printf '%s' "$pr_b64" | base64 --decode)
  repo=$(printf '%s' "$pr" | jq -r '.repository.nameWithOwner')
  number=$(printf '%s' "$pr" | jq -r '.number')
  title=$(printf '%s' "$pr" | jq -r '.title | gsub("\\t"; " ") | gsub("\\|"; "/")')
  url=$(printf '%s' "$pr" | jq -r '.url')
  created=$(printf '%s' "$pr" | jq -r '.createdAt')

  created_today=false
  if [[ "$created" > "$START_UTC" && "$created" < "$END_UTC" ]] || [[ "$created" == "$START_UTC" ]]; then
    created_today=true
  fi

  pr_commits=$(gh api "repos/$repo/pulls/$number/commits?per_page=250" --paginate)
  today_shas=$(printf '%s' "$pr_commits" | jq -r --arg s "$START_UTC" --arg e "$END_UTC" '.[] | select(.commit.author.date >= $s and .commit.author.date < $e) | .sha')
  if [[ -n "$today_shas" ]]; then
    printf '%s\n' "$today_shas" >> "$pr_today_shas"
  fi

  has_today=false
  if [[ -n "$today_shas" ]]; then
    has_today=true
  fi

  if [[ "$created_today" == "false" && "$has_today" == "false" ]]; then
    continue
  fi

  plus=0
  minus=0
  basis="today_commits"

  if [[ "$created_today" == "true" ]]; then
    basis="total_pr"
    shas=$(printf '%s' "$pr_commits" | jq -r '.[].sha')
  else
    shas="$today_shas"
  fi

  while IFS= read -r sha; do
    [[ -z "$sha" ]] && continue
    stats=$(gh api "repos/$repo/commits/$sha" --jq '.stats')
    a=$(printf '%s' "$stats" | jq -r '.additions')
    d=$(printf '%s' "$stats" | jq -r '.deletions')
    plus=$((plus + a))
    minus=$((minus + d))
  done < <(printf '%s\n' "$shas")

  printf '%s\t#%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "$number" "$title" "$url" "$created_today" "$plus" "$minus" "$basis" >> "$pr_rows_file"
done

sort -u "$pr_today_shas" -o "$pr_today_shas"

commit_search=$(gh search commits --author="$USERNAME" --author-date=">=$TARGET_DATE" --json repository,sha,commit,url --limit 300)
printf '%s' "$commit_search" | jq -r --arg s "$START_UTC" --arg e "$END_UTC" '.[] | select(.commit.author.date >= $s and .commit.author.date < $e) | @base64' | while IFS= read -r c_b64; do
  c=$(printf '%s' "$c_b64" | base64 --decode)
  repo=$(printf '%s' "$c" | jq -r '.repository.fullName')
  sha=$(printf '%s' "$c" | jq -r '.sha')
  msg=$(printf '%s' "$c" | jq -r '.commit.message | split("\n")[0] | gsub("\t"; " ") | gsub("\\|"; "/")')
  printf '%s\t%s\t%s\n' "$repo" "$sha" "$msg" >> "$all_rows"
done
sort -u "$all_rows" -o "$all_rows"

cut -f1 "$all_rows" | sort -u | while IFS= read -r repo; do
  [[ -z "$repo" ]] && continue

  default_branch=$(gh api "repos/$repo" --jq '.default_branch')
  def_shas_file="$tmp_dir/def_$(echo "$repo" | tr '/' '_').txt"
  gh api -X GET "repos/$repo/commits" -f "sha=$default_branch" -f "since=$START_UTC" -f "until=$END_UTC" -f "per_page=100" --paginate --jq '.[].sha' | sort -u > "$def_shas_file"

  awk -F '\t' -v r="$repo" '$1==r {print $0}' "$all_rows" | while IFS=$'\t' read -r _ sha msg; do
    if grep -q "^$sha$" "$pr_today_shas"; then
      continue
    fi

    pulls_len=$(gh api "repos/$repo/commits/$sha/pulls" --jq 'length')
    if [[ "$pulls_len" != "0" ]]; then
      continue
    fi

    commit_json=$(gh api "repos/$repo/commits/$sha")
    author_login=$(printf '%s' "$commit_json" | jq -r '.author.login // empty')
    committer_login=$(printf '%s' "$commit_json" | jq -r '.committer.login // empty')
    author_email=$(printf '%s' "$commit_json" | jq -r '.commit.author.email // empty')
    committer_email=$(printf '%s' "$commit_json" | jq -r '.commit.committer.email // empty')

    if [[ "$author_login" != "$USERNAME" && "$committer_login" != "$USERNAME" && "$author_email" != "$USER_EMAIL" && "$committer_email" != "$USER_EMAIL" ]]; then
      continue
    fi

    a=$(printf '%s' "$commit_json" | jq -r '.stats.additions')
    d=$(printf '%s' "$commit_json" | jq -r '.stats.deletions')

    bucket="branch_only"
    if grep -q "^$sha$" "$def_shas_file"; then
      bucket="default"
    fi

    branch_hint=$(gh api "repos/$repo/commits/$sha/branches-where-head" --jq '.[].name' 2>/dev/null | paste -sd ',' -)
    if [[ -z "$branch_hint" ]]; then
      branch_hint="unknown"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "$bucket" "$branch_hint" "$sha" "$a" "$d" "$msg" >> "$nonpr_rows"
  done
done

sort -u "$pr_rows_file" -o "$pr_rows_file"
sort -u "$nonpr_rows" -o "$nonpr_rows"

pr_total_add=$(awk -F '\t' '{a += $6} END {print a + 0}' "$pr_rows_file")
pr_total_del=$(awk -F '\t' '{d += $7} END {print d + 0}' "$pr_rows_file")
pr_count=$(wc -l < "$pr_rows_file" | tr -d ' ')

default_total_add=$(awk -F '\t' '$2=="default" {a += $5} END {print a + 0}' "$nonpr_rows")
default_total_del=$(awk -F '\t' '$2=="default" {d += $6} END {print d + 0}' "$nonpr_rows")
default_commit_count=$(awk -F '\t' '$2=="default" {c++} END {print c + 0}' "$nonpr_rows")

branch_total_add=$(awk -F '\t' '$2=="branch_only" {a += $5} END {print a + 0}' "$nonpr_rows")
branch_total_del=$(awk -F '\t' '$2=="branch_only" {d += $6} END {print d + 0}' "$nonpr_rows")
branch_commit_count=$(awk -F '\t' '$2=="branch_only" {c++} END {print c + 0}' "$nonpr_rows")

grand_add=$((pr_total_add + default_total_add + branch_total_add))
grand_del=$((pr_total_del + default_total_del + branch_total_del))

echo "Daily activity for $TARGET_DATE ($TIMEZONE)"
echo "Window: $START_UTC to $END_UTC"
echo

echo "Pull Requests"
echo "| PR | Repository | Title | +/- | Notes |"
echo "|---|---|---|---:|---|"
if [[ -s "$pr_rows_file" ]]; then
  while IFS=$'\t' read -r repo pr title url _ add del basis; do
    if [[ "$basis" == "total_pr" ]]; then
      note="total PR (created today)"
    else
      note="today's commits only"
    fi
    echo "| [$pr]($url) | \`$repo\` | $title | +$add/-$del | $note |"
  done < "$pr_rows_file"
else
  echo "| - | - | - | - | - |"
fi

echo

echo "Direct Commits to Default Branch (non-PR)"
echo "| Repo | Commits | +/- |"
echo "|---|---:|---:|"
if awk -F '\t' '$2=="default" {found=1} END {exit found ? 0 : 1}' "$nonpr_rows"; then
  awk -F '\t' '$2=="default" {c[$1]++; a[$1]+=$5; d[$1]+=$6} END {for (r in c) printf("| `%s` | %d | +%d/-%d |\n", r, c[r], a[r], d[r])}' "$nonpr_rows" | sort
else
  echo "| - | 0 | +0/-0 |"
fi

echo

echo "Branch-Only Commits (non-PR)"
echo "| Repo | Branches | Commits | +/- |"
echo "|---|---|---:|---:|"
if awk -F '\t' '$2=="branch_only" {found=1} END {exit found ? 0 : 1}' "$nonpr_rows"; then
  awk -F '\t' '
    $2=="branch_only" {
      c[$1]++
      a[$1]+=$5
      d[$1]+=$6
      key=$1
      if (branches[key] == "") {
        branches[key]=$3
      } else if (index("," branches[key] ",", "," $3 ",") == 0) {
        branches[key]=branches[key] "," $3
      }
    }
    END {
      for (r in c) printf("| `%s` | %s | %d | +%d/-%d |\n", r, branches[r], c[r], a[r], d[r])
    }
  ' "$nonpr_rows" | sort
else
  echo "| - | - | 0 | +0/-0 |"
fi

echo

echo "Totals"
echo "- Total PRs with activity: $pr_count"
echo "- Total non-PR default-branch commits: $default_commit_count"
echo "- Total non-PR branch-only commits: $branch_commit_count"
echo "- Total lines changed: +$grand_add/-$grand_del"
