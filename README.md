# Profession Sage (WoW Forever)

Profit on every recipe, the best route to your target skill, and where to gather — built into Blizzard's own profession window.

## Features
- **Profit on every recipe.** Each recipe shows what you'd make or lose crafting it: the better of its auction price (after the AH cut) and vendor price, minus the cost of its materials. Hover for the breakdown and its skill-up colors.
- **Leveling guide.** Click the book tab under your profession tabs. Type or slide a target skill and get a route from your current skill: what to craft and how many times (fail chance included), when to learn new recipes, and when to train the next rank.
- **Route styles.** Most profit, Fewest crafts or Balanced. Hover the selector to compare all three.
- **Where to learn recipes.** Trainers with names and zones, vendors, drops and quest rewards.
- **Shopping list.** Everything the route needs, minus what's in your bags and bank. Send it to Auctionator as a shopping list.
- **Plan to make.** Choose how many of a recipe you want. If you're short, a popup at the side of your screen lists what you still need and ticks items off as you get them.
- **Gathering guide.** Herbalism, Mining, Skinning and Fishing show where to go at each skill and what you'll find there, with values.

## Works with (optional)
- [Auctionator](https://www.curseforge.com/wow/addons/auctionator): auction prices and shopping lists. Recommended.
- Questie: vendors, drops, quests and trainers for each recipe.
- GatherMate2: sorts gathering zones by the nodes you've found.

Without them the addon uses vendor prices, and remembers trainers, vendors and prices as you visit them.

## Commands
- `/sage`: open or close the guide (with a profession open)
- `/sage profit`: show or hide profit next to recipes
- `/sage cut <percent>`: auction house cut used for profit (default 5)
- `/sage track` / `/sage clear`: show or stop the materials popup
- `/sage errors`: list errors the addon caught (for bug reports)

## Recipe data
Recipes, skill-up colors and materials are generated from the WoW Forever client's own data (`tools/build_data.py`). The skill needed for trainer recipes isn't in the client data, so it's estimated until you open that profession's trainer. The gathering guide follows the classic leveling zones.

## Install / update
Copy this folder to `World of Warcraft\_forever_\Interface\AddOns\ProfessionSage`.
If a client patch changes the interface version, update `## Interface:` in the .toc (`/dump select(4, GetBuildInfo())` in game).

## Updating the recipe data
`python tools/build_data.py <build>` downloads the client tables for that build from wago.tools and rewrites `Data.lua`.

## License
MIT
