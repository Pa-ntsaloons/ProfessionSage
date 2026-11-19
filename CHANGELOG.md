# Changelog

## 2.2.1 — 2026-11-18

### Leveling guide
- Expert and Artisan steps now name the right trainers. Only a few NPCs teach these ranks (for example, Expert Alchemy is Ainethil in Darnassus or Doctor Herbert Halsey in Undercity); the guide used to list any trainer with "Expert" or "Artisan" in their title, but a title names one rank above what the trainer teaches.
- Rank steps show what you need (skill, character level and cost) and, when one trainer teaches it for your faction, their name. Click the step to set a waypoint.
- Mining trainers count as teaching every rank, so the Mining route no longer says no trainer was found.
- The guide button now sits next to the profession's link button at the top of the window instead of under the side tabs. On the professions overview it stays visible and opens your last profession with the guide.

## 2.2.0 — 2026-11-17

### Leveling guide
- First Aid and Cooking: the Expert and Artisan steps now say how you actually get them. Expert is a book to buy and read (Expert First Aid - Under Wraps, Expert Cookbook) and Artisan is a quest (Triage, Clamlette Surprise), with where to go for your faction. These used to say "Train" and found no trainers.
- Click one of those steps to set a waypoint to the NPC (map pin, plus a TomTom arrow if you have TomTom).

## 2.1.0 — 2026-11-17

### Leveling guide
- Materials you already have now count as paid for when the guide picks recipes, so after you buy a route's materials and level up, re-planning keeps using them instead of switching to a different recipe. Turn off **Count what I have** to plan at full prices.
- Route steps show the craft count before the recipe name ("12x Minor Healing Potion"), so it's no longer cut off.

### Recipe list
- New **Leveling route** option in the profession window's Filter menu: shows only the recipes the guide uses to reach your target, in the order to craft them, with how many of each in front of the name. Follows the guide's target and route style.

## 2.0.0 — 2026-11-17

Rebuilt from GatherProfitScanner as **Profession Sage**, for WoW Forever. Everything now lives inside Blizzard's own profession window.

### Profit on every recipe
- Profit or loss next to each recipe in the profession window, with a breakdown on hover.
- Sale value is the better of the auction price (after the AH cut) and the vendor price; materials use the cheaper of auction and vendor.
- Prices from Auctionator, built-in vendor prices for common reagents, and vendor prices learned at every merchant you visit.

### Leveling guide
- A book tab under your profession tabs opens a guide beside the window.
- Type or slide a target skill; the guide plans the route from your current skill: what to craft and how many times, when to learn new recipes, and when to train the next rank.
- Three route styles: **Most profit**, **Fewest crafts** and **Balanced**. Hover the selector to compare all three.
- Counts what you'll make back by selling what you craft, so routes are ranked by net cost (or profit).
- Fail chance is shown: each step splits where the recipe changes color and shows its skill-up chance.
- Where to get each recipe: trainers (with names and zones), vendors, drops, world drops and quest rewards. Uses Questie when installed and remembers trainers and vendors you visit.
- Shopping list with what you already have subtracted; send it to Auctionator as a shopping list.

### Plan to make
- Choose how many of a recipe you want, even more than you have materials for.
- If you're short, a small popup at the side of the screen lists what you still need and ticks items off as you get them. It stays up at the auction house and after a reload.

### Gathering guide
- Herbalism, Mining, Skinning and Fishing show where to go at each skill bracket for your faction, and what you'll gather or fish there with its value.
- Zones are sorted by the nodes you've found there when GatherMate2 is installed.
- Mining can switch between the gathering guide and a smelting route.

### Data
- Recipes, skill-up colors, materials and recipe skill requirements generated from the WoW Forever client's own data (build 1.60.1.70938).
- Trainer recipe requirements are estimated until you open that trainer, then exact.
- `/sage errors` lists any errors the addon caught, for bug reports.

## 1.0.2

GatherProfitScanner for Classic Era: values of gathered materials by profession level.
