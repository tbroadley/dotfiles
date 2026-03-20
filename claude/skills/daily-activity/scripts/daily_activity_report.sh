#!/usr/bin/env bash
set -euo pipefail

USERNAME="tbroadley"
USER_EMAIL="thomas@metr.org"
TIMEZONE="America/Los_Angeles"
TARGET_DATE=""
MAX_PARALLEL=6
JOB_PIDS=()

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

if START_EPOCH=$(TZ="$TIMEZONE" date -j -f "%Y-%m-%d %H:%M:%S" "$TARGET_DATE 00:00:00" +%s 2>/dev/null); then
  END_EPOCH=$(TZ="$TIMEZONE" date -j -v+1d -f "%Y-%m-%d %H:%M:%S" "$TARGET_DATE 00:00:00" +%s)
  START_UTC=$(date -u -r "$START_EPOCH" +"%Y-%m-%dT%H:%M:%SZ")
  END_UTC=$(date -u -r "$END_EPOCH" +"%Y-%m-%dT%H:%M:%SZ")
else
  START_EPOCH=$(TZ="$TIMEZONE" date -d "$TARGET_DATE 00:00:00" +%s)
  NEXT_DATE=$(TZ="$TIMEZONE" date -d "$TARGET_DATE +1 day" +%Y-%m-%d)
  END_EPOCH=$(TZ="$TIMEZONE" date -d "$NEXT_DATE 00:00:00" +%s)
  START_UTC=$(date -u -d "@$START_EPOCH" +"%Y-%m-%dT%H:%M:%SZ")
  END_UTC=$(date -u -d "@$END_EPOCH" +"%Y-%m-%dT%H:%M:%SZ")
fi

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

pr_rows_file="$tmp_dir/pr_rows.tsv"
pr_today_shas="$tmp_dir/pr_today_shas.txt"
repos_file="$tmp_dir/repos.txt"
candidate_rows="$tmp_dir/candidate_rows.tsv"
nonpr_rows="$tmp_dir/nonpr_rows.tsv"
skipped_repos="$tmp_dir/skipped_repos.txt"
push_refs="$tmp_dir/push_refs.tsv"
commit_details_file="$tmp_dir/commit_details.tsv"
repo_default_branches="$tmp_dir/repo_default_branches.tsv"
pivot_stage_rows="$tmp_dir/pivot_stage_rows.tsv"

: > "$pr_rows_file"
: > "$pr_today_shas"
: > "$repos_file"
: > "$candidate_rows"
: > "$nonpr_rows"
: > "$skipped_repos"
: > "$push_refs"
: > "$commit_details_file"
: > "$repo_default_branches"
: > "$pivot_stage_rows"

repo_slug() {
  printf '%s' "$1" | tr '/' '_'
}

build_commit_details_query() {
  local repo="$1"
  shift

  local owner="${repo%%/*}"
  local name="${repo#*/}"
  local query="query { repository(owner: \"$owner\", name: \"$name\") {"
  local idx=0
  local sha
  for sha in "$@"; do
    query+=" c$idx: object(expression: \"$sha\") { ... on Commit { oid additions deletions associatedPullRequests(first: 10) { totalCount } author { email user { login } } committer { email user { login } } } }"
    idx=$((idx + 1))
  done
  query+=" } }"

  printf '%s' "$query"
}

