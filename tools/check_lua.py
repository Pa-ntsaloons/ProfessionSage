"""Rough structure check for the addon's Lua files: block keywords
(function/if/do/repeat ... end/until) and brackets must balance.
Not a real compiler; it catches the common slip-ups before you load the game.

Usage: python tools/check_lua.py [files...]   (defaults to every .lua next to the .toc)
"""
import glob
import os
import re
import sys

TOKEN = re.compile(r"--\[(=*)\[.*?\]\1\]|--[^\n]*|\[(=*)\[.*?\]\2\]|\"(?:\\.|[^\"\\\n])*\"|'(?:\\.|[^'\\\n])*'"
                   r"|[A-Za-z_][A-Za-z0-9_]*|[(){}\[\]]|\n", re.S)
OPEN = {"function", "if", "do", "repeat"}
PAIRS = {")": "(", "}": "{", "]": "["}


def check(path):
    text = open(path, encoding="utf-8").read()
    stack, line, problems = [], 1, []
    for match in TOKEN.finditer(text):
        token = match.group(0)
        if token == "\n":
            line += 1
            continue
        if token.startswith("--") or token[0] in "\"'" or token.startswith("[[") or token.startswith("[="):
            line += token.count("\n")
            continue
        if token in OPEN:
            stack.append((token, line))
        elif token == "end":
            if not stack or stack[-1][0] not in ("function", "if", "do"):
                problems.append(f"line {line}: 'end' with nothing to close" + (f" (open: {stack[-1]})" if stack else ""))
            else:
                stack.pop()
        elif token == "until":
            if not stack or stack[-1][0] != "repeat":
                problems.append(f"line {line}: 'until' without 'repeat'")
            else:
                stack.pop()
        elif token in "({[":
            stack.append((token, line))
        elif token in ")}]":
            if not stack or stack[-1][0] != PAIRS[token]:
                problems.append(f"line {line}: unexpected '{token}'" + (f" (open: {stack[-1]})" if stack else ""))
            else:
                stack.pop()
    for token, at in stack:
        problems.append(f"line {at}: '{token}' never closed")
    return problems


def main():
    here = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    files = sys.argv[1:] or sorted(glob.glob(os.path.join(here, "*.lua")))
    bad = 0
    for path in files:
        problems = check(path)
        name = os.path.basename(path)
        if problems:
            bad += 1
            print(f"{name}: {len(problems)} problem(s)")
            for problem in problems[:10]:
                print("   ", problem)
        else:
            print(f"{name}: ok")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
