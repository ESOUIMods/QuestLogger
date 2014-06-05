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
        ["npc"]          = ZO_SavedVars:NewAccountWide("QuestMap_SavedVariables", 1, "npc", QuestMap.dataDefault),
        ["quest"]        = ZO_SavedVars:NewAccountWide("QuestMap_SavedVariables", 1, "quest", QuestMap.dataDefault),
        ["progress"]     = ZO_SavedVars:NewAccountWide("QuestMap_SavedVariables", 1, "progress", QuestMap.dataDefault),
    }

    if QuestMap.savedVars["internal"].debug == 1 then
        QuestMap.Debug("QuestMap addon initialized. Debugging is enabled.")
    else
        QuestMap.Debug("QuestMap addon initialized. Debugging is disabled.")
    end
end

-- Logs saved variables
function QuestMap.Log(type, nodes, ...)
    local data = {}
    local dataStr = ""
    local sv

    if QuestMap.savedVars[type] == nil or QuestMap.savedVars[type].data == nil then
        QuestMap.Debug("Attempted to log unknown type: " .. type)
        return
    else
        sv = QuestMap.savedVars[type].data
    end

    for i = 1, #nodes do
        local node = nodes[i];
        if string.find(node, '\"') then
            node = string.gsub(node, '\"', '\'')
        end

        if sv[node] == nil then
            sv[node] = {}
        end
        sv = sv[node]
    end

    for i = 1, select("#", ...) do
        local value = select(i, ...)
        data[i] = value
        dataStr = dataStr .. "[" .. tostring(value) .. "] "
    end

    if QuestMap.savedVars["internal"].debug == 1 then
        QuestMap.Debug("Logged [" .. type .. "] data: " .. dataStr)
    end

    if #sv == 0 then
        sv[1] = data
    else
        sv[#sv+1] = data
    end
end

-- Checks if we already have an entry for the object/npc within a certain x/y distance
function QuestMap.LogCheck(type, nodes, x, y, scale, name)
    local log = true
    local sv

    local distance
    if scale == nil then
        distance = QuestMap.minDefault
    else
        distance = scale
    end

    if QuestMap.savedVars[type] == nil or QuestMap.savedVars[type].data == nil then
        return nil
    else
        sv = QuestMap.savedVars[type].data
    end

    for i = 1, #nodes do
        local node = nodes[i];
        if string.find(node, '\"') then
            node = string.gsub(node, '\"', '\'')
        end

        if sv[node] == nil then
            sv[node] = {}
        end
        sv = sv[node]
    end

    for i = 1, #sv do
        local item = sv[i]

        dx = item[1] - x
        dy = item[2] - y
        -- (x - center_x)2 + (y - center_y)2 = r2, where center is the player
        dist = math.pow(dx, 2) + math.pow(dy, 2)
        -- both ensure that the entire table isn't parsed
        if dist < distance then -- near player location
            if name == nil then -- npc, quest, vendor all but harvesting
                return false
            else -- harvesting only
                if item[4] == name then
                    return false
                elseif item[4] ~= name then
                    return true
                end
            end
        end
    end

    return log
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

        if action ~= QuestMap.action then
            QuestMap.action = action -- QuestMap.action is the global current action

        end
    else
        QuestMap.isHarvesting = true
        QuestMap.time = time

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

function QuestMap.progressExists(type, questName, isPushed, isComplete, mainStepChanged)

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
                if QuestMap.savedVars["internal"].debug == 1 then
                    QuestMap.Debug("Quest progress : " .. questName .. " found!")
                end
                if value[1] ~= isPushed then
                    value[1] = isPushed
                    if QuestMap.savedVars["internal"].debug == 1 then
                        QuestMap.Debug("Quest progress : " .. questName .. " isPushed updated!")
                        QuestMap.Debug(value[1])
                    end
                end
                if value[2] ~= isComplete then
                    value[2] = isComplete
                    if QuestMap.savedVars["internal"].debug == 1 then
                        QuestMap.Debug("Quest progress : " .. questName .. " isComplete updated!")
                        QuestMap.Debug(value[2])
                    end
                end
                if value[3] ~= mainStepChanged then
                    value[3] = mainStepChanged
                    if QuestMap.savedVars["internal"].debug == 1 then
                        QuestMap.Debug("Quest progress : " .. questName .. " mainStepChanged updated!")
                        QuestMap.Debug(value[3])
                    end
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

function QuestMap.saveQuestData(type, map, x, y, questName, questLevel, npcName, npcLevel)
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
    table.insert( QuestMap.savedVars[type].data[world][subzone][location][questName], { x, y, questLevel, npcName, npcLevel } )
    if QuestMap.savedVars["internal"].debug == 1 then
        QuestMap.Debug("Quest data saved!")
    end
end

function QuestMap.saveQuestProgress(type, questName, isPushed, isComplete, mainStepChanged)

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

    table.insert( QuestMap.savedVars[type].data[questName], { isPushed, isComplete, mainStepChanged } )
    if QuestMap.savedVars["internal"].debug == 1 then
        QuestMap.Debug("Quest progress savedSave data!")
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
        questLevel, 
        QuestMap.currentConversation.npcName,
        QuestMap.currentConversation.npcLevel
    )
