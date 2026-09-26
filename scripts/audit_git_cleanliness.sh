#!/usr/bin/env bash
# scripts/audit_git_cleanliness.sh
# Turnkey municipal audit script for git working trees and worktrees across Camp Colt.
# Maintained by Mayor (Headquarters Commandant) and S-3 Operations.
# Reference: SOP-0.3-WORKTREE-CLEANLINESS (MCTP 3-30A Garrison Hygiene)

set -euo pipefail

COLONY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL_ON_DIRTY=1
VERBOSE=0
PRUNE_WORKTREES=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Audits git working trees and worktrees across colony root and all rigs.

Options:
  -v, --verbose     Show detailed porcelain status and worktree lists
  -p, --prune       Automatically prune stale git worktrees
  -w, --warn-only   Exit 0 even if dirty working trees or extra worktrees are found
  -h, --help        Show this help message

Exit Codes:
  0: All working trees clean; zero orphaned worktrees
  1: One or more repositories have uncommitted changes or untracked files
  2: Script configuration or execution error
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -p|--prune)
            PRUNE_WORKTREES=1
            shift
            ;;
        -w|--warn-only)
            FAIL_ON_DIRTY=0
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

cd "${COLONY_ROOT}"

TARGET_DIRS=(".")
if [[ -d "rigs" ]]; then
    for rig_dir in rigs/*; do
        if [[ -d "${rig_dir}" && (-d "${rig_dir}/.git" || -f "${rig_dir}/.git") ]]; then
            TARGET_DIRS+=("${rig_dir}")
        fi
    done
fi

TOTAL_REPOS=0
DIRTY_REPOS=0
EXTRA_WORKTREES=0

echo "=== Camp Colt Git Worktree & Working Tree Cleanliness Audit ==="
echo "Audit Root: ${COLONY_ROOT}"
echo "Timestamp:  $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "---------------------------------------------------------------"

for dir in "${TARGET_DIRS[@]}"; do
    TOTAL_REPOS=$((TOTAL_REPOS + 1))
    display_name="${dir}"
    if [[ "${dir}" == "." ]]; then
        display_name="colony (root)"
    fi

    # Prune worktrees if requested
    if [[ "${PRUNE_WORKTREES}" -eq 1 ]]; then
        git -C "${dir}" worktree prune 2>/dev/null || true
    fi

    # 1. Check Working Tree Status
    porcelain_status="$(git -C "${dir}" status --porcelain 2>/dev/null || true)"
    
    # 2. Check Worktree Count
    worktree_count="$(git -C "${dir}" worktree list --porcelain 2>/dev/null | grep -c '^worktree ' || true)"
    
    repo_dirty=0
    if [[ -n "${porcelain_status}" ]]; then
        repo_dirty=1
        DIRTY_REPOS=$((DIRTY_REPOS + 1))
    fi

    extra_wt=0
    if [[ "${worktree_count}" -gt 1 ]]; then
        extra_wt=$((worktree_count - 1))
        EXTRA_WORKTREES=$((EXTRA_WORKTREES + extra_wt))
    fi

    # Output status line
    if [[ "${repo_dirty}" -eq 0 && "${extra_wt}" -eq 0 ]]; then
        printf "  %-32s [OK] (clean, 1 worktree)\n" "${display_name}"
    else
        printf "  %-32s [DIRTY]" "${display_name}"
        if [[ "${repo_dirty}" -eq 1 ]]; then
            dirty_count="$(echo "${porcelain_status}" | wc -l | tr -d ' ')"
            printf " %s modified/untracked" "${dirty_count}"
        fi
        if [[ "${extra_wt}" -gt 0 ]]; then
            printf " %s secondary worktree(s)" "${extra_wt}"
        fi
        printf "\n"

        if [[ "${VERBOSE}" -eq 1 ]]; then
            if [[ -n "${porcelain_status}" ]]; then
                echo "    Status Details:"
                while IFS= read -r line; do
                    echo "      ${line}"
                done <<< "${porcelain_status}"
            fi
            if [[ "${extra_wt}" -gt 0 ]]; then
                echo "    Worktrees:"
                git -C "${dir}" worktree list | while IFS= read -r line; do
                    echo "      ${line}"
                done
            fi
        fi
    fi
done

echo "---------------------------------------------------------------"
echo "Audit Summary: ${TOTAL_REPOS} repos checked | ${DIRTY_REPOS} dirty | ${EXTRA_WORKTREES} extra worktrees"

if [[ "${DIRTY_REPOS}" -gt 0 || "${EXTRA_WORKTREES}" -gt 0 ]]; then
    if [[ "${FAIL_ON_DIRTY}" -eq 1 ]]; then
        echo "RESULT: FAILED — Non-clean git state detected." >&2
        exit 1
    else
        echo "RESULT: WARNING — Non-clean git state detected (warn-only mode)."
        exit 0
    fi
else
    echo "RESULT: PASSED — 100% clean garrison git posture."
    exit 0
fi
