--[[
 *  The MIT License (MIT)
 *
 *  Copyright (c) 2016 Sjshovan (Apogee)
 *
 *  Permission is hereby granted, free of charge, to any person obtaining a copy
 *  of this software and associated documentation files (the "Software"), to
 *  deal in the Software without restriction, including without limitation the
 *  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 *  sell copies of the Software, and to permit persons to whom the Software is
 *  furnished to do so, subject to the following conditions:
 *
 *  The above copyright notice and this permission notice shall be included in
 *  all copies or substantial portions of the Software.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 *  DEALINGS IN THE SOFTWARE.
]]--

_addon.author   = 'Sjshovan (Apogee)';
_addon.name     = 'AmmoWatch';
_addon.version  = '0.1.2';

require 'common'
require 'timer'
require 'mathex'

---------------------------------------------------------------------------------------------------
-- desc: Default AmmoWatch configuration table.
---------------------------------------------------------------------------------------------------
local default_config =
{
    every_count = 1;
    every_uses = 0;
};

---------------------------------------------------------------------------------------------------
-- desc: AmmoWatch variables.
---------------------------------------------------------------------------------------------------
local ammo_watch_config = default_config;

local _core =  AshitaCore;

local _resource = _core:GetResourceManager();
local _chat =  _core:GetChatManager();
local _data =  _core:GetDataManager();
local _party = _data:GetParty();
local _player = _data:GetPlayer();
local _inventory = _data:GetInventory();
local _target = _data:GetTarget();
local _entity = _data:GetEntity();

local last_mode = nil;

local chatModes = {
    say         = 1,
    shout       = 3,
    tell        = 4,
    party       = 5,
    linkshell   = 6,
    echo        = 206,
    unity       = 211,
    danger      = 39,
    linkshell2  = 204,
    info        = 207,
    combatInfo  = 36,
    combatInfo2 = 37
}

local helpCmds = {
    "======================",
    "AmmoWatch Commands",
    "======================",
	"/aw get => Display current count of equipped ammo.",
	"/aw every x Display ammo count every x number of uses.",
	"/aw reload => Reload the AmmoWatch addon.",
    "/aw unload => Unload the AmmoWatch addon.",
    "/aw (help/?) => Display this list of commands.",
    "======================",
}

---------------------------------------------------------------------------------------------------
-- desc: AmmoWatch functions.
---------------------------------------------------------------------------------------------------

-----------------------------------------------------
-- desc: helper.
-----------------------------------------------------
local function isInt(n)
    n = tonumber(n);
    return (type(n) == "number" and (math.floor(n) == n));
end

local function isSwitch(n)
    return n == "on" or n == "off";
end

local function getMax(...)
    local args = {...}
    local max = 0;
    for k, num in pairs(args) do
        if num > max then
            max = num;
        end
    end
    return max;
end

local function getWords(message)
    local words = {};
    for word in message:gmatch("%S+") do
        table.insert(words, word);
    end
    return words;
end

