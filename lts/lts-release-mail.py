#!/usr/bin/env python3
#
# Copyright (c) 2026, Linaro Limited and Contributors. All rights reserved.
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Prepare Hafnium LTS release email content.
#
import argparse
import sys
import os
import re
import subprocess


DEFAULT_URL = f"https://review.trustedfirmware.org/{os.environ.get('GERRIT_PROJECT_PREFIX', '')}hafnium/hafnium"
WORKDIR = "hafnium"

# Regex patterns for commit subjects to exclude from the release email.
# Commits matching any of these are auto-generated or administrative and not
# meaningful to release recipients.
SKIP_PATTERNS = [
    # Changelog update commits created by the release process itself
    r"docs\(changelog\): ",
    # Gerrit topic-based merge commits, e.g. "Merge changes from topic 'foo'"
    r"Merge changes from topic ",
    # Gerrit merge commits quoting the source, e.g. 'Merge "fix xyz" into lts-v2.14'
    r"Merge \".+\" into ",
    # Gerrit grouped merge commits, e.g. "Merge changes I1234,I5678 into lts-v2.14"
    r"Merge changes .+ into ",
]


def run(cmd):
    """Execute a shell command, raising an exception on failure."""
    return subprocess.check_call(cmd, shell=True)


def maybe_int(s):
    """Convert numeric strings to int for proper version comparison.

    This allows version components like ["lts-v2", "14", "3"] to be compared
    numerically (14 > 3) rather than lexicographically ("3" > "14").
    """
    if s.isdigit():
        return int(s)
    return s


def is_sandbox_run():
    """Return True unless SANDBOX_RUN is explicitly set to 'false'."""
    return os.environ.get("SANDBOX_RUN") != "false"


