-----------------------------------------
--                                     --
--  QuestMap based off of code from    --
--  Esohead by Zam Network and         --
--  HarvestMap by Shinni               --
--                                     --
-----------------------------------------

QuestMap = {}

-----------------------------------------
--           Core Functions            --
-----------------------------------------

function QuestMap.Initialize()
    QuestMap.savedVars = {}
    QuestMap.debugDefault = 0
    QuestMap.dataDefault = {
        data = {}
    }

    QuestMap.name = ""
    QuestMap.time = 0
    QuestMap.isHarvesting = false
    QuestMap.action = ""
    QuestMap.langs = { "en", "de", "fr", }
    QuestMap.currentConversation = {
        npcName = "",
        npcLevel = 0,
        x = 0,
        y = 0,
        subzone = ""
    }
    QuestMap.minDefault = 0.000025 -- 0.005^2
    QuestMap.minReticleover = 0.000049 -- 0.007^2
    QuestMap.questGiver = 0.000081 -- 0.009^2
end

function QuestMap.InitSavedVariables()
    QuestMap.savedVars = {
        ["internal"]     = ZO_SavedVars:NewAccountWide("QuestMap_SavedVariables", 1, "internal", { debug = QuestMap.debugDefault, language = "" }),
        ["quest"]        = ZO_SavedVars:NewAccountWide("QuestMap_SavedVariables", 1, "quest", QuestMap.dataDefault),
        ["progress"]     = ZO_SavedVars:New("QuestMap_SavedVariables", 1, "progress", QuestMap.dataDefault),
        ["mapnames"]     = ZO_SavedVars:NewAccountWide("QuestMap_SavedVariables", 1, "mapnames", QuestMap.dataDefault),
        ["harvestmap"]   = ZO_SavedVars:NewAccountWide("QuestMap_SavedVariables", 1, "harvestmap", QuestMap.dataDefault),
    }

    if QuestMap.savedVars["internal"].debug == 1 then
        QuestMap.Debug("QuestMap addon initialized. Debugging is enabled.")
    else
        QuestMap.Debug("QuestMap addon initialized. Debugging is disabled.")
    end
end

-- formats a number with commas on thousands
function QuestMap.NumberFormat(num)
    local formatted = num
    local k

    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then
            break
        end
    end

    return formatted
end

-- Listens for anything that is not event driven by the API but needs to be tracked
function QuestMap.OnUpdate(time)
    if IsGameCameraUIModeActive() or IsUnitInCombat("player") then
        return
    end

    local type = GetInteractionType()
    local active = IsPlayerInteractingWithObject()
    local x, y, textureName = QuestMap.GetUnitPosition("player")
    local targetType
    local action, name, interactionBlocked, additionalInfo, context = GetGameCameraInteractableActionInfo()

    local isHarvesting = ( active and (type == INTERACTION_HARVEST) )
    if not isHarvesting then
        if name then
            QuestMap.name = name -- QuestMap.name is the global current node
        end

        if QuestMap.isHarvesting and time - QuestMap.time > 1 then
            QuestMap.isHarvesting = false
        end

        if textureName ~= QuestMap.lastMap then
            if QuestMap.savedVars["internal"].debug == 1 then
                QuestMap.Debug(textureName)
            end
            QuestMap.saveMapName(textureName)
            QuestMap.lastMap = textureName
        end

        if action ~= QuestMap.action then
            QuestMap.action = action -- QuestMap.action is the global current action

        end
    else
        QuestMap.isHarvesting = true
        QuestMap.time = time

    end
end

-----------------------------------------
--             Map Data                --
-----------------------------------------
function QuestMap.checkDupeInfo(nodes, harvestMapName, data)
    for index, maps in pairs(nodes) do
        for _, map in pairs(maps) do
            if harvestMapName == index then
                if (data[1] == map[1]) and (data[2] == map[2]) and (data[3] == map[3]) then
                    return false
                end
            end
        end
    end
    return true
end

function QuestMap.checkDupeZoneNames(nodes, data)
    if nodes ~= nil then
        for index, maps in pairs(nodes) do
            if (data[1] == maps[1]) and (data[2] == maps[2]) and (data[3] == maps[3]) then
                return false
            end
        end
    end
    return true
