# Core.lua Analysis - Memory Churn Investigation

**File**: `/Users/ncerny/workspace/uss-enterprise-guild/cleveroidmacros/Core.lua`
**Lines**: 1,461
**Environment**: WoW 1.12.1 (Lua 5.0)

---

## 1. Summary

`Core.lua` is the central file of the CleveRoidMacros addon. It provides:

- **Macro parsing and execution**: Parses extended macro syntax with conditionals (similar to retail WoW)
- **Action bar integration**: Hooks WoW's action bar API to display dynamic tooltips, textures, cooldowns, and range information for macro-driven actions
- **Cast sequence support**: Implements `/castsequence` functionality
- **Event-driven state management**: Tracks combat state, spell casts, auto-attack status, and sequences
- **OnUpdate handler**: Runs every frame (throttled to 0.2s) to update sequences, clean spell tracking, and re-index action bars

---

## 2. Key Data Structures

All data structures are **module-level persistent** (stored on the `CleveRoids` table), initialized in `Init.lua`:

| Table | Purpose | Lifetime |
|-------|---------|----------|
| `CleveRoids.ParsedMsg` | Cache of parsed macro messages | Persistent, cleared on UPDATE_MACROS |
| `CleveRoids.Items` | Indexed inventory/equipped items | Rebuilt on BAG_UPDATE, UNIT_INVENTORY_CHANGED |
| `CleveRoids.Spells` | Indexed spellbook entries | Rebuilt on SPELLS_CHANGED |
| `CleveRoids.Talents` | Indexed talent ranks | Rebuilt lazily, cleared on UPDATE_MACROS |
| `CleveRoids.Macros` | Parsed macro bodies | Persistent, cleared on UPDATE_MACROS |
| `CleveRoids.Actions` | Action slot -> parsed macro mapping | Persistent, cleared on UPDATE_MACROS |
| `CleveRoids.Sequences` | Cast sequence state | Persistent, cleared on UPDATE_MACROS |
| `CleveRoids.spell_tracking` | Active spell casts by GUID | Cleaned up in OnUpdate |
| `CleveRoids.CombatLog` | Recent combat log entries (max 100) | Persistent |
| `CleveRoids.actionSlots` | Spell/item name -> action slot mapping | Rebuilt on IndexActionBars |
| `CleveRoids.reactiveSlots` | Reactive spell -> action slot mapping | Rebuilt on IndexActionBars |
| `CleveRoids.CurrentSpell` | Current spell state (channeling, auto-attack, etc.) | Persistent |
| `CleveRoids.Hooks` | Original function references | Persistent |
| `CleveRoids.actionEventHandlers` | Registered action event callbacks | Persistent |
| `CleveRoids.mouseOverResolvers` | Registered mouseover resolvers | Persistent |

---

## 3. Event Handlers

### 3.1 Registered Events (lines 1211-1231, 1416-1419)

| Event | Handler Function | Frequency | Notes |
|-------|-----------------|-----------|-------|
| `PLAYER_LOGIN` | `Frame:PLAYER_LOGIN` | Once | Initial indexing |
| `ADDON_LOADED` | `Frame:ADDON_LOADED` | Once per addon | SuperMacro integration |
| `SPELLCAST_CHANNEL_START` | `Frame:SPELLCAST_CHANNEL_START` | Per channel | Sets CurrentSpell.type |
| `SPELLCAST_CHANNEL_STOP` | `Frame:SPELLCAST_CHANNEL_STOP` | Per channel | Clears CurrentSpell |
| `UNIT_CASTEVENT` | `Frame:UNIT_CASTEVENT` | Per cast event | SuperWoW cast tracking |
| `PLAYER_ENTER_COMBAT` | `Frame:PLAYER_ENTER_COMBAT` | Combat start | Sets autoAttack flag |
| `PLAYER_LEAVE_COMBAT` | `Frame:PLAYER_LEAVE_COMBAT` | Combat end | Resets sequences |
| `PLAYER_TARGET_CHANGED` | `Frame:PLAYER_TARGET_CHANGED` | Target change | Resets target-based sequences |
| `START_AUTOREPEAT_SPELL` | `Frame:START_AUTOREPEAT_SPELL` | Auto-shot/wand start | Sets autoShot/wand flag |
| `STOP_AUTOREPEAT_SPELL` | `Frame:STOP_AUTOREPEAT_SPELL` | Auto-shot/wand stop | Clears autoShot/wand flag |
| `UPDATE_MACROS` | `Frame:UPDATE_MACROS` | Macro edit/create | **Full cache clear and reindex** |
| `ACTIONBAR_SLOT_CHANGED` | `Frame:ACTIONBAR_SLOT_CHANGED` | Per slot change | Reindexes single slot |
| `SPELLS_CHANGED` | `Frame:SPELLS_CHANGED` | Talent/spell change | **Full cache clear and reindex** |
| `BAG_UPDATE` | `Frame:BAG_UPDATE` | Inventory change | **Full item reindex** |
| `UNIT_INVENTORY_CHANGED` | `Frame:UNIT_INVENTORY_CHANGED` | Equipment change | **Full item reindex** |
| `CHAT_MSG_SPELL_SELF_DAMAGE` | eventFrame OnEvent | Per damage event | Combat log entry |
| `CHAT_MSG_COMBAT_SELF_HITS` | eventFrame OnEvent | Per hit event | Combat log entry |
| `CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE` | eventFrame OnEvent | Per DoT tick | Combat log entry |
| `EVENT_COMBAT_LOG_EVENT` | eventFrame OnEvent | Per combat log event | Combat log entry |