end

function QuestMap.OnQuestAdvanced(_, questIndex, questName, isPushed, isComplete, mainStepChanged)

    local targetType = "progress"

    QuestMap.saveQuestProgress(targetType, questName, isPushed, isComplete, mainStepChanged)
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
--        Better NPC Tracking          --
-----------------------------------------

-- Fired when the reticle hovers a new target
function QuestMap.OnTargetChange(eventCode)
    local tag = "reticleover"
    local type = GetUnitType(tag)
    local targetType = "npc"

    -- ensure the unit that the reticle is hovering is a non-playing character
    if type == 2 then
        local name = QuestMap.GetUnitName(tag)
        local x, y, textureName = QuestMap.GetUnitPosition(tag)

        if name == nil or name == "" or x <= 0 or y <= 0 then
            return
        end

        local level = QuestMap.GetUnitLevel(tag)

        if QuestMap.LogCheck(dataType, {world, subzone, location, nodeName}, x, y, QuestMap.minReticleover, nil) then
                QuestMap.Log(dataType, {world, subzone, location, nodeName}, x, y, level)
        end
    end
end

-----------------------------------------
--           Slash Command             --
-----------------------------------------

QuestMap.validCategories = {
    "quest",
    "npc",
    "progress",
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
                    QuestMap.Debug("valid catagoires are chest, fish, book, vendor,") 
                    QuestMap.Debug("quest, harvest, npc, and skyshard.")
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

    --EVENT_MANAGER:RegisterForEvent("QuestMap", EVENT_RETICLE_TARGET_CHANGED, QuestMap.OnTargetChange)
    EVENT_MANAGER:RegisterForEvent("QuestMap", EVENT_CHATTER_BEGIN, QuestMap.OnChatterBegin)
    EVENT_MANAGER:RegisterForEvent("QuestMap", EVENT_QUEST_ADDED, QuestMap.OnQuestAdded)
    EVENT_MANAGER:RegisterForEvent("QuestMap", EVENT_QUEST_ADVANCED, QuestMap.OnQuestAdvanced)
    --EVENT_MANAGER:RegisterForEvent("QuestMap", EVENT_QUEST_COMPLETE_EXPERIENCE, QuestMap.OnExperenceGained)
    
end

EVENT_MANAGER:RegisterForEvent("QuestMap", EVENT_ADD_ON_LOADED, function (eventCode, addOnName)
    if addOnName == "QuestMap" then
        QuestMap.Initialize()
        QuestMap.OnLoad(eventCode, addOnName)
    end
end)