end

function QuestMap.saveMapName(textureName)
    local worldMapName = GetUnitZone("player")
    local subzoneMapName = GetMapName()
    local locationMapName = GetPlayerLocationName()
    
    local harvestMapName = GetMapTileTexture()
    harvestMapName = string.lower(harvestMapName)
    harvestMapName = string.gsub(harvestMapName, "^.*maps/", "")
    harvestMapName = string.gsub(harvestMapName, "_%d+%.dds$", "")

    local world, subzone, location = select(3,textureName:find("([%w%-]+)/([_%w%-]+)/([_%w%-]+)"))
    
    -----------------------------------------
    --          Save QuestMap Name         --
    -----------------------------------------

    if not QuestMap.savedVars["mapnames"].data[world] then
        QuestMap.savedVars["mapnames"].data[world] = {}
    end

    if not QuestMap.savedVars["mapnames"].data[world][subzone] then
        QuestMap.savedVars["mapnames"].data[world][subzone] = {}
    end
    data = { worldMapName, subzoneMapName, locationMapName }

    if QuestMap.savedVars["mapnames"].data[world][subzone][location] == nil then
        QuestMap.savedVars["mapnames"].data[world][subzone][location] = {}
    end

    if QuestMap.checkDupeZoneNames(QuestMap.savedVars["mapnames"].data[world][subzone][location], data) then
        table.insert( QuestMap.savedVars["mapnames"].data[world][subzone][location], { worldMapName, subzoneMapName, locationMapName } )
    end
    -----------------------------------------
    --         Save HarvestMap Name        --
    -----------------------------------------
    data = { worldMapName, subzoneMapName, locationMapName }
    local savemapdata = QuestMap.checkDupeInfo(QuestMap.savedVars["harvestmap"].data, harvestMapName, data)

    if savemapdata then
        if QuestMap.savedVars["harvestmap"].data[harvestMapName] == nil then
            QuestMap.savedVars["harvestmap"].data[harvestMapName] = {}
        end

        table.insert( QuestMap.savedVars["harvestmap"].data[harvestMapName], data )
    end
end

-----------------------------------------
--            API Helpers              --
-----------------------------------------

function QuestMap.GetUnitPosition(tag)
    local setMap = SetMapToPlayerLocation() -- Fix for bug #23
    if setMap == 2 then
        CALLBACK_MANAGER:FireCallbacks("OnWorldMapChanged") -- Fix for bug #23
    end

    local x, y, a = GetMapPlayerPosition(tag)
    local textureName = GetMapTileTexture()
    textureName = string.lower(textureName)
    textureName = string.gsub(textureName, "^.*maps/", "")
    textureName = string.gsub(textureName, "_%d+%.dds$", "")
    textureName = string.gsub(textureName, "_base$", "")
    
    local location = GetPlayerLocationName()
    location = string.lower(location)
    location = string.gsub(location, "%s", "_")
    location = string.gsub(location, "\'", "")
    textureName = textureName .. "/" .. location
    
    return x, y, textureName
end

function QuestMap.contains(table, value)
    for key, v in pairs(table) do
        if v == value then
            return key
        end
    end
    return nil
end

function QuestMap.GetUnitName(tag)
    return GetUnitName(tag)
end

function QuestMap.GetUnitLevel(tag)
    return GetUnitLevel(tag)
end

function QuestMap.GetLootEntry(index)
    return GetLootItemInfo(index)
end

-----------------------------------------
--           Debug Logger              --
-----------------------------------------

local function EmitMessage(text)
    if(CHAT_SYSTEM)
    then
        if(text == "")
        then
            text = "[Empty String]"
        end

        CHAT_SYSTEM:AddMessage(text)
    end
end

local function EmitTable(t, indent, tableHistory)
    indent          = indent or "."
    tableHistory    = tableHistory or {}

    for k, v in pairs(t)
    do
        local vType = type(v)

        EmitMessage(indent.."("..vType.."): "..tostring(k).." = "..tostring(v))

        if(vType == "table")
        then
            if(tableHistory[v])
            then
                EmitMessage(indent.."Avoiding cycle on table...")
            else
                tableHistory[v] = true
                EmitTable(v, indent.."  ", tableHistory)
            end
        end
    end