emit_commit_details_rows() {
  local repo="$1"

  jq -r --arg repo "$repo" '
    .data.repository
    | to_entries[]
    | select(.value != null)
    | [
        $repo,
        .value.oid,
        .value.additions,
        .value.deletions,
        .value.associatedPullRequests.totalCount,
        (.value.author.user.login // ""),
        (.value.committer.user.login // ""),
        (.value.author.email // ""),
        (.value.committer.email // "")
      ]
    | @tsv
  '
}

fetch_commit_details_for_repo() {
  local repo="$1"
  local shas_file="$2"

  local -a batch_shas=()
  local sha
  while IFS= read -r sha; do
    [[ -z "$sha" ]] && continue
    batch_shas+=("$sha")
    if [[ ${#batch_shas[@]} -eq 20 ]]; then
      gh api graphql -f query="$(build_commit_details_query "$repo" "${batch_shas[@]}")" | emit_commit_details_rows "$repo"
      batch_shas=()
    fi
  done < "$shas_file"

  if [[ ${#batch_shas[@]} -gt 0 ]]; then
    gh api graphql -f query="$(build_commit_details_query "$repo" "${batch_shas[@]}")" | emit_commit_details_rows "$repo"
  fi
}

sum_pivot_stage_pr_lines() {
  local repo="$1"
  local number="$2"

  gh api "repos/$repo/pulls/$number/files?per_page=100" --paginate --slurp | jq -r '
    [.[ ][] | select(.filename | startswith(".pivot/stages/"))]
    | [
        (map(.additions) | add // 0),
        (map(.deletions) | add // 0)
      ]
    | @tsv
  '
}

sum_pivot_stage_commit_lines() {
  local repo="$1"
  local shas_file="$2"

  local plus=0
  local minus=0
  local sha
  local file_totals
  local a
  local d
  while IFS= read -r sha; do
    [[ -z "$sha" ]] && continue
    file_totals=$(gh api "repos/$repo/commits/$sha" | jq -r '
      [(.files // [])[] | select(.filename | startswith(".pivot/stages/"))]
      | [
          (map(.additions) | add // 0),
          (map(.deletions) | add // 0)
        ]
      | @tsv
    ')
    a=$(printf '%s' "$file_totals" | cut -f1)
    d=$(printf '%s' "$file_totals" | cut -f2)
    plus=$((plus + a))
    minus=$((minus + d))
  done < "$shas_file"

  printf '%s\t%s\n' "$plus" "$minus"
}

fetch_branch_commits_json() {
  local repo="$1"
  local branch="$2"

  gh api -X GET "repos/$repo/commits" \
    -f "sha=$branch" \
    -f "since=$START_UTC" \
    -f "until=$END_UTC" \
    -f "per_page=100" \
    --paginate 2>/dev/null
}

wait_for_available_slot() {
  if [[ ${#JOB_PIDS[@]} -lt $MAX_PARALLEL ]]; then
    return
  fi

  wait "${JOB_PIDS[0]}"
  JOB_PIDS=("${JOB_PIDS[@]:1}")
}

register_job_pid() {
  JOB_PIDS+=("$1")
}

wait_for_all_jobs() {
  local job_pid
  for job_pid in "${JOB_PIDS[@]}"; do
    wait "$job_pid"
  done
  JOB_PIDS=()
}

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
    while IFS= read -r sha; do
      [[ -z "$sha" ]] && continue
      printf '%s\t%s\n' "$repo" "$sha" >> "$pr_today_shas"
    done < <(printf '%s\n' "$today_shas")
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
    pr_totals=$(gh api "repos/$repo/pulls/$number" --jq '{additions: .additions, deletions: .deletions}')
    plus=$(printf '%s' "$pr_totals" | jq -r '.additions')
    minus=$(printf '%s' "$pr_totals" | jq -r '.deletions')
    pivot_stage_totals=$(sum_pivot_stage_pr_lines "$repo" "$number")
  else
    repo_slug_value=$(repo_slug "$repo")
    pr_stats_shas="$tmp_dir/pr_${number}_${repo_slug_value}.txt"
    pr_stats_rows="$tmp_dir/pr_${number}_${repo_slug_value}.tsv"
    printf '%s\n' "$today_shas" | sort -u > "$pr_stats_shas"
    fetch_commit_details_for_repo "$repo" "$pr_stats_shas" > "$pr_stats_rows"
    plus=$(awk -F '\t' '{a += $3} END {print a + 0}' "$pr_stats_rows")
    minus=$(awk -F '\t' '{d += $4} END {print d + 0}' "$pr_stats_rows")
    pivot_stage_totals=$(sum_pivot_stage_commit_lines "$repo" "$pr_stats_shas")
  fi

  pivot_stage_add=$(printf '%s' "$pivot_stage_totals" | cut -f1)
  pivot_stage_del=$(printf '%s' "$pivot_stage_totals" | cut -f2)
  plus=$((plus - pivot_stage_add))
  minus=$((minus - pivot_stage_del))
  printf '%s\tpr\t%s\t%s\n' "$repo" "$pivot_stage_add" "$pivot_stage_del" >> "$pivot_stage_rows"

  printf '%s\n' "$repo" >> "$repos_file"
  printf '%s\t#%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "$number" "$title" "$url" "$created_today" "$plus" "$minus" "$basis" >> "$pr_rows_file"
done

sort -u "$pr_today_shas" -o "$pr_today_shas"

commit_search=$(gh search commits --author="$USERNAME" --author-date=">=$TARGET_DATE" --json repository,sha,commit,url --limit 300)
printf '%s' "$commit_search" | jq -r --arg s "$START_UTC" --arg e "$END_UTC" '.[] | select(.commit.author.date >= $s and .commit.author.date < $e) | .repository.fullName' >> "$repos_file"
gh api "users/$USERNAME/events?per_page=100" --paginate | jq -r --arg s "$START_UTC" --arg e "$END_UTC" '.[] | select(.type == "PushEvent" and .created_at >= $s and .created_at < $e) | [.repo.name, (.payload.ref // "")] | @tsv' >> "$push_refs"
cut -f1 "$push_refs" >> "$repos_file"
sort -u "$repos_file" -o "$repos_file"
sort -u "$push_refs" -o "$push_refs"

repo_scan_dir="$tmp_dir/repo_scan"
mkdir -p "$repo_scan_dir"

while IFS= read -r repo; do
  [[ -z "$repo" ]] && continue
  wait_for_available_slot

  {
    repo_slug_value=$(repo_slug "$repo")
    repo_candidate_rows="$repo_scan_dir/${repo_slug_value}.candidate.tsv"
    repo_default_branch_file="$repo_scan_dir/${repo_slug_value}.default_branch.tsv"
    repo_skipped_file="$repo_scan_dir/${repo_slug_value}.skipped.txt"
    branches_file="$repo_scan_dir/${repo_slug_value}.branches.txt"

    : > "$repo_candidate_rows"
    : > "$repo_default_branch_file"
    : > "$repo_skipped_file"

    if ! default_branch=$(gh api "repos/$repo" --jq '.default_branch' 2>/dev/null); then
      printf '%s\n' "$repo" > "$repo_skipped_file"
      exit 0
    fi
    printf '%s\t%s\n' "$repo" "$default_branch" > "$repo_default_branch_file"

    awk -F '\t' -v r="$repo" '$1==r {sub(/^refs\/heads\//, "", $2); if ($2 != "") print $2}' "$push_refs" > "$branches_file"
    printf '%s\n' "$default_branch" >> "$branches_file"
    sort -u "$branches_file" -o "$branches_file"

    while IFS= read -r branch; do
      [[ -z "$branch" ]] && continue
      if ! branch_commits=$(fetch_branch_commits_json "$repo" "$branch"); then
        continue
      fi
      printf '%s' "$branch_commits" \
        | jq -r --arg b "$branch" 'if type == "array" then .[] else empty end | [.sha, .commit.author.date, .commit.author.email, (.author.login // ""), (.commit.message | split("\n")[0] | gsub("\t"; " ") | gsub("\\|"; "/")), $b] | @tsv' \
        | while IFS=$'\t' read -r sha _ _ _ msg br; do
            [[ -z "$sha" ]] && continue
            printf '%s\t%s\t%s\t%s\n' "$repo" "$sha" "$msg" "$br" >> "$repo_candidate_rows"
          done
    done < "$branches_file"
  } &
  register_job_pid "$!"
done < "$repos_file"

wait_for_all_jobs
find "$repo_scan_dir" -name '*.candidate.tsv' -type f -exec cat {} + >> "$candidate_rows"
find "$repo_scan_dir" -name '*.default_branch.tsv' -type f -exec cat {} + >> "$repo_default_branches"
find "$repo_scan_dir" -name '*.skipped.txt' -type f -exec cat {} + >> "$skipped_repos"

sort -u "$candidate_rows" -o "$candidate_rows"
cut -f1,2 "$candidate_rows" | sort -u > "$tmp_dir/candidate_unique_shas.tsv"

commit_details_dir="$tmp_dir/commit_details"
default_branch_shas_dir="$tmp_dir/default_branch_shas"
mkdir -p "$commit_details_dir" "$default_branch_shas_dir"

while IFS= read -r repo; do
  [[ -z "$repo" ]] && continue
  repo_slug_value=$(repo_slug "$repo")
  repo_shas_file="$tmp_dir/detail_${repo_slug_value}.txt"
  awk -F '\t' -v r="$repo" '$1==r {print $2}' "$tmp_dir/candidate_unique_shas.tsv" > "$repo_shas_file"
  if [[ -s "$repo_shas_file" ]]; then
    wait_for_available_slot
    {
      fetch_commit_details_for_repo "$repo" "$repo_shas_file" > "$commit_details_dir/${repo_slug_value}.tsv"
    } &
    register_job_pid "$!"
  fi

  default_branch=$(awk -F '\t' -v r="$repo" '$1==r {print $2; exit}' "$repo_default_branches")
  [[ -z "$default_branch" ]] && continue
  wait_for_available_slot
  {
    if fetch_branch_commits_json "$repo" "$default_branch" \
      | jq -r 'if type == "array" then .[].sha else empty end' \
      | sort -u > "$default_branch_shas_dir/${repo_slug_value}.txt"; then
      :
    else
      : > "$default_branch_shas_dir/${repo_slug_value}.txt"
    fi
  } &
  register_job_pid "$!"
done < "$repos_file"

wait_for_all_jobs
find "$commit_details_dir" -name '*.tsv' -type f -exec cat {} + >> "$commit_details_file"
sort -u "$commit_details_file" -o "$commit_details_file"

awk -F '\t' '!seen[$1 FS $2]++ {print $1 "\t" $2 "\t" $3}' "$candidate_rows" | while IFS=$'\t' read -r repo sha msg; do
  [[ -z "$repo" || -z "$sha" ]] && continue

  if grep -F -q "$repo"$'\t'"$sha" "$pr_today_shas"; then
    continue
  fi

  detail_row=$(awk -F '\t' -v r="$repo" -v s="$sha" '$1==r && $2==s {print; exit}' "$commit_details_file")
  [[ -z "$detail_row" ]] && continue

  pulls_len=$(printf '%s' "$detail_row" | awk -F '\t' '{print $5}')
  if [[ "$pulls_len" != "0" ]]; then
    continue
  fi

  author_login=$(printf '%s' "$detail_row" | awk -F '\t' '{print $6}')
  committer_login=$(printf '%s' "$detail_row" | awk -F '\t' '{print $7}')
  author_email=$(printf '%s' "$detail_row" | awk -F '\t' '{print $8}')
  committer_email=$(printf '%s' "$detail_row" | awk -F '\t' '{print $9}')

  if [[ "$author_login" != "$USERNAME" && "$committer_login" != "$USERNAME" && "$author_email" != "$USER_EMAIL" && "$committer_email" != "$USER_EMAIL" ]]; then
    continue
  fi

  a=$(printf '%s' "$detail_row" | awk -F '\t' '{print $3}')
  d=$(printf '%s' "$detail_row" | awk -F '\t' '{print $4}')

  def_shas_file="$default_branch_shas_dir/$(repo_slug "$repo").txt"

  bucket="branch_only"
  if grep -q "^$sha$" "$def_shas_file"; then
    bucket="default"
  fi

  branch_hint=$(awk -F '\t' -v r="$repo" -v s="$sha" '$1==r && $2==s {print $4}' "$candidate_rows" | sort -u | paste -sd ',' -)
  if [[ -z "$branch_hint" ]]; then
    branch_hint="unknown"
  fi

  nonpr_sha_file="$tmp_dir/nonpr_$(repo_slug "$repo")_${sha}.txt"
  printf '%s\n' "$sha" > "$nonpr_sha_file"
  pivot_stage_totals=$(sum_pivot_stage_commit_lines "$repo" "$nonpr_sha_file")
  pivot_stage_add=$(printf '%s' "$pivot_stage_totals" | cut -f1)
  pivot_stage_del=$(printf '%s' "$pivot_stage_totals" | cut -f2)
  a=$((a - pivot_stage_add))
  d=$((d - pivot_stage_del))
  printf '%s\tnonpr\t%s\t%s\n' "$repo" "$pivot_stage_add" "$pivot_stage_del" >> "$pivot_stage_rows"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "$bucket" "$branch_hint" "$sha" "$a" "$d" "$msg" >> "$nonpr_rows"
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
pivot_stage_add=$(awk -F '\t' '{a += $3} END {print a + 0}' "$pivot_stage_rows")
pivot_stage_del=$(awk -F '\t' '{d += $4} END {print d + 0}' "$pivot_stage_rows")
grand_total_lines=$((grand_add + grand_del))
pivot_stage_total_lines=$((pivot_stage_add + pivot_stage_del))
overall_total_lines=$((grand_total_lines + pivot_stage_total_lines))
pivot_stage_percent=$(awk -v pivot_stage="$pivot_stage_total_lines" -v total="$overall_total_lines" 'BEGIN { printf "%.1f", total ? (100 * pivot_stage / total) : 0 }')

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
echo "- Total lines changed (excluding .pivot/stages): +$grand_add/-$grand_del"
echo "- Lines in .pivot/stages: +$pivot_stage_add/-$pivot_stage_del ($pivot_stage_percent% of overall lines changed)"