### 3.2 High-Frequency Event Concerns

**BAG_UPDATE** (line 1381-1383):
```lua
function CleveRoids.Frame:BAG_UPDATE()
    CleveRoids.IndexItems()  -- EXPENSIVE: Iterates all bags and inventory
end
```
- Fires on ANY inventory change (including stack count changes)
- Calls `IndexItems()` which creates many table entries

**UNIT_INVENTORY_CHANGED** (lines 1385-1390):
```lua
function CleveRoids.Frame:UNIT_INVENTORY_CHANGED()
    if arg1 ~= "player" then return end
    CleveRoids.IndexItems()  -- Same expensive operation
end
```

---

## 4. OnUpdate Handlers - CRITICAL

### 4.1 Main OnUpdate (lines 1007-1040, registered at line 1206)

```lua
CleveRoids.Frame:SetScript("OnUpdate", CleveRoids.OnUpdate)
```

**Throttling**: 0.2 second interval (line 1014)
```lua
if (time - CleveRoids.lastUpdate) < 0.2 then return end
```

**Per-tick operations**:

1. **Auto-attack lock timeout** (lines 1017-1020):
   - Simple flag check, minimal allocation

2. **Sequence iteration** (lines 1022-1030):
   ```lua
   for _, sequence in pairs(CleveRoids.Sequences) do
       -- Calls CleveRoids.TestAction(sequence.cmd, sequence.args)
   end
   ```
   - **MEMORY CONCERN**: `pairs()` creates an iterator
   - **MEMORY CONCERN**: `TestAction` may call `GetParsedMsg` which can allocate

3. **Spell tracking cleanup** (lines 1032-1037):
   ```lua
   for guid, cast in pairs(spell_tracking) do
       if time > cast.expires then
           CleveRoids.spell_tracking[guid] = nil
       end
   end
   ```
   - **MEMORY CONCERN**: `pairs()` creates an iterator

4. **Action bar indexing** (line 1039):
   ```lua
   CleveRoids.IndexActionBars()  -- Iterates 120 action slots EVERY 0.2 SECONDS
   ```
   - **MAJOR MEMORY CONCERN**: Calls `IndexActionSlot` 120 times
   - Each call may invoke `GetActionButtonInfo`, `TestForActiveAction`, `SendEventForAction`

### 4.2 CombatLog Event Frame (lines 1421-1428)

```lua
eventFrame:SetScript("OnEvent", function(self, event, timestamp, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
    if event == "EVENT_COMBAT_LOG_EVENT" then
        local args = {arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9}  -- TABLE CREATION
        CleveRoids.AddCombatLogEntry(timestamp, event, unpack(args))
    ...
end)
```
- **MEMORY CONCERN**: Creates `args` table on EVERY combat log event

---

## 5. Memory Concerns - Detailed Analysis

### 5.1 Table Creation in Hot Paths

#### Line 101 - AddCombatLogEntry
```lua
local args = {arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9}  -- Creates table
table.insert(CleveRoids.CombatLog, {msg = msg, args = args})   -- Creates another table
```
**Impact**: Creates 2 tables per qualifying combat event

#### Line 193 - ExecuteMacroBody
```lua
local lines = CleveRoids.splitString(body, "\n")
```
**Impact**: Creates new table for each macro execution

