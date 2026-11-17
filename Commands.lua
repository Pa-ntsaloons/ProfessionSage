local _, ns = ...

local function printHelp()
  ns.Print("commands:")
  print("  /sage - open the leveling guide (with a profession open)")
  print("  /sage profit - show or hide profit next to recipes")
  print("  /sage cut <percent> - auction house cut used for profit (now " .. ns.db.ahCut .. "%)")
  print("  /sage track - show the materials popup again")
  print("  /sage clear - stop tracking materials")
end

local commands = {}

function commands.profit()
  ns.db.showRowProfit = not ns.db.showRowProfit
  ns.Print("Profit next to recipes " .. (ns.db.showRowProfit and "shown." or "hidden."))
  if ns.RefreshRows then
    ns.RefreshRows()
  end
end

function commands.cut(value)
  local percent = tonumber(value)
  if not percent or percent < 0 or percent > 50 then
    return ns.Print("Usage: /sage cut 5")
  end
  ns.db.ahCut = percent
  ns.Print(string.format("Auction house cut set to %g%%.", percent))
  ns.Fire("PRICES_CHANGED")
end

function commands.track()
  if not ns.char.shopping then
    return ns.Print("Nothing is being tracked. Use \"Plan to make\" or the guide's Track materials button.")
  end
  ns.Tracker:Refresh()
end

function commands.clear()
  ns.Tracker:Clear()
end

function commands.errors()
  local errors = ns.db.errors or {}
  if #errors == 0 then
    return ns.Print("No errors recorded.")
  end
  ns.Print("recent errors (newest first):")
  for _, e in ipairs(errors) do
    local times = (e.count or 1) > 1 and string.format(" |cffa0a0a0(x%d)|r", e.count) or ""
    print(string.format("  |cffa0a0a0%s|r [%s] %s%s", e.when or "", e.where or "", e.message or "", times))
  end
end

function commands.clearerrors()
  ns.db.errors = {}
  ns.Print("Error list cleared.")
end

function commands.help()
  printHelp()
end

SLASH_PROFESSIONSAGE1 = "/sage"
SLASH_PROFESSIONSAGE2 = "/professionsage"
SlashCmdList.PROFESSIONSAGE = function(input)
  local command, argument = strtrim(input or ""):match("^(%S*)%s*(.-)$")
  command = (command or ""):lower()
  if command == "" then
    if ns.Panel and ProfessionsFrame and ProfessionsFrame:IsShown() then
      ns.Panel:Toggle()
    else
      ns.Print("Open a crafting profession, then click the book tab on the right of the window (or type /sage again).")
    end
    return
  end
  local handler = commands[command]
  if handler then
    handler(argument ~= "" and argument or nil)
  else
    printHelp()
  end
end