local function has_value(tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end

function table.slice(tbl, first, last, step)
    local sliced = {}

    for i = first or 1, last or #tbl, step or 1 do
        sliced[#sliced+1] = tbl[i]
    end

    return sliced
end

local function iPlural(count, word)
    if  count ~= 1 then
		return word.."s";
	end
		return word;
end

-----------------------------------------------------
-- desc: message.
-----------------------------------------------------
local function echo(message)
    _chat:QueueCommand("/echo "..message, 0);
end

local function addChat(mode, message)
    local c_msg = "";
        for i, word in ipairs(getWords(message)) do
            local c_word = string.color(word, mode)
            c_msg = c_msg..word.." ";
        end
    _chat:AddChatMessage(mode, c_msg)
end

-----------------------------------------------------
-- desc: utility.
-----------------------------------------------------

local function getPlayerName()
    return _party:GetPartyMemberName(0);
end

local function displayHelp()
    local mode;
    addChat(chatModes.say, "")
    for k, v in pairs(helpCmds) do
        if (k==1 or k==3 or k==#helpCmds) then
            mode = chatModes.party;
        elseif (k==2) then
            mode = chatModes.unity;
        else
            mode = chatModes.tell;
        end
        addChat(mode, v);
    end
    addChat(chatModes.say, "")
end

local function saveSettings(silent)
    settings:save(_addon.path .. 'settings/ammo_watch.json', ammo_watch_config);
    if (silent) then
        return true;
    end
    addChat(chatModes.linkshell, "AmmoWatch settings have been saved!");
end

-----------------------------------------------------
-- desc: object tables.
-----------------------------------------------------

local function getAmmo()
    local eEntry = _inventory:GetEquipmentItem(SLOT_AMMO);
    local iEntry = _inventory:GetInventoryItem(STORAGETYPE_INVENTORY, eEntry.ItemIndex);
    local ammo   = _resource:GetItemByID(iEntry.Id);
    return {
        ["name"]        = ammo.Name[0x2],
        ["delay"]       = ammo.Delay,
        ["count"]       = iEntry.Count,
        ["iEntry"]      = ammo,
        ["eEntry"]      = eEntry,
        ["action_time"] = math.Round(ammo.Delay / 70, 0)
    };
end

local function getRanged()
    local eEntry = _inventory:GetEquipmentItem(SLOT_RANGE);
    local iEntry = _inventory:GetInventoryItem(STORAGETYPE_INVENTORY, eEntry.ItemIndex);
    local ranged   = _resource:GetItemByID(iEntry.Id);
    return {
        ["name"]        = ranged.Name[0x2],
        ["delay"]       = ranged.Delay,
        ["iEntry"]      = ranged,
        ["eEntry"]      = eEntry,
        ["action_time"] = math.Round(ranged.Delay / 70, 0)
    };
end

local function getTarget()
    local target_index = _target:GetTargetIndex();
    return {
        ["type"]   = _entity:GetType(target_index),
        ["index"]  = target_index,
        ["speech"] = _entity:GetNpcSpeechLoop(target_index)
    };
end

-----------------------------------------------------
-- desc: ammo.
-----------------------------------------------------

local function displayAmmoCount()
    local ammo = getAmmo();
    --TODO:heck ammo slot, if none, display different message
    local count = ammo.count;
    local color = chatModes.linkshell2;
    local prefix = "There are";

    if (count <= 10) then
        color = chatModes.danger;
        prefix = "There are only";
    end

    if (count <= 1) then
        prefix = "There is only"
    end

    local c_count = string.color(ammo.count, color);
    addChat(chatModes.say, prefix.." "..c_count.." "..iPlural(count, ammo.name).." left.");
end

local function normalizeCount(count, min)
    if count >= 99 then
        count = 99;
    elseif count <= min then
        count = min;
    end
    return count;
end

-----------------------------------------------------
-- desc: every_uses.
-----------------------------------------------------
local function getEveryUses()
    return normalizeCount(ammo_watch_config.every_uses, 0);
end

local function setEveryUses(count)
    local new_count = normalizeCount(tonumber(count), 0);
    ammo_watch_config.every_uses = new_count;
end

-----------------------------------------------------
-- desc: every_count.
-----------------------------------------------------
local function displayEveryCount(count, msg_participle)
    local c_count = string.color(count, chatModes.linkshell2);
    addChat(chatModes.say, "The ammo count "..msg_participle.." displayed every "..c_count.." "..iPlural(count, "use")..".");
end

local function getEveryCount()
    return normalizeCount(ammo_watch_config.every_count, 1);
end

local function setEveryCount(count)
    local new_count = normalizeCount(tonumber(count), 1);
    ammo_watch_config.every_count = new_count;
    displayEveryCount(new_count, "will now be");
    setEveryUses(0);
end

----------------------------------------------------
-- desc: timer callbacks.
-----------------------------------------------------
local function onActionTimerEnd()
    timer.RemoveTimer('action_timer');
    setEveryUses(getEveryUses() + 1);

    if (getEveryUses() >= getEveryCount()) then
        displayAmmoCount();
        setEveryUses(0);
    end

    saveSettings(true);
end

---------------------------------------------------------------------------------------------------
-- func: load
-- desc: First called when our addon is loaded.
---------------------------------------------------------------------------------------------------
ashita.register_event('load', function()
    ammo_watch_config = settings:load(_addon.path .. 'settings/ammo_watch.json') or default_config;
    ammo_watch_config = table.merge(default_config, ammo_watch_config);
end );

---------------------------------------------------------------------------------------------------
-- func: unload
-- desc: Called when our addon is unloaded.
---------------------------------------------------------------------------------------------------
ashita.register_event('unload', function()
    addChat(chatModes.unity, "Thank you for using AmmoWatch.");
end );

---------------------------------------------------------------------------------------------------
-- func: command
-- desc: Called when our addon receives a command.
---------------------------------------------------------------------------------------------------
ashita.register_event('command', function(cmd, nType)
    local args = cmd:GetArgs();

    if (args[1] ~= '/aw' and args[1] ~= '/ammo' and args[1] ~= '/ammowatch') then
        return false;
    end
    
    if (args[2] == "get") then
        displayAmmoCount();
        return true;

    elseif (args[2] == "every") then
        if (args[3] and isInt(args[3])) then
            setEveryCount(args[3]);
            saveSettings(true);
        else
            displayEveryCount(getEveryCount(), "is being");
            addChat(chatModes.tell, "To change this value, type: '/aw every x' where 'x' is the new value.")
        end
        return true;
 
    elseif (args[2] == "reload") then
        _chat:QueueCommand("/addon reload AmmoWatch", 0);
        return true;

    elseif (args[2] == "unload") then
        _chat:QueueCommand("/addon unload AmmoWatch", 0);
        return true;

    elseif (args[2] == "?" or args[2] == "help") then
        displayHelp();
        return true;

    else
        if (args[2]) then
            addChat(chatModes.tell, "That is not a valid AmmoWatch command.");
        end

        addChat(chatModes.tell, "To see a list of commands type: /aw ? or /aw help.")
        return true;
    end

    return true;

end );

---------------------------------------------------------------------------------------------------
-- func: outgoing_packet
-- desc: Called when our addon sends a packet.
---------------------------------------------------------------------------------------------------
ashita.register_event('outgoing_packet', function(id, size, packet)

    if (id == 0x1A) then
        local _, data = pack.unpack(packet, 'b', 0xA + 1);

        if (data == 0x10 and _ == 0xc ) then
            local target = getTarget();
            local ammo = getAmmo();
            local ranged = getRanged();

            if (ammo.eEntry and ammo.eEntry.ItemIndex ~= 0x0) then
                local action_time = ammo.action_time;

                if (ranged.eEntry and ranged.eEntry.ItemIndex ~= 0x0) then
                    action_time = ranged.action_time;
                end

                if(target.type == 0x2 and target.speech == 0x0) then

                    timer.Create("action_timer", action_time, 1, onActionTimerEnd)
                    timer.StartTimer("action_timer");
                end
            end
        end
    end

    return false;
end);
