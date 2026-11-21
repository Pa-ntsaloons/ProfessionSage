# Profession Sage (WoW Forever)

Profit on every recipe, the best route to your target skill, and where to gather — built into Blizzard's own profession window.

## Features
- **Profit on every recipe.** Each recipe shows what you'd make or lose crafting it: the better of its auction price (after the AH cut) and vendor price, minus the cost of its materials. Hover for the breakdown and its skill-up colors.
- **Leveling guide.** Click the book button in the profession window's title bar, next to the close button. Type or slide a target skill and get a route from your current skill: what to craft and how many times (fail chance included), when to learn new recipes, and when to train the next rank.
- **Route styles.** Most profit, Fewest crafts or Balanced. Hover the selector to compare all three.
- **Where to learn recipes.** Trainers with names and zones, vendors, drops and quest rewards.
- **Shopping list.** Everything the route needs, minus what's in your bags and bank. Send it to Auctionator as a shopping list.
- **Plan.** Choose how many of a recipe you want. The status shows whether everything is in your bags, some is in your bank or on other characters, or what you're short of. If you're short, an optional popup at the side of your screen lists what you still need and ticks items off as you get them.
- **Gathering tooltips.** Herbs, ore veins and skinnable creatures show the skill they need and yours, colored for how likely a skill-up is.
- **Gathering guide.** Herbalism, Mining, Skinning and Fishing: pick a target skill and see where to go at each skill range, what you'll find there with values, and when to train the next rank.

## Works with (optional)
- [Auctionator](https://www.curseforge.com/wow/addons/auctionator): auction prices and shopping lists. Recommended.
- Questie: vendors, drops, quests and trainers for each recipe.
- GatherMate2: sorts gathering zones by the nodes you've found.
- Syndicator (or Baganator): shows which of your other characters have the materials you need.

Without them the addon uses vendor prices, and remembers trainers, vendors and prices as you visit them.

## Commands
- `/sage`: open or close the guide (with a profession open)
- `/sage profit`: show or hide profit next to recipes
- `/sage cut <percent>`: auction house cut used for profit (default 5)
- `/sage track` / `/sage clear`: show or stop the materials popup
- `/sage errors`: list errors the addon caught (for bug reports)

## Recipe data
Recipes, skill-up colors and materials are generated from the WoW Forever client's own data (`tools/build_data.py`). The skill needed for trainer recipes isn't in the client data, so it comes from a checked list for WoW Forever where known, and is estimated otherwise until you open that profession's trainer. The gathering guide follows the classic leveling zones.

## Install / update
Copy this folder to `World of Warcraft\_forever_\Interface\AddOns\ProfessionSage`.
If a client patch changes the interface version, update `## Interface:` in the .toc (`/dump select(4, GetBuildInfo())` in game).

## Updating the recipe data
`python tools/build_data.py <build>` downloads the client tables for that build from wago.tools and rewrites `Data.lua`.

## License
MIT