end

function QuestMap.Debug(...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if(type(value) == "table")
        then
            EmitTable(value)
        else
            EmitMessage(tostring (value))
        end
    end
end

-----------------------------------------
--           Data Logging              --
-----------------------------------------

-----------------------------------------
--         Check Duplicate Data        --
-----------------------------------------
function QuestMap.questFound(type, map, x, y, questName )
    local world, subzone, location = select(3,map:find("([%w%-]+)/([_%w%-]+)/([_%w%-]+)"))

    -- If this check is not here the next routine will fail
    -- after the loading screen because for a brief moment
    -- the information is not available.
    if QuestMap.savedVars[type] == nil then
        return
    end

    if not QuestMap.savedVars[type].data[world] then
        return false
    end

    if not QuestMap.savedVars[type].data[world][subzone] then
        return false
    end

    if not QuestMap.savedVars[type].data[world][subzone][location] then
        return false
    end

    distance = QuestMap.questGiver

    for quest, quests in pairs( QuestMap.savedVars[type].data[world][subzone][location] ) do
        if quest == questName then
            if QuestMap.savedVars["internal"].debug == 1 then
                QuestMap.Debug("Questname : " .. questName .. " at : " .. map .. " x:" .. x .." , y:" .. y .. " found!")
            end
            return true
        end
    end
    if QuestMap.savedVars["internal"].debug == 1 then
        QuestMap.Debug("Questname : " .. questName .. " at : " .. map .. " x:" .. x .." , y:" .. y .. " not found!")
    end
    return false
end

function QuestMap.progressExists(type, questName, isPushed, isComplete, mainStepChanged, questLevel, npcLevel, expGained)

    -- If this check is not here the next routine will fail
    -- after the loading screen because for a brief moment
    -- the information is not available.
    if QuestMap.savedVars[type] == nil then
        return
    end

    if not QuestMap.savedVars[type].data[questName] then
        return false
    end

    for quest, quests in pairs( QuestMap.savedVars[type].data ) do
        for index, value in pairs(quests) do
            if quest == questName then
                if value[1] ~= isPushed then
                    value[1] = isPushed
                end
                if value[2] ~= isComplete then
                    value[2] = isComplete
                    if QuestMap.savedVars["internal"].debug == 1 then
                        QuestMap.Debug("Quest Complete!")
                    end
                end
                if value[3] ~= mainStepChanged then
                    value[3] = mainStepChanged
                end
                return true
            end
        end
    end
    if QuestMap.savedVars["internal"].debug == 1 then
        QuestMap.Debug("Quest progress : " .. questName .. " not found!")
    end
    return false
end

-----------------------------------------
--           Save Quest Data           --
-----------------------------------------

function QuestMap.saveQuestData(type, map, x, y, questName, npcName)
QuestMap.saveQuestData(
        targetType, 
        QuestMap.currentConversation.subzone, 
        QuestMap.currentConversation.x, 
        QuestMap.currentConversation.y, 
        questName, 
        QuestMap.currentConversation.npcName
    )


    local world, subzone, location = select(3,map:find("([%w%-]+)/([_%w%-]+)/([_%w%-]+)"))

    if QuestMap.savedVars[type] == nil or QuestMap.savedVars[type].data == nil then
        QuestMap.Debug("Attempted to log unknown type: " .. type)
        return
    end

    if QuestMap.questFound(type, map, x, y, questName ) then
        return
    end

    if QuestMap.savedVars[type] == nil then
        return
    end

    if not QuestMap.savedVars[type].data[world] then
        QuestMap.savedVars[type].data[world] = {}
    end

    if not QuestMap.savedVars[type].data[world][subzone] then
        QuestMap.savedVars[type].data[world][subzone] = {}
    end

    if not QuestMap.savedVars[type].data[world][subzone][location] then
        QuestMap.savedVars[type].data[world][subzone][location] = {}
    end

    if not QuestMap.savedVars[type].data[world][subzone][location][questName] then
        QuestMap.savedVars[type].data[world][subzone][location][questName] = {}
    end

    --if QuestMap.savedVars["internal"].debug == 1 then
    --end
    table.insert( QuestMap.savedVars[type].data[world][subzone][location][questName], { x, y, npcName } )
    if QuestMap.savedVars["internal"].debug == 1 then
        QuestMap.Debug("Quest data saved!")
    end
end

function QuestMap.updateQuestInfo(type, questName, isPushed, isComplete, mainStepChanged, questLevel, npcLevel, expGained)

    if QuestMap.savedVars[type] == nil or QuestMap.savedVars[type].data == nil then
        QuestMap.Debug("Attempted to log unknown type: " .. type)
        return
    end

    if QuestMap.progressExists(type, questName, isPushed, isComplete, mainStepChanged, questLevel, npcLevel, expGained) then
        return
    end

    -- If this check is not here the next routine will fail
    -- after the loading screen because for a brief moment
    -- the information is not available.
    if QuestMap.savedVars[type] == nil then
        return
    end

    if not QuestMap.savedVars[type].data[questName] then
        QuestMap.savedVars[type].data[questName] = {}
    end

    table.insert( QuestMap.savedVars[type].data[questName], { isPushed, isComplete, mainStepChanged } )
    if QuestMap.savedVars["internal"].debug == 1 then
        QuestMap.Debug("Quest progress saved!")
    end

end

function QuestMap.initQuestInfo(type, questName, isPushed, isComplete, mainStepChanged, questLevel, npcLevel, expGained)

    if QuestMap.savedVars[type] == nil or QuestMap.savedVars[type].data == nil then
        QuestMap.Debug("Attempted to log unknown type: " .. type)
        return
    end

    if QuestMap.progressExists( type, questName, isPushed, isComplete, mainStepChanged ) then
        return
    end

    -- If this check is not here the next routine will fail
    -- after the loading screen because for a brief moment
    -- the information is not available.
    if QuestMap.savedVars[type] == nil then
        return
    end

    if not QuestMap.savedVars[type].data[questName] then
        QuestMap.savedVars[type].data[questName] = {}
    end

    table.insert( QuestMap.savedVars[type].data[questName], { isPushed, isComplete, mainStepChanged, questLevel, npcLevel, expGained } )
    if QuestMap.savedVars["internal"].debug == 1 then
        QuestMap.Debug("Quest progress saved!")
    end

end

-----------------------------------------
--           Quest Tracking            --
-----------------------------------------

function QuestMap.OnQuestAdded(_, questIndex)
    -- This routine might need a check to make sure the player 
    -- obtained the quest by interacting with the NPC and that
    -- the quest was not shared by another player
    local questName = GetJournalQuestInfo(questIndex)
    local questLevel = GetJournalQuestLevel(questIndex)

    local targetType = "quest"

    if QuestMap.currentConversation.npcName == "" or QuestMap.currentConversation.npcName == nil then
        return
    end
    -- quests are not tracked when your reticle is over the quest giver
    -- however the NPC might move around, therefore range checking is needed

    QuestMap.saveQuestData(
        targetType, 
        QuestMap.currentConversation.subzone, 
        QuestMap.currentConversation.x, 
        QuestMap.currentConversation.y, 
        questName, 
        QuestMap.currentConversation.npcName
    )
    local expGained = 0 -- set to be updated upon completion
    QuestMap.initQuestInfo("progress", questName, isPushed, isComplete, mainStepChanged, questLevel, QuestMap.currentConversation.npcLevel, expGained)
end

function QuestMap.OnQuestAdvanced(_, questIndex, questName, isPushed, isComplete, mainStepChanged)
    local questLevel = GetJournalQuestLevel(questIndex)

    local targetType = "progress"
    
    QuestMap.updateQuestInfo(targetType, questName, isPushed, isComplete, mainStepChanged, questLevel, QuestMap.currentConversation.npcLevel, nil)
end

-----------------------------------------
--        Conversation Tracking        --
-----------------------------------------

function QuestMap.OnChatterBegin()
    local x, y, textureName = QuestMap.GetUnitPosition("player")
    local npcLevel = QuestMap.GetUnitLevel("interact")

    QuestMap.currentConversation.npcName = QuestMap.name
    QuestMap.currentConversation.npcLevel = npcLevel
    QuestMap.currentConversation.x = x
    QuestMap.currentConversation.y = y
    QuestMap.currentConversation.subzone = textureName
end

-----------------------------------------
--           Slash Command             --
-----------------------------------------

QuestMap.validCategories = {
    "quest",
    "progress",
    "mapnames",
    "harvestmap",
}

function QuestMap.IsValidCategory(name)
    for k, v in pairs(QuestMap.validCategories) do
        if string.lower(v) == string.lower(name) then
            return true
        end
    end

    return false
end

SLASH_COMMANDS["/quest"] = function (cmd)
    local commands = {}
    local index = 1
    for i in string.gmatch(cmd, "%S+") do
        if (i ~= nil and i ~= "") then
            commands[index] = i
            index = index + 1
        end
    end

    if #commands == 0 then
        return QuestMap.Debug("Please enter a valid QuestMap command")
    end

    if #commands == 2 and commands[1] == "debug" then
        if commands[2] == "on" then
            QuestMap.Debug("QuestMap debugger toggled on")
            QuestMap.savedVars["internal"].debug = 1
        elseif commands[2] == "off" then
            QuestMap.Debug("QuestMap debugger toggled off")
            QuestMap.savedVars["internal"].debug = 0
        end

    elseif commands[1] == "reset" then
        if #commands ~= 2 then 
            for type,sv in pairs(QuestMap.savedVars) do
                if type ~= "internal" then
                    QuestMap.savedVars[type].data = {}
                end
            end
            QuestMap.Debug("QuestMap saved data has been completely reset")
        else
            if commands[2] ~= "internal" then
                if QuestMap.IsValidCategory(commands[2]) then
                    QuestMap.savedVars[commands[2]].data = {}
                    QuestMap.Debug("QuestMap saved data : " .. commands[2] .. " has been reset")
                else
                    QuestMap.Debug("Please enter a valid QuestMap category to reset")
                    QuestMap.Debug("Catagoires are quest, progress, and mapnames.")
                    return
                end
            end
        end

    elseif commands[1] == "asdfghjkl" then
        QuestMap.Debug("---")
        QuestMap.Debug("Complete list of gathered data:")
        QuestMap.Debug("---")

        local counter = {
            ["npc"] = 0,
            ["quest"] = 0,
            ["progress"] = 0,
        }

        for type,sv in pairs(QuestMap.savedVars) do
            if type ~= "internal" then
                for zone, t1 in pairs(QuestMap.savedVars[type].data) do
                    for data, t2 in pairs(QuestMap.savedVars[type].data[zone]) do
                        counter[type] = counter[type] + #QuestMap.savedVars[type].data[zone][data]
                    end
                end
            end
        end

        QuestMap.Debug("Monster/NPCs: "     .. QuestMap.NumberFormat(counter["npc"]))
        QuestMap.Debug("Quests: "           .. QuestMap.NumberFormat(counter["quest"]))

        QuestMap.Debug("---")
    end
end

SLASH_COMMANDS["/rl"] = function()
    ReloadUI("ingame")
end

SLASH_COMMANDS["/reload"] = function()
    ReloadUI("ingame")
end

-----------------------------------------
--        Addon Initialization         --
-----------------------------------------

function QuestMap.OnLoad(eventCode, addOnName)
    if addOnName ~= "QuestMap" then
        return
    end

    QuestMap.language = (GetCVar("language.2") or "en")
    QuestMap.InitSavedVariables()
    QuestMap.savedVars["internal"]["language"] = QuestMap.language
    QuestMap.lastMap = ""

    EVENT_MANAGER:RegisterForEvent("QuestMap", EVENT_CHATTER_BEGIN, QuestMap.OnChatterBegin)
    EVENT_MANAGER:RegisterForEvent("QuestMap", EVENT_QUEST_ADDED, QuestMap.OnQuestAdded)
    EVENT_MANAGER:RegisterForEvent("QuestMap", EVENT_QUEST_ADVANCED, QuestMap.OnQuestAdvanced)
    
end

EVENT_MANAGER:RegisterForEvent("QuestMap", EVENT_ADD_ON_LOADED, function (eventCode, addOnName)
    if addOnName == "QuestMap" then
        QuestMap.Initialize()
        QuestMap.OnLoad(eventCode, addOnName)
    end
end)