#### Line 342-343 - ParseSequence
```lua
local args = string.gsub(text, "(%s*,%s*)", ",")
local _, c, cond = string.find(args, "(%[.*%])")
```
**Impact**: Creates intermediate strings

#### Lines 353-362 - ParseSequence
```lua
local sequence = {
    index = 1,
    reset = {},
    status = 0,
    list = {},
    lastUpdate = 0,
    ...
}
```
**Impact**: Creates nested tables (but cached after first parse)

#### Line 457 - ParseMsg
```lua
local conditionals = {}
```
**Impact**: Creates table per parse (but result is cached in `ParsedMsg`)

#### Line 1423 - Combat Log Handler
```lua
local args = {arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9}
```
**Impact**: Creates table on EVERY combat log event - even when idle if combat log events fire

### 5.2 String Concatenation in Hot Paths

#### Line 1000 - DoCastSequence
```lua
local action = (sequence.cond or "") .. active.action
```
**Impact**: Creates new string per cast sequence attempt

#### Line 1052 - GameTooltip.SetAction
```lua
GameTooltipTextRight1:SetText("|cff808080" .. rank .."|r")
```
**Impact**: Creates string per tooltip display

#### Line 1113-1114 - IsCurrentAction
```lua
name = active.spell.name..(rank and ("("..rank..")"))
```
**Impact**: Creates string per action check (called frequently from UI)

#### Line 1305 - UNIT_CASTEVENT
```lua
local isSeqSpell = (active.action == name or active.action == (name.."("..rank..")"))
```
**Impact**: Creates string per cast event

#### Lines 127-128 (Utility.lua) - Print
```lua
out = out..tostring(arg[i]).."  "
```
**Impact**: String concatenation in loop (only affects debug output)

#### Lines 107-109 (Utility.lua) - splitStringIgnoringQuotes
```lua
temp = temp .. char  -- Character-by-character concatenation
```
**Impact**: O(n^2) string building - called during macro parsing

### 5.3 Functions Called Frequently

#### IndexActionBars (called every 0.2s in OnUpdate)
Located in `Extensions/Tooltip/Generic.lua` lines 190-194:
```lua
function CleveRoids.IndexActionBars()
    for i = 1, 120 do
        CleveRoids.IndexActionSlot(i)
    end
end
```
- Iterates 120 slots every 0.2 seconds = 600 function calls/second
- Each `IndexActionSlot` may create strings for action names

#### IndexActionSlot (lines 157-188, Generic.lua)
```lua
function CleveRoids.IndexActionSlot(slot)
    ...
    local actionSlotName = name..(rank and ("("..rank..")") or "")  -- STRING CREATION
    ...
end
```
**Impact**: Creates strings for every action slot with a spell

#### GetParsedMsg (lines 541-552)
```lua
function CleveRoids.GetParsedMsg(msg)
    if CleveRoids.ParsedMsg[msg] then
        return CleveRoids.ParsedMsg[msg].action, CleveRoids.ParsedMsg[msg].conditionals
    end

    CleveRoids.ParsedMsg[msg] = {}  -- TABLE CREATION (cached)
    CleveRoids.ParsedMsg[msg].action, CleveRoids.ParsedMsg[msg].conditionals = CleveRoids.ParseMsg(msg)
    ...
end
```
**Impact**: Caching helps, but first call creates tables

#### TestAction (lines 578-626)
```lua
function CleveRoids.TestAction(cmd, args)
    local msg, conditionals = CleveRoids.GetParsedMsg(args)
    ...
    for k, v in pairs(conditionals) do  -- ITERATOR CREATION
        ...
    end
end
```
**Impact**: Iterator created per call, called for each sequence in OnUpdate

#### SendEventForAction (lines 149-188)
```lua
function CleveRoids.SendEventForAction(slot, event, ...)
    ...
    for _, fn in ipairs(CleveRoids.actionEventHandlers) do  -- ITERATOR CREATION
        fn(slot, event, unpack(arg))
    end
end
```
**Impact**: Iterator created per call, `unpack(arg)` may allocate

### 5.4 Closure Creation

#### Line 797-807 - DoTarget
```lua
local action = function(msg)  -- CLOSURE CREATED PER CALL
    if string.sub(msg, 1, 1) == "@" then
        ...
    end
end
```
**Impact**: Creates closure every time `/target` is used

