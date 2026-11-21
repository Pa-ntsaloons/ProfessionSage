"""Shared by the data tools: where the files are, reading and writing
learn_levels.csv, spell names from the cached game data, and the recipes in
Data.lua.

learn_levels.csv has one row per recipe spell. Its skill column is the skill a
trainer needs to teach the recipe, or one of:
  removed   no longer in the game (build_data.py leaves the recipe out)
  unknown   checked, but no source states a level (the estimate is kept)
"""
import csv
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = "1.60.1.70938"  # the WoW Forever client build the data comes from
CACHE = os.path.join(HERE, ".cache")
DATA = os.path.join(HERE, "..", "Data.lua")
LEARN_LEVELS = os.path.join(HERE, "learn_levels.csv")

FIELDS = ["recipe_spell", "skill", "name", "source"]
REMOVED = "removed"
UNKNOWN = "unknown"


def read_rows():
    """learn_levels.csv as a list of dicts (empty when there's no file)."""
    if not os.path.exists(LEARN_LEVELS):
        return []
    with open(LEARN_LEVELS, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def write_rows(rows):
    with open(LEARN_LEVELS, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def confirmed_levels():
    """{recipe spell: skill needed to learn it, or None when it's been removed}.
    "unknown" rows are left out, so their estimates stay."""
    levels = {}
    for row in read_rows():
        skill = row["skill"].strip().lower()
        if skill == REMOVED:
            levels[row["recipe_spell"]] = None
        elif skill != UNKNOWN:
            try:
                levels[row["recipe_spell"]] = int(float(skill))
            except ValueError:
                levels[row["recipe_spell"]] = 0
    return levels


def spell_names_path(build=BUILD, cache=CACHE):
    return os.path.join(cache, f"SpellName.{build}.csv")


def spell_names(build=BUILD, cache=CACHE):
    """{spell id: name} from the cached game data, or {} before the first build."""
    path = spell_names_path(build, cache)
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as f:
        return {row["ID"]: row["Name_lang"] for row in csv.DictReader(f)}


PROFESSION_LINE = re.compile(r'^\s*\[\d+\] = \{ -- ([^,]+),')
# {spell, learn, yellow, grey, item, count, "mats", recipeItem, raceMask, skillUps, exact, vendorCost}
RECIPE_LINE = re.compile(r'^\s*\{(\d+),(\d+),(\d+),(\d+),\d+,\d+,"[^"]*",\d+,\d+,\d+,(\d),\d+\},')


def data_recipes():
    """Every recipe in Data.lua: dicts with profession, spell, learn, yellow,
    grey and exact (False when the learn level is an estimate)."""
    profession, result = None, []
    with open(DATA, encoding="utf-8") as f:
        for line in f:
            match = PROFESSION_LINE.match(line)
            if match:
                profession = match.group(1)
                continue
            match = RECIPE_LINE.match(line)
            if match and profession is not None:
                spell, learn, yellow, grey, exact = match.groups()
                result.append({"profession": profession, "spell": spell, "learn": int(learn),
                               "yellow": int(yellow), "grey": int(grey), "exact": exact == "1"})
    return result
