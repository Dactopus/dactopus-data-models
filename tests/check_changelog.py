"""Check CHANGELOG.md against Common Changelog and against UPGRADING.md.

CHANGELOG.md (https://common-changelog.org) opens with `# Changelog`,
then releases newest first, each `## [X.Y.Z] - YYYY-MM-DD` with a link
reference to its GitHub release at the end of the file; there is no
Unreleased section. A release holds an optional notice, one paragraph
in italics on one line, then its groups, `### Changed`, `Added`,
`Removed`, `Fixed`, in that order, each a list of one-line changes. A
change starts with a verb in the imperative (`Add`, not `Adds`,
`Added` or `Adding`), breaking changes first as `**Breaking:**`, and
ends with its references in parentheses, each a link. A release without
groups has a notice.

UPGRADING.md has an optional `## Unreleased`, then a section `## X.Y.Z`
for each release with steps, newest first. A release has a section
there exactly when its notice links to it.

Run from the repository root:

    uv run tests/check_changelog.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RELEASES = "https://github.com/Dactopus/dactopus-data-models/releases/tag/v"
GROUPS = ["Changed", "Added", "Removed", "Fixed"]
HEADING = re.compile(r"## \[(\d+\.\d+\.\d+)\] - (\d{4}-\d{2}-\d{2})")
NOTICE = re.compile(r"_[^_].*[^_]_")
REFERENCE = r"\[[^\]]+\]\(https://[^)]+\)"
CHANGE = re.compile(rf"- (\*\*Breaking:\*\* )?([A-Z][a-z]+)\b.* \({REFERENCE}(, {REFERENCE})*\)")
UPGRADE_LINK = re.compile(r"\(UPGRADING\.md#(\d+)\)")
# Imperatives that end like a third person, a past or a gerund.
IMPERATIVES = {"Bring", "Embed", "Feed", "Need", "Seed", "Shed", "Speed", "String"}


def imperative(verb):
    if verb in IMPERATIVES or verb.endswith(("ss", "us", "is")):
        return True
    return not verb.endswith(("s", "ed", "ing"))


def semver(version):
    return tuple(int(part) for part in version.split("."))


def anchor(version):
    return version.replace(".", "")


def releases(lines):
    """Each release's version, heading line number and body lines."""
    found = []
    for number, line in enumerate(lines, 1):
        if line.startswith("## "):
            found.append([line, number, []])
        elif found and not line.startswith("["):
            found[-1][2].append((number, line))
    return found


def check_release(version, body, problems):
    """The notice's link anchor, or None."""
    blocks, current = [], []
    for number, line in body:
        if line:
            current.append((number, line))
        elif current:
            blocks.append(current)
            current = []
    if current:
        blocks.append(current)
    notice = None
    if blocks and blocks[0][0][1].startswith("_"):
        (number, line), *rest = blocks.pop(0)
        if rest or not NOTICE.fullmatch(line):
            problems.append(f"CHANGELOG.md:{number}: {version}'s notice must be one line in italics")
        links = UPGRADE_LINK.findall(line)
        notice = links[0] if links else ""
    seen = []
    while blocks:
        (number, line), *rest = blocks.pop(0)
        group = line.removeprefix("### ")
        if not line.startswith("### ") or group not in GROUPS or rest:
            problems.append(f"CHANGELOG.md:{number}: {version} may hold only a notice and the groups "
                            f"{', '.join(GROUPS)}, each heading on its own line: {line}")
            continue
        if seen and GROUPS.index(group) <= GROUPS.index(seen[-1]):
            problems.append(f"CHANGELOG.md:{number}: {version}'s groups must come in the order "
                            f"{', '.join(GROUPS)}, each once")
        seen.append(group)
        if not blocks or blocks[0][0][1].startswith("#"):
            problems.append(f"CHANGELOG.md:{number}: {version}'s {group} has no changes")
            continue
        breaking_over = False
        for number, line in blocks.pop(0):
            match = CHANGE.fullmatch(line)
            if not match:
                problems.append(f"CHANGELOG.md:{number}: a change is one line, `- <change> (<references>)`, "
                                f"each reference a link: {line[:80]}")
                continue
            verb = match.group(2)
            if not imperative(verb):
                problems.append(f"CHANGELOG.md:{number}: start with a verb in the imperative, not {verb}")
            if match.group(1) and breaking_over:
                problems.append(f"CHANGELOG.md:{number}: breaking changes come first in their group")
            breaking_over = breaking_over or not match.group(1)
    if not seen and notice is None:
        problems.append(f"CHANGELOG.md: {version} has no changes and no notice")
    return notice


def check():
    problems = []
    lines = (ROOT / "CHANGELOG.md").read_text().splitlines()
    if not lines or lines[0] != "# Changelog":
        problems.append("CHANGELOG.md: the first line must be `# Changelog`")
    references = dict(re.findall(r"^\[(\d+\.\d+\.\d+)\]: (\S+)$", "\n".join(lines), flags=re.M))
    versions, notices = [], {}
    for heading, number, body in releases(lines):
        match = HEADING.fullmatch(heading)
        if not match:
            problems.append(f"CHANGELOG.md:{number}: a release heading is `## [X.Y.Z] - YYYY-MM-DD`, "
                            f"and there is no Unreleased section: {heading}")
            continue
        version = match.group(1)
        if versions and semver(version) >= semver(versions[-1]):
            problems.append(f"CHANGELOG.md:{number}: {version} must come after {versions[-1]}: newest first")
        versions.append(version)
        if references.get(version) != RELEASES + version:
            problems.append(f"CHANGELOG.md: the link reference of {version} must be "
                            f"`[{version}]: {RELEASES}{version}`")
        notices[version] = check_release(version, body, problems)
    extra = sorted(set(references) - set(versions), key=semver)
    if extra:
        problems.append(f"CHANGELOG.md: link references without a release: {', '.join(extra)}")

    sections = re.findall(r"^## (.+)$", (ROOT / "UPGRADING.md").read_text(), flags=re.M)
    if sections and sections[0] == "Unreleased":
        sections.pop(0)
    previous = None
    for section in sections:
        if not re.fullmatch(r"\d+\.\d+\.\d+", section):
            problems.append(f"UPGRADING.md: a section is `## Unreleased`, first, or `## X.Y.Z`: {section}")
            continue
        if section not in notices:
            problems.append(f"UPGRADING.md: {section} is not a release in CHANGELOG.md")
        elif previous and semver(section) >= semver(previous):
            problems.append(f"UPGRADING.md: {section} must come after {previous}: newest first")
        previous = section
    for version, notice in notices.items():
        linked = notice == anchor(version)
        if (version in sections) != linked:
            problems.append(f"CHANGELOG.md: {version}'s notice must link to UPGRADING.md#{anchor(version)} "
                            f"exactly when UPGRADING.md has a section {version}")
        elif notice and not linked:
            problems.append(f"CHANGELOG.md: {version}'s notice links to UPGRADING.md#{notice}, "
                            f"not to its own section #{anchor(version)}")
    return problems, len(versions)


def main():
    problems, count = check()
    for problem in problems:
        print(f"FAIL {problem}")
    if not problems:
        print(f"CHANGELOG.md: {count} releases in Common Changelog, notices match UPGRADING.md")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
