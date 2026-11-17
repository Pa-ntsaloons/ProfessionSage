local _, ns = ...

local Prices = {}
ns.Prices = Prices

local function api()
  return Auctionator and Auctionator.API and Auctionator.API.v1
end

function Prices.HasAuctionator()
  local v1 = api()
  return v1 ~= nil and type(v1.GetAuctionPriceByItemID) == "function"
end

-- Last scanned auction price, or nil.
function Prices.Auction(item)
  local v1 = api()
  if not item or not v1 or not v1.GetAuctionPriceByItemID then
    return nil
  end
  local ok, price = pcall(v1.GetAuctionPriceByItemID, ns.CALLER, item)
  if ok and type(price) == "number" and price > 0 then
    return price
  end
end

-- Days since the auction price was seen, or nil.
function Prices.AuctionAge(item)
  local v1 = api()
  if not item or not v1 or not v1.GetAuctionAgeByItemID then
    return nil
  end
  local ok, age = pcall(v1.GetAuctionAgeByItemID, ns.CALLER, item)
  return ok and type(age) == "number" and age or nil
end

-- Price at a vendor that always sells it, or nil.
function Prices.Vendor(item)
  return (ns.db and ns.db.vendorPrices[item]) or ns.VENDOR_PRICES[item]
end

-- Cheapest way to buy one: returns copper, "vendor" / "auction"; nil if unknown.
function Prices.Buy(item)
  local vendor, auction = Prices.Vendor(item), Prices.Auction(item)
  if vendor and (not auction or vendor <= auction) then
    return vendor, "vendor"
  end
  if auction then
    return auction, "auction"
  end
end

-- What one sells for: the better of the auction price (after the AH cut) and
-- the vendor price. Returns copper, "auction" / "vendor"; nil if unknown.
function Prices.Sell(item)
  if not item then
    return nil
  end
  local auction = Prices.Auction(item)
  auction = auction and auction * (1 - (ns.db.ahCut or 5) / 100)
  local vendor = select(11, ns.GetItemInfo(item))
  vendor = vendor and vendor > 0 and vendor or nil
  if auction and (not vendor or auction >= vendor) then
    return auction, "auction"
  end
  if vendor then
    return vendor, "vendor"
  end
end

-- What one craft of a recipe sells back for (0 when nothing sellable).
function Prices.Resale(recipe)
  if not recipe.item then
    return 0
  end
  local each = Prices.Sell(recipe.item)
  return each and each * recipe.count or 0
end

-- Material cost of one craft. Returns cost (nil if any reagent is unpriced)
-- and the list of reagents with no price.
function Prices.CraftCost(recipe)
  local total, missing = 0, nil
  for _, reagent in ipairs(recipe.reagents) do
    local price = Prices.Buy(reagent.item)
    if price then
      total = total + price * reagent.count
    else
      missing = missing or {}
      table.insert(missing, reagent.item)
    end
  end
  if missing then
    return nil, missing
  end
  return total
end

-- Profit of one craft: { value, cost, profit, sellSource } or nil when the
-- recipe makes nothing sellable or a price is missing.
function Prices.Profit(recipe)
  if not recipe.item then
    return nil
  end
  local cost = Prices.CraftCost(recipe)
  local each, source = Prices.Sell(recipe.item)
  if not cost or not each then
    return nil
  end
  local value = each * recipe.count
  return { value = value, cost = cost, profit = value - cost, source = source }
end

--------------------------------------------------------------------------------
-- Learn vendor prices at merchants (only for crafting reagents)
--------------------------------------------------------------------------------

local reagentSet
local function isReagent(item)
  if not reagentSet then
    reagentSet = {}
    for _, rows in pairs(ns.RECIPES) do
      for _, row in ipairs(rows) do
        for id in row[7]:gmatch("(%d+):") do
          reagentSet[tonumber(id)] = true
        end
      end
    end
  end
  return reagentSet[item]
end

local function merchantItem(index)
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local info = C_MerchantFrame.GetItemInfo(index)
    if info then
      return info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
    end
  elseif GetMerchantItemInfo then
    local _, _, price, quantity, numAvailable, _, _, extendedCost = GetMerchantItemInfo(index)
    return price, quantity, numAvailable, extendedCost
  end
end

local function learnMerchant()
  if not ns.db or not GetMerchantNumItems or not GetMerchantItemID then
    return
  end
  local learned = false
  for index = 1, GetMerchantNumItems() do
    local item = GetMerchantItemID(index)
    local price, stack, available, extendedCost = merchantItem(index)
    -- Unlimited supply, plain gold price.
    if item and isReagent(item) and price and price > 0 and available == -1 and not extendedCost then
      local each = math.floor(price / math.max(1, stack or 1) + 0.5)
      if ns.db.vendorPrices[item] ~= each then
        ns.db.vendorPrices[item] = each
        learned = true
      end
    end
  end
  if learned then
    ns.Fire("PRICES_CHANGED")
  end
end

local queueMerchant = ns.Debounce(learnMerchant, 0.5)
ns.On("MERCHANT_SHOW", queueMerchant)
ns.On("MERCHANT_UPDATE", queueMerchant)

ns.Listen("LOGIN", function()
  local v1 = api()
  if v1 and type(v1.RegisterForDBUpdate) == "function" then
    pcall(v1.RegisterForDBUpdate, ns.CALLER, ns.Debounce(function() ns.Fire("PRICES_CHANGED") end, 1))
  end
end)

--------------------------------------------------------------------------------
-- Auctionator shopping list
--------------------------------------------------------------------------------

-- items: list of { item, count }. Returns true when the list was created.
function Prices.SendShoppingList(name, items)
  local v1 = api()
  if not v1 or type(v1.CreateShoppingList) ~= "function" then
    return false, "Auctionator isn't installed or doesn't support shopping lists."
  end
  local searchStrings = {}
  for _, entry in ipairs(items) do
    local itemName = ns.ItemName(entry.item)
    if itemName then
      local term = { searchString = itemName, isExact = true, quantity = entry.count }
      local ok, searchString = pcall(v1.ConvertToSearchString, ns.CALLER, term)
      table.insert(searchStrings, ok and searchString or ('"' .. itemName .. '"'))
    end
  end
  if #searchStrings == 0 then
    return false, "Nothing to buy."
  end
  local ok, err = pcall(v1.CreateShoppingList, ns.CALLER, name, searchStrings)
  if not ok then
    return false, tostring(err)
  end
  return true
end
