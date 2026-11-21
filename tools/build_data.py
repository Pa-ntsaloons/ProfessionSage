"""Builds Data.lua for Profession Sage from the WoW Forever client's own data tables.

The tables come from wago.tools (DB2 exports of the game client). Nothing here is
copied from other addons.

Usage:  python tools/build_data.py [build] [cache_dir]
        build defaults to the WoW Forever build below; cache_dir to tools/.cache
"""
import csv
import os
import sys
import urllib.request

import learn_data

BUILD = sys.argv[1] if len(sys.argv) > 1 else learn_data.BUILD
CACHE = sys.argv[2] if len(sys.argv) > 2 else learn_data.CACHE
OUT = learn_data.DATA

TABLES = ["SkillLine", "SkillLineAbility", "SpellName", "SpellEffect", "SpellReagents",
          "ItemEffect", "ItemXItemEffect", "Item", "ItemSparse"]

# Skill lines with recipes. Mining's smelting gives skill-ups; Herbalism,
# Fishing and Skinning only have a few camp recipes (Fish Bowl and so on),
# listed for their tooltips, not for leveling routes.
PROFESSIONS = [171, 164, 333, 202, 165, 197, 185, 129, 186, 40, 182, 356, 393]

# Reagents sold by vendors in unlimited supply. Item data gives a "buy price"
# for many items that no vendor sells, so this list is picked by hand; the addon
# also learns vendor prices at every merchant you visit.
VENDOR_REAGENTS = [
    2320, 2321, 4291, 8343, 14341,                          # thread
    3371, 3372, 8925, 18256,                                # vials
    2880, 3466, 18567,                                      # flux
    2678, 2692, 3713, 159, 1179, 4289, 4536,                # cooking
    2324, 2325, 2604, 2605, 4340, 4341, 4342, 6260, 6261, 10290,  # bleach & dyes
    4399, 4400, 2596, 3857, 6217, 4470, 11291, 3419,        # misc crafting
    5173, 2928, 8924, 8923, 2930,                           # poison supplies
]

JUNK_MARKERS = ("[DNT]", "(OLD)", "OLD ", "TEST", "Test ", "[PH]", "zzOLD", "DEPRECATED")

ACQUIRE_WITH_PROFESSION = "1"
LEARN_ESTIMATE_GAP = 10
ITEM_CLASS_RECIPE = "9"
EFFECT_CREATE_ITEM = "24"
TRIGGER_ON_LEARN = "6"


