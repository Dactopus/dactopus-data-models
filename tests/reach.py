# /// script
# dependencies = ["pyyaml"]
# ///
"""Which jobs the changed files reach, once the changes of text alone are left out.

The filters in ci.yml match paths; this script reads what changed in them.
A file a job reads is left out of that job when its change cannot move
anything the job builds or checks:

- a dbt_project.yml whose only changed line is the top-level `version:`;
- an Ossie model equal before and after once every `description` and
  `ai_context` is removed. The validate job is left as its filter says:
  it reads the whole model.

Anything else counts: a file added, deleted or renamed, one that does not
parse, any error. A job skipped by mistake passes `CI passed`, so a doubt
runs the job, and so does a filter without its list of files. Run with
the commits to compare and dorny/paths-filter's outputs (`list-files:
json`) as a JSON object in $FILTERS; it prints `<filter>=true|false` for
each filter, e.g.:

    FILTERS='{"ga4": "true", "ga4_files": "[\\"sources/ga4/dbt_project.yml\\"]"}' \\
        uv run tests/reach.py HEAD^1 HEAD
"""
import fnmatch
import json
import os
import subprocess
import sys

import yaml

# Jobs that read every byte of the files their filter matches.
WHOLE = {"validate"}


def show(rev, path):
    return subprocess.run(["git", "show", f"{rev}:{path}"], capture_output=True, text=True, check=True).stdout


def without_text(node):
    if isinstance(node, dict):
        return {k: without_text(v) for k, v in node.items() if k not in ("description", "ai_context")}
    if isinstance(node, list):
        return [without_text(v) for v in node]
    return node


def without_version(text):
    return [line for line in text.splitlines() if not line.startswith("version:")]


def text_only(base, head, path):
    try:
        before, after = show(base, path), show(head, path)
        if fnmatch.fnmatch(path, "*/*/dbt_project.yml"):
            return without_version(before) == without_version(after)
        if fnmatch.fnmatch(path, "entities/*.yaml"):
            return without_text(yaml.safe_load(before)) == without_text(yaml.safe_load(after))
    except Exception as error:
        print(f"{path}: {error}", file=sys.stderr)
    return False


base, head = sys.argv[1], sys.argv[2]
outputs = json.loads(os.environ["FILTERS"])
for name, matched in sorted(outputs.items()):
    if matched not in ("true", "false"):
        continue
    files = json.loads(outputs.get(f"{name}_files", "null"))
    if files is None or name in WHOLE:
        reached = matched == "true"
    else:
        reached = any(not text_only(base, head, f) for f in files)
    print(f"{name}={'true' if reached else 'false'}")
