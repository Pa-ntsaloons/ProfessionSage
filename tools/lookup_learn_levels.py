"""Walks through the recipes whose learn level is still a guess, opens each one's
WoW Forever page on Wowhead in your browser, and saves the level you type into
learn_levels.csv. Nothing is downloaded: you read the page, the script does the
bookkeeping.

Usage:  python tools/lookup_learn_levels.py [--profession NAME] [--from SKILL] [--rebuild]

  --profession  only this profession, e.g. "First Aid" or tailoring
  --from        start at recipes learned around this skill or higher
  --rebuild     run build_data.py when you finish, so Data.lua picks up the levels

At each recipe, type:
  a number   the skill the trainer needs to teach it (saved right away)
  r          it's been removed from the game (left out of the addon's data)
  n          no level stated anywhere: keep the addon's guess, don't ask again
  Enter      skip it for now
  o          open the page again
  u          undo the last level you saved
  q          quit (run again any time: saved recipes aren't asked again)
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import webbrowser

import learn_data
from learn_data import REMOVED, UNKNOWN, read_rows, write_rows

HERE = learn_data.HERE
MAX_SKILL = 300


def spell_names():
    names = learn_data.spell_names()
    if not names:
        sys.exit(f"Missing {learn_data.spell_names_path()}. Run tools/build_data.py once to download the game data.")
    return names


def guessed_recipes(names, saved):
    """Recipes in Data.lua whose learn level is an estimate and isn't saved yet."""
    done = {row["recipe_spell"] for row in saved}
    return [dict(recipe, name=names.get(recipe["spell"], "?")) for recipe in learn_data.data_recipes()
            if not recipe["exact"] and recipe["spell"] not in done]


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def page(recipe):
    return f"https://www.wowhead.com/forever/spell={recipe['spell']}/{slug(recipe['name'])}#recipes"


# Chromium browsers can run in a window of their own (a separate profile), which
# the script can close when you move on. Your normal browser is left alone.
CHROMIUM = ["brave.exe", "chrome.exe", "msedge.exe", "chromium.exe"]
CHROMIUM_UNIX = ["brave-browser", "google-chrome", "chromium", "chromium-browser", "microsoft-edge"]
PROFILE = os.path.join(tempfile.gettempdir(), "ProfessionSageLookup")


def find_chromium():
    if sys.platform == "win32":
        import winreg
        for exe in CHROMIUM:
            for root in (winreg.HKEY_CURRENT_USER, winreg.HKEY_LOCAL_MACHINE):
                try:
                    with winreg.OpenKey(root, rf"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\{exe}") as key:
                        path = winreg.QueryValue(key, None)
                        if path and os.path.exists(path):
                            return path
                except OSError:
                    pass
    for exe in CHROMIUM_UNIX:
        path = shutil.which(exe)
        if path:
            return path
    return None


class Browser:
    """Shows one page at a time: opening a page closes the one before it."""

    def __init__(self):
        self.exe = find_chromium()
        self.process = None
        if not self.exe:
            print("No Chrome, Edge or Brave found: pages open in your normal browser and stay open.\n")

    def open(self, url):
        if not self.exe:
            webbrowser.open(url)
            return
        self.close()
        self.process = subprocess.Popen(
            [self.exe, f"--user-data-dir={PROFILE}", "--no-first-run", "--no-default-browser-check",
             "--new-window", url],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def close(self):
        if not self.process or self.process.poll() is not None:
            self.process = None
            return
        # Ask the window to close first, so the browser saves its cookies
        # (including a passed captcha); force it only if it doesn't.
        if sys.platform == "win32":
            subprocess.run(["taskkill", "/PID", str(self.process.pid)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            self.process.terminate()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            if sys.platform == "win32":
                subprocess.run(["taskkill", "/PID", str(self.process.pid), "/T", "/F"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            else:
                self.process.kill()
        self.process = None


def ask_level(recipe, browser):
    """Returns a skill level, REMOVED, None to skip, or a command string ('u', 'q')."""
    while True:
        answer = input("  learned at> ").strip().lower()
        if answer == "":
            return None
        if answer in ("q", "u"):
            return answer
        if answer == "r":
            return REMOVED
        if answer == "n":
            return UNKNOWN
        if answer == "o":
            browser.open(page(recipe))
            continue
        if not answer.isdigit() or not 1 <= int(answer) <= MAX_SKILL:
            print(f"  Type a skill from 1 to {MAX_SKILL}, r if it's removed, n if no level is stated, "
                  "Enter to skip, o, u or q.")
            continue
        level = int(answer)
        if level > recipe["yellow"]:
            confirm = input(f"  {level} is above where it turns yellow ({recipe['yellow']}). Save anyway? [y/N] ")
            if confirm.strip().lower() != "y":
                continue
        return level


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--profession", help='only this profession, e.g. "First Aid"')
    parser.add_argument("--from", dest="start", type=int, default=0, help="start at this skill")
    parser.add_argument("--rebuild", action="store_true", help="rebuild Data.lua when done")
    args = parser.parse_args()

    saved = read_rows()
    todo = guessed_recipes(spell_names(), saved)
    if args.profession:
        wanted = args.profession.lower()
        todo = [r for r in todo if r["profession"].lower() == wanted]
    todo = [r for r in todo if r["learn"] >= args.start]
    if not todo:
        print("Nothing to look up for that selection.")
        return

    print(f"{len(todo)} recipes to look up. r marks one removed, n means no level is stated, "
          "Enter skips, o reopens the page, u undoes, q quits.\n")
    browser = Browser()
    try:
        added = lookup(todo, saved, browser)
    finally:
        browser.close()

    print(f"\nSaved {len(added)} learn level(s) to {os.path.normpath(learn_data.LEARN_LEVELS)}.")
    if added and args.rebuild:
        subprocess.run([sys.executable, os.path.join(HERE, "build_data.py")], check=True)
    elif added:
        print("Run python tools/build_data.py to put them into Data.lua.")


def lookup(todo, saved, browser):
    """Asks for each recipe in turn; returns the rows saved this session."""
    added = []
    for index, recipe in enumerate(todo, 1):
        print(f"[{index}/{len(todo)}] {recipe['profession']}: {recipe['name']}  "
              f"(guess {recipe['learn']}, yellow {recipe['yellow']}, grey {recipe['grey']})")
        print("  " + page(recipe))
        browser.open(page(recipe))
        while True:
            level = ask_level(recipe, browser)
            if level == "u":
                if added:
                    undone = added.pop()
                    saved = [row for row in saved if row["recipe_spell"] != undone["recipe_spell"]]
                    write_rows(saved)
                    print(f"  Removed {undone['name']} ({undone['skill']}).")
                else:
                    print("  Nothing to undo this session.")
                continue
            break
        if level == "q":
            break
        if level is None:
            continue
        row = {"recipe_spell": recipe["spell"], "skill": str(level), "name": recipe["name"],
               "source": f"wowhead.com/forever/spell={recipe['spell']} (looked up by hand)"}
        saved.append(row)
        added.append(row)
        write_rows(saved)
        if level == REMOVED:
            print(f"  Saved {recipe['name']} as removed.")
        elif level == UNKNOWN:
            print(f"  Saved {recipe['name']} as no stated level (keeps the guess).")
        else:
            print(f"  Saved {recipe['name']} at {level}.")
    return added


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        print("\nStopped. Everything typed so far is saved.")