#### Lines 844-855 - DoUse
```lua
local action = function(msg)  -- CLOSURE CREATED PER CALL
    local item = CleveRoids.GetItem(msg)
    ...
end
```
**Impact**: Creates closure every time `/use` is used

#### Lines 902-904, 920-922 - DoEquipMainhand/DoEquipOffhand
```lua
local action = function(msg)  -- CLOSURE CREATED PER CALL
    return CleveRoids.EquipBagItem(msg, false)
end
```
**Impact**: Creates closure per equip command

#### Lines 938-943 - DoUnshift
```lua
local action = function(msg)  -- CLOSURE CREATED PER CALL
    local currentShapeshiftIndex = CleveRoids.GetCurrentShapeshiftIndex()
    ...
end
```
**Impact**: Creates closure per unshift command

### 5.5 gsub/strfind/format in Hot Paths

#### Line 21-24 - GetSpellCost
```lua
local _, _, cost = string.find(CleveRoids.Frame.costFontString:GetText() or "", "^(%d+) [^ys]")
local _, _, reagent = string.find(CleveRoids.Frame.reagentFontString:GetText() or "", "^Reagents: (.*)")
if reagent and string.sub(reagent, 1, 2) == "|c" then
    reagent = string.sub(reagent, 11, -3)
end
```
**Impact**: Called during IndexSpells, creates capture strings

#### Lines 459-466 - ParseMsg
```lua
msg, conditionals.ignoretooltip = string.gsub(CleveRoids.Trim(msg), "^%?", "")
local _, cbEnd, conditionBlock = string.find(msg, "%[(.+)%]")
local _, _, noSpam, cancelAura, action = string.find(string.sub(msg, (cbEnd or 0) + 1), "^%s*(!?)(~?)([^!~]+.*)")
action = CleveRoids.Trim(action or "")
...
action = string.gsub(action, "%(Rank %d+%)", "")
```
**Impact**: Multiple string operations per parse (but cached)

#### Lines 511-516 - ParseMsg conditionals parsing
```lua
arg = string.gsub(arg, '"', "")
arg = string.gsub(arg, "_", " ")
arg = string.gsub(arg, "^#(%d+)$", "=#%1")
arg = string.gsub(arg, "([^>~=<]+)#(%d+)", "%1=#%2")
```
**Impact**: Multiple gsub calls per conditional arg (but cached)

### 5.6 Idle State Memory Churn Sources

Even when standing idle, the following cause memory allocation:

1. **OnUpdate every 0.2s** (line 1007):
   - `pairs(CleveRoids.Sequences)` - iterator allocation
   - `pairs(spell_tracking)` - iterator allocation
   - `IndexActionBars()` - 120 iterations, potential string creation for each slot

2. **Combat log events** (lines 1416-1428):
   - Even "idle", nearby combat creates events
   - Each event creates `args` table at line 1423

3. **Hooked functions called by WoW UI**:
   - `GetActionTexture` (line 1124) - called when action bars redraw
   - `GetActionCooldown` (line 1140) - called continuously for cooldown display
   - `IsUsableAction` (line 1095) - called for usability display
   - `IsActionInRange` (line 1085) - called for range display
   - `IsCurrentAction` (line 1105) - string concatenation at line 1114

---

## 6. Function Call Patterns

### 6.1 Call Hierarchy (Idle State)

```
OnUpdate (every 0.2s)
  |
  +-- pairs(Sequences) [iterator]
  |     |
  |     +-- TestAction() per sequence
  |           |
  |           +-- GetParsedMsg() [cached lookup]
  |           +-- pairs(conditionals) [iterator]
  |
  +-- pairs(spell_tracking) [iterator]
  |
  +-- IndexActionBars()
        |
        +-- IndexActionSlot(1..120)
              |
              +-- GetActionButtonInfo()
              +-- string concatenation for actionSlotName
              +-- TestForActiveAction()
              |     |
              |     +-- TestAction()
              |     +-- pairs iteration
              |
              +-- SendEventForAction()
                    |
                    +-- ipairs(actionEventHandlers) [iterator]
```

### 6.2 Call Hierarchy (Action Bar UI Updates)

```
GetActionTexture(slot) [WoW UI call]
  |
  +-- GetAction(slot)
        |
        +-- GetMacro() [cached]
        +-- TestForActiveAction()
        +-- SendEventForAction()
```

---

## 7. Recommendations

