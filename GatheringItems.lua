-- GatheringItems.lua
GatherProfitScannerItems = {

     --Herbalism Profession Items
    ["Herbalism"] = {
        { itemID = 2447, name = "Peacebloom", requiredLevel = 1 },
        { itemID = 765, name = "Silverleaf", requiredLevel = 1 },
        { itemID = 2449, name = "Earthroot", requiredLevel = 15 },
        { itemID = 2450, name = "Briarthorn", requiredLevel = 70 },
        { itemID = 2453, name = "Bruiseweed", requiredLevel = 100 },
        { itemID = 2452, name = "Swiftthistle", requiredLevel = 50 },
        { itemID = 3355, name = "Wild Steelbloom", requiredLevel = 115 },
        { itemID = 3369, name = "Grave Moss", requiredLevel = 120 },
        { itemID = 3356, name = "Kingsblood", requiredLevel = 125 },
        { itemID = 3357, name = "Liferoot", requiredLevel = 150 },
        { itemID = 3818, name = "Fadeleaf", requiredLevel = 160 },
        { itemID = 3820, name = "Stranglekelp", requiredLevel = 85 },
        { itemID = 3819, name = "Dragon's Teeth", requiredLevel = 195 },
        { itemID = 3821, name = "Goldthorn", requiredLevel = 170 },
        { itemID = 8831, name = "Purple Lotus", requiredLevel = 210 },
        { itemID = 8838, name = "Sungrass", requiredLevel = 230 },
        { itemID = 8839, name = "Blindweed", requiredLevel = 235 },
        { itemID = 8845, name = "Ghost Mushroom", requiredLevel = 245 },
        { itemID = 8846, name = "Gromsblood", requiredLevel = 250 },
        { itemID = 13464, name = "Golden Sansam", requiredLevel = 260 },
        { itemID = 13463, name = "Dreamfoil", requiredLevel = 270 },
        { itemID = 13465, name = "Mountain Silversage", requiredLevel = 280 },
        { itemID = 13466, name = "Plaguebloom", requiredLevel = 285 },
        { itemID = 13467, name = "Icecap", requiredLevel = 290 },
        { itemID = 13468, name = "Black Lotus", requiredLevel = 300 },
    },
  
    --Mining Profession Items
    ["Mining"] = {
        { itemID = 2770, name = "Copper Ore", requiredLevel = 1 },
        { itemID = 2771, name = "Tin Ore", requiredLevel = 65 },
        { itemID = 2836, name = "Coarse Stone", requiredLevel = 75 },
        { itemID = 2772, name = "Iron Ore", requiredLevel = 125 },
        { itemID = 2838, name = "Heavy Stone", requiredLevel = 125 },
        { itemID = 7912, name = "Solid Stone", requiredLevel = 175 },
        { itemID = 3858, name = "Mithril Ore", requiredLevel = 175 },
        { itemID = 7911, name = "Truesilver Ore", requiredLevel = 230 },
        { itemID = 10620, name = "Thorium Ore", requiredLevel = 245 },
        { itemID = 12365, name = "Dense Stone", requiredLevel = 250 },
        { itemID = 11370, name = "Dark Iron Ore", requiredLevel = 230 },
        { itemID = 11754, name = "Black Diamond", requiredLevel = 250 },
        { itemID = 18567, name = "Elemental Flux", requiredLevel = 1 },
        { itemID = 774, name = "Malachite", requiredLevel = 1 },
        { itemID = 818, name = "Tigerseye", requiredLevel = 1 },
        { itemID = 1210, name = "Shadowgem", requiredLevel = 50 },
        { itemID = 1705, name = "Lesser Moonstone", requiredLevel = 125 },
        { itemID = 3864, name = "Citrine", requiredLevel = 175 },
        { itemID = 7910, name = "Star Ruby", requiredLevel = 250 },
    },

    -- Fishing Profession Items
    ["Fishing"] = {
        --Required Level #1
        { itemID = 6291, name = "Raw Longjaw Mud Snapper", requiredLevel = 1 },
        { itemID = 6308, name = "Raw Slitherskin Mackerel", requiredLevel = 1 },
        { itemID = 6303, name = "Raw Slitherskin Tuna", requiredLevel = 1 },
        { itemID = 6289, name = "Raw Brilliant Smallfish", requiredLevel = 1 },
        { itemID = 5498, name = "Small Lustrous Pearl", requiredLevel = 1 },

        -- Requred Level #50
        { itemID = 6361, name = "Raw Rainbow Fin Albacore", requiredLevel = 50 },
        { itemID = 5503, name = "Clam Meat", requiredLevel = 50 },

        --Required Level #55
        { itemID = 6358, name = "Oily Blackmouth", requiredLevel = 55 },
        { itemID = 6359, name = "Firefin Snapper", requiredLevel = 55 },
        { itemID = 6522, name = "Deviate Fish", requiredLevel = 55 },
       
        --Required Level #85
        { itemID = 21071, name = "Raw Sagefish", requiredLevel = 85 },

        --Required Level #100
        { itemID = 5500, name = "Iridescent Pearl", requiredLevel = 100 },
       
        -- Required Level #125
        { itemID = 5504, name = "Tangy Clam Meat", requiredLevel = 125 },
       
        -- Required Level #130
        { itemID = 6362, name = "Raw Rockscale Cod", requiredLevel = 130 },
       
        -- Required Level #175
        { itemID = 8365, name = "Raw Mithril Head Trout", requiredLevel = 175 },
        { itemID = 7974, name = "Zesty Clam Meat", requiredLevel = 175 },
        { itemID = 21153, name = "Raw Greater Sagefish", requiredLevel = 175 },
        { itemID = 7971, name = "Black Pearl", requiredLevel = 175 },
  
        -- Required Level #205
        { itemID = 13758, name = "Raw Redgill", requiredLevel = 205 },
        { itemID = 13760, name = "Raw Sunscale Salmon", requiredLevel = 205 },
        { itemID = 13756, name = "Raw Summer Bass", requiredLevel = 205 },
        { itemID = 4603, name = "Raw Spotted Yellowtail", requiredLevel = 205 },
        { itemID = 13755, name = "Winter Squid", requiredLevel = 205 },
        { itemID = 13422, name = "Stonescale Eel", requiredLevel = 205 },
       
        -- Required Level #225
        { itemID = 13754, name = "Raw Glossy Mightfish", requiredLevel = 225 },
       
        -- Required Level #275
        { itemID = 13893, name = "Large Raw Mightfish", requiredLevel = 275 },
        { itemID = 13759, name = "Raw Nightfin Snapper", requiredLevel = 275 },
        { itemID = 13889, name = "Raw Whitescale Salmon", requiredLevel = 275 },
        { itemID = 13929, name = "Raw Rockscale Cod", requiredLevel = 275 },
        { itemID = 13888, name = "Darkclaw Lobster", requiredLevel = 275 },
        { itemID = 13926, name = "Golden Pearl", requiredLevel = 275 },
    
    },

    --Skinning Profession Items
    ["Skinning"] = {
        { itemID = 2934, name = "Ruined Leather Scraps", requiredLevel = 1 },
        { itemID = 2318, name = "Light Leather", requiredLevel = 1 },
        { itemID = 783, name = "Light Hide", requiredLevel = 10 },
        { itemID = 2319, name = "Medium Leather", requiredLevel = 100 },
        { itemID = 4232, name = "Medium Hide", requiredLevel = 100 },
        { itemID = 4304, name = "Heavy Leather", requiredLevel = 150 },
        { itemID = 4235, name = "Heavy Hide", requiredLevel = 150 },
        { itemID = 8170, name = "Rugged Leather", requiredLevel = 250 },
        { itemID = 8171, name = "Rugged Hide", requiredLevel = 250 },
        { itemID = 15423, name = "Chimera Leather", requiredLevel = 225 }, -- From chimeras
        { itemID = 15422, name = "Frostsaber Leather", requiredLevel = 275 }, -- Winterspring
        { itemID = 15419, name = "Warbear Leather", requiredLevel = 275 }, -- High-level bears
        { itemID = 15415, name = "Blue Dragonscale", requiredLevel = 275 }, -- Dragonkin
        { itemID = 15414, name = "Red Dragonscale", requiredLevel = 300 }, -- Rare dragonkin
        { itemID = 15416, name = "Black Dragonscale", requiredLevel = 300 }, -- Blackrock Depths dragons
        { itemID = 15417, name = "Devilsaur Leather", requiredLevel = 300 }, -- Un'Goro Crater
        { itemID = 17012, name = "Core Leather", requiredLevel = 300 }, -- Molten Core hounds
        { itemID = 15412, name = "Green Dragonscale", requiredLevel = 275 }, -- Swamp of Sorrows
        { itemID = 8150, name = "Deeprock Salt", requiredLevel = 175 }, -- From certain beasts
        { itemID = 8165, name = "Worn Dragonscale", requiredLevel = 200 }, -- Low drop chance
        { itemID = 7286, name = "Black Whelp Scale", requiredLevel = 50 }, -- Redridge whelps
        { itemID = 7392, name = "Green Whelp Scale", requiredLevel = 175 }, -- Swamp of Sorrows
        { itemID = 6470, name = "Deviate Scale", requiredLevel = 75 }, -- Wailing Caverns
        { itemID = 6471, name = "Perfect Deviate Scale", requiredLevel = 100 }, -- Wailing Caverns
    },
}