def table(name):
    path = os.path.join(CACHE, f"{name}.{BUILD}.csv")
    if not os.path.exists(path):
        os.makedirs(CACHE, exist_ok=True)
        url = f"https://wago.tools/db2/{name}/csv?build={BUILD}"
        print("downloading", url)
        request = urllib.request.Request(url, headers={"User-Agent": "ProfessionSage data build"})
        with urllib.request.urlopen(request, timeout=300) as response, open(path, "wb") as f:
            f.write(response.read())
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def num(value):
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return 0


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    # Learn levels checked by hand for WoW Forever (the client data has none
    # for trainer recipes), from learn_levels.csv.
    confirmed = learn_data.confirmed_levels()
    skill_lines = {r["ID"]: r for r in table("SkillLine")}
    spell_names = {r["ID"]: r["Name_lang"] for r in table("SpellName")}

    created = {}
    for r in table("SpellEffect"):
        if r["Effect"] == EFFECT_CREATE_ITEM and r["SpellID"] not in created and num(r["EffectItemType"]) > 0:
            created[r["SpellID"]] = (num(r["EffectItemType"]), max(1, num(r["EffectBasePointsF"])))

    reagents = {}
    for r in table("SpellReagents"):
        parts = []
        for i in range(8):
            item, count = num(r[f"Reagent_{i}"]), num(r[f"ReagentCount_{i}"])
            if item > 0 and count > 0:
                parts.append(f"{item}:{count}")
        if parts:
            reagents[r["SpellID"]] = ",".join(parts)

    item_class = {r["ID"]: r["ClassID"] for r in table("Item")}
    effects = {r["ID"]: r for r in table("ItemEffect")}
    teaches = {}
    for r in table("ItemXItemEffect"):
        effect = effects.get(r["ItemEffectID"])
        if effect and effect["TriggerType"] == TRIGGER_ON_LEARN and item_class.get(r["ItemID"]) == ITEM_CLASS_RECIPE:
            teaches.setdefault(effect["SpellID"], []).append(num(r["ItemID"]))

    sparse = {r["ID"]: r for r in table("ItemSparse")}

    recipes = {p: [] for p in PROFESSIONS}
    seen = set()
    skipped = 0
    for r in table("SkillLineAbility"):
        profession = num(r["SkillLine"])
        spell = r["Spell"]
        if profession not in recipes or spell in seen:
            continue
        grey = num(r["TrivialSkillLineRankHigh"])
        if grey <= 0:
            continue  # rank spells and other entries that never give skill-ups
        name = spell_names.get(spell)
        if not name or any(marker in name for marker in JUNK_MARKERS):
            skipped += 1
            continue
        if spell in confirmed and confirmed[spell] is None:
            skipped += 1  # still in the client files, but no longer learnable
            continue
        if spell not in created and spell not in reagents:
            skipped += 1
            continue
        seen.add(spell)
        item, count = created.get(spell, (0, 0))
        recipe_items = sorted(teaches.get(spell, []))
        yellow = num(r["TrivialSkillLineRankLow"])

        # The skill needed to learn it. MinSkillLineRank is 1 for nearly every
        # recipe in this client, so: a level confirmed for WoW Forever
        # (learn_levels.csv); the recipe item's required skill when there is
        # one; 1 for recipes you get with the profession; otherwise a cautious
        # estimate (most recipes turn yellow 5-25 points after you can learn
        # them). The addon replaces estimates with what trainers show.
        required = [num(sparse[str(i)]["RequiredSkillRank"]) for i in recipe_items if str(i) in sparse]
        if spell in confirmed:
            learn, exact = confirmed[spell], 1
        elif required:
            learn, exact = max(1, min(required)), 1
        elif r["AcquireMethod"] == ACQUIRE_WITH_PROFESSION:
            learn, exact = 1, 1
        else:
            learn, exact = max(1, min(yellow - LEARN_ESTIMATE_GAP, 300)), 0

        recipes[profession].append((
            num(spell),
            learn,                                 # skill needed to learn; orange from here
            yellow,                                # turns yellow
            grey,                                  # turns grey
            item, count,
            reagents.get(spell, ""),
            recipe_items[0] if recipe_items else 0,  # 0 = trainer (or learned automatically)
            num(r["RaceMasks_0"]),                 # 0 = any race
            max(1, num(r["NumSkillUps"])),
            exact,                                 # 0 = learn skill is an estimate
            # What a vendor charges for the recipe item, if a vendor sells it.
            # Only used once the addon knows a vendor does (Questie or a visit).
            min((num(sparse[str(i)]["BuyPrice"]) for i in recipe_items if str(i) in sparse), default=0),
        ))

    vendor = []
    for item in VENDOR_REAGENTS:
        row = sparse.get(str(item))
        price = num(row["BuyPrice"]) if row else 0
        stack = max(1, num(row["VendorStackCount"])) if row else 1
        if price > 0:
            vendor.append((item, max(1, round(price / stack)), row["Display_lang"]))

    lines = [
        "-- Generated by tools/build_data.py from the WoW Forever client's data tables",
        f"-- (build {BUILD}, via wago.tools). Do not edit by hand; run the script again.",
        "local _, ns = ...",
        "",
        f'ns.DATA_BUILD = "{BUILD}"',
        "",
        "-- [skill line] = name",
        "ns.PROFESSION_NAMES = {",
    ]
    for p in PROFESSIONS:
        lines.append(f"  [{p}] = {lua_string(skill_lines[str(p)]['DisplayName_lang'])},")
    lines += [
        "}",
        "",
        "-- [skill line] = { { recipe spell, learn at, yellow at, grey at, item made, count made,",
        '--   "reagent:qty,...", recipe item (0 = trainer), race mask (0 = all), skill-ups,',
        "--   learn-at is exact (1) or an estimate (0), vendor price of the recipe item }, ... }",
        "-- Green starts halfway between yellow and grey.",
        "ns.RECIPES = {",
    ]
    total = 0
    for p in PROFESSIONS:
        rows = sorted(recipes[p], key=lambda row: (row[1], row[2], row[0]))
        total += len(rows)
        lines.append(f"  [{p}] = {{ -- {skill_lines[str(p)]['DisplayName_lang']}, {len(rows)} recipes")
        for row in rows:
            spell, learn, yellow, grey, item, count, mats, source, race, ups, exact, cost = row
            lines.append(f'    {{{spell},{learn},{yellow},{grey},{item},{count},"{mats}",{source},{race},{ups},{exact},{cost}}},')
        lines.append("  },")
    lines += [
        "}",
        "",
        "-- [item] = copper per item, for reagents vendors always sell",
        "ns.VENDOR_PRICES = {",
    ]
    for item, price, name in vendor:
        lines.append(f"  [{item}] = {price}, -- {name}")
    lines += ["}", ""]

    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print(f"wrote {os.path.normpath(OUT)}: {total} recipes, {len(vendor)} vendor reagents, skipped {skipped}")
    for p in PROFESSIONS:
        print(f"  {skill_lines[str(p)]['DisplayName_lang']}: {len(recipes[p])}")


if __name__ == "__main__":
    main()