### 7.1 Critical - OnUpdate Optimization

**Line 1039 - Remove IndexActionBars from OnUpdate**:
```lua
-- BEFORE:
CleveRoids.IndexActionBars()

-- AFTER:
-- Remove this line entirely. Action bars should only be indexed on:
-- 1. PLAYER_LOGIN
-- 2. ACTIONBAR_SLOT_CHANGED (already handled)
-- 3. UPDATE_MACROS (already handled)
```

**Lines 1022-1030 - Pre-allocate sequence iteration**:
```lua
-- BEFORE:
for _, sequence in pairs(CleveRoids.Sequences) do

-- AFTER:
-- Use a cached list of sequence keys, update only when sequences change
-- Or use next() iteration pattern:
local seq_key, sequence = next(CleveRoids.Sequences)
while seq_key do
    -- process sequence
    seq_key, sequence = next(CleveRoids.Sequences, seq_key)
end
```

### 7.2 High Priority - Table Pre-allocation

**Line 101 - AddCombatLogEntry**:
```lua
-- BEFORE:
local args = {arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9}
table.insert(CleveRoids.CombatLog, {msg = msg, args = args})

-- AFTER:
-- Use a ring buffer with pre-allocated entries
-- Or store args inline without creating intermediate table
```

**Line 1423 - Combat Log Handler**:
```lua
-- BEFORE:
local args = {arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9}

-- AFTER:
-- Pass args directly without intermediate table
CleveRoids.AddCombatLogEntry(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
```

### 7.3 Medium Priority - String Concatenation

**Lines 1113-1114 - IsCurrentAction**:
```lua
-- BEFORE:
name = active.spell.name..(rank and ("("..rank..")"))

-- AFTER:
-- Cache the formatted name on the spell object during indexing
name = active.spell.nameWithRank  -- Pre-computed
```

**Lines 166 (Generic.lua) - IndexActionSlot**:
```lua
-- BEFORE:
local actionSlotName = name..(rank and ("("..rank..")") or "")

-- AFTER:
-- Use a lookup table for common spell+rank combinations
-- Or compute once and cache in the spell object
```

### 7.4 Medium Priority - Closure Elimination

**Lines 797-807, 844-855, 902-904, 920-922, 938-943**:
```lua
-- BEFORE (example from DoTarget):
local action = function(msg)
    ...
end

-- AFTER:
-- Move closure to module level as a named function
CleveRoids._DoTargetAction = function(msg)
    ...
end

-- Then use:
CleveRoids.DoWithConditionals(v, CleveRoids.Hooks.TARGET_SlashCmd,
    CleveRoids.FixEmptyTargetSetTarget, false, CleveRoids._DoTargetAction)
```

### 7.5 Low Priority - Iterator Pattern

**Use next() instead of pairs() in hot paths**:
```lua
-- BEFORE:
for k, v in pairs(conditionals) do

-- AFTER:
local k, v = next(conditionals)
while k do
    -- process k, v
    k, v = next(conditionals, k)
end
```

### 7.6 Event Handler Optimization

**Lines 1381-1390 - BAG_UPDATE/UNIT_INVENTORY_CHANGED**:
```lua
-- BEFORE:
function CleveRoids.Frame:BAG_UPDATE()
    CleveRoids.IndexItems()
end

-- AFTER:
-- Throttle or debounce item indexing
local itemIndexPending = false
function CleveRoids.Frame:BAG_UPDATE()
    if not itemIndexPending then
        itemIndexPending = true
        -- Use OnUpdate to delay by 1 frame
    end
end

-- Or only re-index affected bag:
function CleveRoids.Frame:BAG_UPDATE()
    CleveRoids.IndexBag(arg1)  -- New function to index single bag
end
```

---

## 8. Summary of Memory Churn Sources (Idle State)

| Source | Frequency | Allocations | Priority |
|--------|-----------|-------------|----------|
| IndexActionBars in OnUpdate | Every 0.2s | 120+ function calls, strings | **CRITICAL** |
| pairs() iterators in OnUpdate | Every 0.2s | 2-3 iterators | HIGH |
| Combat log table creation | Per combat event | 2 tables | MEDIUM |
| Hooked API string concat | Per UI update | Variable strings | MEDIUM |
| Closure creation in commands | Per command use | 1 closure | LOW |

**Estimated Impact**: Removing `IndexActionBars()` from OnUpdate alone could reduce idle memory churn by 50-70%.