def main():
    argp = argparse.ArgumentParser(description="Prepare Hafnium LTS release email content")
    argp.add_argument("-u", "--url", default=DEFAULT_URL, help="repository URL (default: %(default)s)")
    argp.add_argument("-b", "--branch", default="", help="repository branch for --latest option")
    argp.add_argument("--latest", action="store_true", help="use latest release tag on --branch")
    argp.add_argument("release_tag", nargs="?", help="release tag")
    args = argp.parse_args()
    if not args.release_tag and not args.latest:
        argp.error("Either release_tag or --latest is required")

    with open(os.path.dirname(__file__) + "/lts-release-mail.txt") as f:
        mail_template = f.read()

    if not os.path.exists(WORKDIR):
        run("git clone %s %s" % (args.url, WORKDIR))
        os.chdir(WORKDIR)
    else:
        os.chdir(WORKDIR)
        run("git pull --quiet")

    # Resolve the latest release tag on the given branch by scanning all tags
    # and picking the one with the highest semantic version.
    if args.latest:
        latest = []
        for l in os.popen("git tag"):
            # Match LTS release tags in the form "lts-vMAJOR.MINOR.PATCH",
            # e.g. "lts-v2.14.1". This filters out non-release tags such as
            # sandbox tags or unrelated tags.
            if not re.match(r"lts-v\d+\.\d+\.\d+", l):
                continue
            if not l.startswith(args.branch):
                continue
            l = l.rstrip()
            # Split tag by "." to get comparable version components.
            # e.g. "lts-v2.14.3" → ["lts-v2", 14, 3, "lts-v2.14.3"]
            # The original tag string is appended so it can be retrieved
            # after comparison finds the maximum.
            comps = [maybe_int(x) for x in l.split(".")]
            comps.append(l)
            if comps > latest:
                latest = comps
        if not latest:
            argp.error("Could not find latest LTS tag")
        args.release_tag = latest[-1]

    base_release = args.release_tag
    # Sandbox tags have a timestamp suffix, e.g. "sandbox/lts-v2.14.1-20260226T1605".
    # Strip the "sandbox/" prefix and trailing "-TIMESTAMP" (digits only) to recover
    # the underlying release tag "lts-v2.14.1" for version parsing and template rendering.
    if base_release.startswith("sandbox/"):
        # Regex: capture everything after "sandbox/" up to the last "-" followed
        # by one or more digits (the timestamp). Group 1 = the base release tag.
        m = re.match(r"sandbox/(.+)-\d+", base_release)
        base_release = m.group(1)

    # Parse the release tag into its branch prefix and patch version.
    # Regex: capture "lts-vMAJOR.MINOR" (group 1) and "PATCH" (group 2).
    # e.g. "lts-v2.14.1" → group(1)="lts-v2.14", group(2)="1"
    # The branch prefix identifies the LTS branch; the patch version is used
    # to compute the previous release tag for changelog diffing.
    match = re.match(r"(lts-v\d+\.\d+)\.(\d+)", base_release)
    if not match:
        sys.stderr.write(f"Error: Invalid tag format {base_release}\n")
        sys.exit(1)

    branch_prefix = match.group(1)
    patch_version = int(match.group(2))

    # The very first release on a branch (patch 0) has no prior tag to diff
    # against, so there is no meaningful changelog to email.
    if patch_version == 0:
        sys.stderr.write(f"First release of the branch {base_release}. Skipping email.\n")
        return

    # Construct the previous release tag by decrementing the patch version,
    # e.g. "lts-v2.14.1" → previous is "lts-v2.14.0".
    prev_release = f"{branch_prefix}.{patch_version - 1}"

    if subprocess.call(f"git rev-parse --verify {prev_release}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) != 0:
        sys.stderr.write(f"Error: Previous release tag {prev_release} not found in repository\n")
        sys.exit(1)

    # Collect commit subjects between the previous and current release tags,
    # filtering out auto-generated commits (changelog updates, merges).
    subjects = []
    for l in os.popen("git log --oneline --reverse %s..%s" % (prev_release, args.release_tag)):
        skip = False
        # Split "abbrev_hash subject" and match the subject portion against
        # each SKIP_PATTERNS regex to filter out administrative commits.
        for pat in SKIP_PATTERNS:
            if re.match(pat, l.split(" ", 1)[1]):
                skip = True
        if not skip:
            subjects.append(l.rstrip())

    if not subjects:
        sys.stderr.write("No changes found, skipping email generation\n")
        return

    # For each commit, extract its Gerrit Change-Id from the commit message
    # and build a review URL. The Change-Id is a Gerrit-specific trailer line
    # in the format "Change-Id: I<40-hex-chars>" added by the commit-msg hook.
    urls = []
    for s in subjects:
        commit_id, _ = s.split(" ", 1)
        change_id = None
        for l in os.popen("git show %s" % commit_id):
            if "Change-Id:" in l:
                _, change_id = l.strip().split(None, 1)
        if change_id:
            urls.append("https://review.trustedfirmware.org/q/" + change_id)

    # Every commit must have a Change-Id; if not, something is wrong.
    assert len(subjects) == len(urls)

    # Format commits as numbered entries for the email body, e.g.:
    #   abc1234 fix: resolve memory leak in spci handler [1]
    #   def5678 feat: add partition info get support [2]
    commits = ""
    for i, s in enumerate(subjects, 1):
        commits += "%s [%d]\n" % (s, i)

    # Format corresponding Gerrit review URLs as numbered references, e.g.:
    #   [1] https://review.trustedfirmware.org/q/I1234...
    #   [2] https://review.trustedfirmware.org/q/I5678...
    references = ""
    for i, s in enumerate(urls, 1):
        references += "[%d] %s\n" % (i, s)

    # Strip trailing newline, as it's encoded in template.
    commits = commits.rstrip()
    references = references.rstrip()

    # Extract the numeric version string by stripping the "lts-v" prefix,
    # e.g. "lts-v2.14.1" → "2.14.1", for use in the email subject and body.
    version = base_release[len("lts-v"):]
    sys.stdout.write(
        mail_template.format(
            version=version,
            commits=commits,
            references=references,
        )
    )


if __name__ == "__main__":
    main()
