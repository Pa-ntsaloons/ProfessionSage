"""Copies the learn levels Profession Sage recorded at trainers in game into
learn_levels.csv, so every player gets them.

In game, open the trainers for your professions (the addon reads each trainer's
whole list), then log out or /reload so WoW writes its saved data to disk.

Usage:  python tools/import_trainer_levels.py [--wow PATH] [--rebuild]

  --wow      the WoW Forever folder (default: the usual install path)
  --rebuild  run build_data.py afterwards, so Data.lua picks up the levels

A level read at a trainer replaces one looked up by hand when they differ;
the script lists every such change.
"""
import argparse
import glob
import os
import re
import subprocess
import sys

import learn_data

HERE = learn_data.HERE
DEFAULT_WOW = r"C:\Program Files (x86)\World of Warcraft\_forever_"
SOURCE = "in-game trainer scan"

LEARN_AT_BLOCK = re.compile(r'\["learnAt"\]\s*=\s*\{(.*?)\n\s*\}', re.S)
LEARN_AT_ENTRY = re.compile(r'\[(\d+)\]\s*=\s*(\d+)')


def saved_files(wow):
    pattern = os.path.join(wow, "WTF", "Account", "*", "SavedVariables", "ProfessionSage.lua")
    return glob.glob(pattern)


def recorded_levels(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    match = LEARN_AT_BLOCK.search(text)
    if not match:
        return {}
    return {spell: int(skill) for spell, skill in LEARN_AT_ENTRY.findall(match.group(1))}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--wow", default=DEFAULT_WOW, help="WoW Forever folder")
    parser.add_argument("--rebuild", action="store_true", help="rebuild Data.lua afterwards")
    args = parser.parse_args()

    files = saved_files(args.wow)
    if not files:
        sys.exit(f"No Profession Sage saved data under {args.wow}\\WTF. Log in with the addon once, "
                 "or pass --wow with your WoW Forever folder.")

    recorded = {}
    for path in files:
        recorded.update(recorded_levels(path))
    if not recorded:
        print("No trainer levels recorded yet. Open a profession trainer in game, then /reload or log out.")
        return

    rows = learn_data.read_rows()
    by_spell = {row["recipe_spell"]: row for row in rows}
    names = learn_data.spell_names()

    added, changed, same = [], [], 0
    for spell, skill in sorted(recorded.items(), key=lambda item: (item[1], item[0])):
        row = by_spell.get(spell)
        if row is None:
            row = {"recipe_spell": spell, "skill": str(skill), "name": names.get(spell, "?"), "source": SOURCE}
            rows.append(row)
            by_spell[spell] = row
            added.append(row)
        elif row["skill"] != str(skill):
            changed.append((row["name"], row["skill"], skill))
            row["skill"], row["source"] = str(skill), SOURCE
        else:
            same += 1

    learn_data.write_rows(rows)

    print(f"Read {len(recorded)} trainer level(s) from {len(files)} saved-data file(s).")
    for row in added:
        print(f"  added    {row['name']}: {row['skill']}")
    for name, old, new in changed:
        print(f"  changed  {name}: {old} -> {new} (trainer)")
    print(f"{len(added)} added, {len(changed)} changed, {same} already right.")

    if (added or changed) and args.rebuild:
        subprocess.run([sys.executable, os.path.join(HERE, "build_data.py")], check=True)
    elif added or changed:
        print("Run python tools/build_data.py to put them into Data.lua.")


if __name__ == "__main__":
    main()
