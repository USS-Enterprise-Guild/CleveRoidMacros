# CleveRoidMacros: Init, Utility, and Console Analysis

## Summary

| File | Lines | Purpose |
|------|-------|---------|
| `Init.lua` | 124 | Global namespace initialization, data structure setup, localization tables |
| `Utility.lua` | 208 | String manipulation, printing, comparator functions |
| `Console.lua` | 144 | Slash command registration and handlers |

### Init.lua
Establishes the `CleveRoids` global namespace and initializes all data structures used throughout the addon. This includes hooks storage, spell/item caches, sequence tracking, and localization mappings for weapon types and reactive abilities.

### Utility.lua
Provides core utility functions: string splitting (3 variants), trimming, debug printing (plain, indented, table), keyboard modifier detection, and comparison operators. Also overwrites global `print`, `iprint`, and `tprint`.

### Console.lua
Registers all slash commands (`/cast`, `/use`, `/equip`, `/target`, `/castsequence`, etc.) and hooks existing WoW commands to add conditional macro support.

---

## Initialization Flow

### Load Order
1. **Localization files** (loaded first, referenced by Init.lua line 88-97)
2. **Init.lua** - Creates `CleveRoids` namespace
3. **Utility.lua** - Adds utility functions to namespace
4. **Console.lua** - Registers slash commands
5. **Core.lua** - Main logic and frame creation

### Event-Driven Initialization
The addon uses event-driven initialization via `CleveRoids.Frame` (created in Core.lua):

```lua
-- Core.lua lines 1211-1219
CleveRoids.Frame:RegisterEvent("PLAYER_LOGIN")
CleveRoids.Frame:RegisterEvent("ADDON_LOADED")
CleveRoids.Frame:RegisterEvent("SPELLCAST_CHANNEL_START")
CleveRoids.Frame:RegisterEvent("SPELLCAST_CHANNEL_STOP")
CleveRoids.Frame:RegisterEvent("UNIT_CASTEVENT")
```

The `CleveRoids.ready` flag (Init.lua line 5) gates OnUpdate processing until spells/items are parsed.

---

## Frame Creation

### Frames Created
| Location | Frame Type | Purpose |
|----------|------------|---------|
| Core.lua:14 | `Frame` | Event handling frame (`CleveRoidsEventFrame`) |
| Core.lua:1196 | `GameTooltip` | Tooltip scanning + OnUpdate handler |
| ExtensionsManager.lua:57 | `Frame` | Extension loading |

### OnUpdate Handler (CRITICAL)

**Location**: Core.lua lines 1007-1040, registered at line 1206

```lua
CleveRoids.Frame:SetScript("OnUpdate", CleveRoids.OnUpdate)
```

**Frequency**: Runs every frame (~60+ times/second), but throttled to 0.2 seconds (5Hz):

```lua
-- Core.lua lines 1012-1015
local time = GetTime()
if (time - CleveRoids.lastUpdate) < 0.2 then return end
CleveRoids.lastUpdate = time
```

**Operations per tick (every 0.2s)**:
1. Check autoAttackLock timeout
2. Iterate ALL sequences with `pairs()` - calls `TestAction()` for each
3. Iterate spell_tracking table with `pairs()` - garbage collection
4. **Call `IndexActionBars()` which iterates ALL 120 action slots**

---

## Utility Functions

### String Functions

| Function | Location | Called From | Memory Impact |
|----------|----------|-------------|---------------|
| `Trim(str)` | Utility.lua:16-21 | Everywhere | Creates new string via gsub |
| `Split(s, p, trim)` | Utility.lua:24-52 | Parser | Creates table + strings per call |
| `splitString(str, sep)` | Utility.lua:58-81 | Parser | Creates table + strings per call |
| `splitStringIgnoringQuotes(str, sep)` | Utility.lua:83-120 | Parser | Heavy: char-by-char iteration, string concat |

### `splitStringIgnoringQuotes` - Memory Hot Path
**Location**: Utility.lua:83-120

This function is particularly expensive:
- Iterates character-by-character: `for i = 1, string.len(str) do`
- Uses `string.sub(str, i, i)` per character (creates new string)
- Concatenates with `temp = temp .. char` (creates new string each iteration)
- Creates separator lookup table on every call (line 87-95)

### Print Functions

| Function | Location | Purpose |
|----------|----------|---------|
| `Print(...)` | Utility.lua:123-138 | Debug output with color prefix |
| `PrintI(msg, depth)` | Utility.lua:140-144 | Indented print |
| `PrintT(t, depth)` | Utility.lua:146-163 | Recursive table print |

**Global Overwrites** (Utility.lua:165-167):
```lua
print = CleveRoids.Print
iprint = CleveRoids.PrintI
tprint = CleveRoids.PrintT
```

### Comparison Tables

**Location**: Utility.lua:169-205

Static lookup tables created once at load:
- `CleveRoids.kmods` - Keyboard modifier functions
- `CleveRoids.operators` - Operator name mappings
- `CleveRoids.comparators` - Comparison functions

These are fine - created once, never recreated.

---

## Console Commands

### Registered Slash Commands

| Command | Handler | Location |
|---------|---------|----------|
| `/petattack` | `CleveRoids.DoPetAttack` | Console.lua:8-10 |
| `/rl` | `ReloadUI()` | Console.lua:12-14 |
| `/use` | `CleveRoids.DoUse` | Console.lua:16-18 |
| `/equip` | `CleveRoids.DoUse` | Console.lua:20-25 |
| `/equipmh` | `CleveRoids.DoEquipMainhand` | Console.lua:27-28 |
| `/equipoh` | `CleveRoids.DoEquipOffhand` | Console.lua:30-31 |
| `/unshift` | `CleveRoids.DoUnshift` | Console.lua:33-35 |
| `/cancelaura`, `/unbuff` | `CleveRoids.CancelAura` | Console.lua:38-41 |
| `/startattack` | inline function | Console.lua:43-56 |
| `/stopattack` | inline function | Console.lua:58-65 |
| `/stopcasting` | `SpellStopCasting` | Console.lua:67-69 |
| `/cast` | `CleveRoids.CAST_SlashCmd` (hooked) | Console.lua:71-82 |
| `/target` | `CleveRoids.TARGET_SlashCmd` (hooked) | Console.lua:83-123 |
| `/castsequence` | inline function | Console.lua:125-133 |
| `/runmacro` | `CleveRoids.ExecuteMacroByName` | Console.lua:136-139 |
| `/retarget` | `CleveRoids.DoRetarget` | Console.lua:141-144 |

### Hooked Commands

The addon hooks existing WoW commands to add functionality:

```lua
-- Console.lua:71-82
CleveRoids.Hooks.CAST_SlashCmd = SlashCmdList.CAST
CleveRoids.CAST_SlashCmd = function(msg)
    if CleveRoids.DoCast(msg) then return end
    CleveRoids.Hooks.CAST_SlashCmd(msg)
end
SlashCmdList.CAST = CleveRoids.CAST_SlashCmd
```

---

## Memory Concerns

### CRITICAL: OnUpdate Every-Frame Operations

**Issue 1: IndexActionBars() called every 0.2s**
- Location: Core.lua:1039
- Impact: Iterates 120 action slots, each calling `GetActionButtonInfo()`, string operations

```lua
-- Extensions/Tooltip/Generic.lua:190-194
function CleveRoids.IndexActionBars()
    for i = 1, 120 do
        CleveRoids.IndexActionSlot(i)
    end
end
```

Each `IndexActionSlot` call (Generic.lua:157-188):
- Calls `HasAction(slot)`
- Calls `CleveRoids.GetActionButtonInfo(slot)`
- Creates strings with concatenation: `name..(rank and ("("..rank..")") or "")`
- Calls `CleveRoids.TestForActiveAction()`
- Calls `CleveRoids.SendEventForAction()`

**Issue 2: Sequence iteration with pairs()**
```lua
-- Core.lua:1023-1030
for _, sequence in pairs(CleveRoids.Sequences) do
    if sequence.index > 1 and sequence.reset.secs then
        if (time - sequence.lastUpdate) >= sequence.reset.secs then
            CleveRoids.ResetSequence(sequence)
        end
    end
    sequence.active = CleveRoids.TestAction(sequence.cmd, sequence.args)
end
```

`TestAction()` calls `GetParsedMsg()` which can trigger parsing.

**Issue 3: spell_tracking cleanup with pairs()**
```lua
-- Core.lua:1032-1037
for guid, cast in pairs(spell_tracking) do
    if time > cast.expires then
        CleveRoids.spell_tracking[guid] = nil
    end
end
```

Setting table entries to `nil` fragments the table, causing GC pressure.

### String Operations in Hot Paths

**splitStringIgnoringQuotes** (Utility.lua:83-120):
```lua
for i = 1, string.len(str) do
    local char = string.sub(str, i, i)  -- NEW STRING
    if char == "\"" then
        temp = temp .. char              -- NEW STRING
    elseif char == separators[char] and not insideQuotes then
        temp = CleveRoids.Trim(temp)     -- NEW STRING
        -- ...
    else
        temp = temp .. char              -- NEW STRING
    end
end
```

Worst case: O(n^2) string allocations for n-character input.

### Table Creation in Utilities

Every call to split functions creates new tables:
```lua
-- Utility.lua:24-25
function CleveRoids.Split(s, p, trim)
    local r, o = {}, 1  -- NEW TABLE every call
```

```lua
-- Utility.lua:58-59
function CleveRoids.splitString(str, seperatorPattern)
    local tbl = {}  -- NEW TABLE every call
```

```lua
-- Utility.lua:83-87
function CleveRoids.splitStringIgnoringQuotes(str, separator)
    local result = {}      -- NEW TABLE
    local temp = ""
    local insideQuotes = false
    local separators = {}  -- ANOTHER NEW TABLE
```

### `/target` Command Inefficiency

**Location**: Console.lua:99-116

Creates lowercase strings in loops:
```lua
for i=1, GetNumPartyMembers()+GetNumRaidMembers() do
    local name = UnitName("party"..i) or UnitName("raid"..i)  -- STRING CONCAT
    if name and string.lower(name) == string.lower(targetName) then  -- 2 NEW STRINGS
```

---

## Global State

### Global Variables Created

| Variable | Type | Location | Purpose |
|----------|------|----------|---------|
| `CleveRoids` | table | Init.lua:2-3 | Main addon namespace |
| `print` | function | Utility.lua:165 | Overwritten global |
| `iprint` | function | Utility.lua:166 | New global |
| `tprint` | function | Utility.lua:167 | New global |

### CleveRoids Namespace Tables

| Table | Location | Purpose | OnUpdate Access |
|-------|----------|---------|-----------------|
| `Hooks` | Init.lua:7-8 | Original function storage | No |
| `Extensions` | Init.lua:10 | Extension registry | No |
| `actionEventHandlers` | Init.lua:11 | Event callbacks | Yes (via IndexActionSlot) |
| `mouseOverResolvers` | Init.lua:12 | Mouseover detection | Sometimes |
| `ParsedMsg` | Init.lua:19 | Cached parsed messages | Yes (via TestAction) |
| `Items` | Init.lua:20 | Item cache | Yes |
| `Spells` | Init.lua:21 | Spell cache | Yes |
| `Talents` | Init.lua:22 | Talent cache | Rare |
| `Cooldowns` | Init.lua:23 | Cooldown tracking | Yes |
| `Macros` | Init.lua:24 | Parsed macro cache | Sometimes |
| `Actions` | Init.lua:25 | Action bar cache | Yes (every 0.2s) |
| `Sequences` | Init.lua:26 | Cast sequence state | Yes (every 0.2s) |
| `CurrentSpell` | Init.lua:38-49 | Current cast state | Yes |
| `spell_tracking` | Init.lua:35 | Spell tracking | Yes (every 0.2s) |
| `actionSlots` | Init.lua:76 | Slot-to-name mapping | Yes |
| `reactiveSlots` | Init.lua:77 | Reactive ability slots | Yes |

---

## Recommendations

### HIGH PRIORITY

#### 1. Reduce IndexActionBars Frequency
**Location**: Core.lua:1039

Currently called every 0.2s. Should only be called on relevant events.

```lua
-- BEFORE (Core.lua:1039)
CleveRoids.IndexActionBars()

-- AFTER: Remove from OnUpdate, call only on events:
-- ACTIONBAR_SLOT_CHANGED, ACTIONBAR_PAGE_CHANGED, UPDATE_BONUS_ACTIONBAR
```

Register for specific events instead of polling:
```lua
CleveRoids.Frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
CleveRoids.Frame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
CleveRoids.Frame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
```

#### 2. Fix String Concatenation in splitStringIgnoringQuotes
**Location**: Utility.lua:97-109

Replace character-by-character concatenation with table.concat:

```lua
-- BEFORE
temp = temp .. char

-- AFTER
local chars = {}
-- ... collect into table
temp = table.concat(chars)
```

#### 3. Avoid Creating Separator Table Every Call
**Location**: Utility.lua:87-95

```lua
-- BEFORE
local separators = {}
if type(separator) == "table" then
    for _, s in separator do
        separators[s] = s
    end
else
    separators[separator or ";"] = separator or ";"
end

-- AFTER: Pre-compute or use single string comparison
```

#### 4. Use Dirty Flag for Sequence Updates
**Location**: Core.lua:1023-1030

Don't iterate sequences every tick - only when they change:

```lua
-- BEFORE
for _, sequence in pairs(CleveRoids.Sequences) do
    sequence.active = CleveRoids.TestAction(sequence.cmd, sequence.args)
end

-- AFTER: Mark sequences dirty on relevant events, only update dirty ones
```

### MEDIUM PRIORITY

#### 5. Pre-lowercase Target Names
**Location**: Console.lua:99-116

Cache lowercased unit names instead of calling `string.lower()` in loops.

#### 6. Avoid Table Fragmentation in spell_tracking
**Location**: Core.lua:1032-1037

```lua
-- BEFORE
CleveRoids.spell_tracking[guid] = nil

-- AFTER: Use a separate "free list" or compact periodically
```

#### 7. Reduce String Creation in IndexActionSlot
**Location**: Generic.lua:166

```lua
-- BEFORE
local actionSlotName = name..(rank and ("("..rank..")") or "")

-- AFTER: Cache these strings, they don't change frequently
```

### LOW PRIORITY

#### 8. Remove Duplicate mouseoverUnit Declaration
**Location**: Init.lua:14-15

```lua
CleveRoids.mouseoverUnit = CleveRoids.mouseoverUnit or nil
CleveRoids.mouseOverUnit = nil  -- Different capitalization, likely a bug
```

#### 9. Consider Using ipairs for Ordered Iteration
**Location**: Various

Where order matters and tables are arrays, use `ipairs()` instead of `pairs()` for slightly better performance.

---

## Memory Churn Estimate

With the OnUpdate handler running at 5Hz (every 0.2s):

| Operation | Frequency | Allocations/tick | Est. Bytes/tick |
|-----------|-----------|------------------|-----------------|
| IndexActionBars (120 slots) | 5/sec | ~240 strings | ~4-8KB |
| Sequence iteration | 5/sec | varies | ~1-2KB |
| spell_tracking cleanup | 5/sec | minimal | ~100B |
| String operations | 5/sec | varies | ~1-2KB |

**Estimated idle memory churn**: 30-60KB/second

This aligns with the reported 100+KB/s when accounting for:
- Multiple sequences defined
- Active spells/items on action bars
- Extension overhead not analyzed here

---

## Files Analyzed

- `/Users/ncerny/workspace/uss-enterprise-guild/cleveroidmacros/Init.lua`
- `/Users/ncerny/workspace/uss-enterprise-guild/cleveroidmacros/Utility.lua`
- `/Users/ncerny/workspace/uss-enterprise-guild/cleveroidmacros/Console.lua`
- `/Users/ncerny/workspace/uss-enterprise-guild/cleveroidmacros/Core.lua` (OnUpdate handler)
- `/Users/ncerny/workspace/uss-enterprise-guild/cleveroidmacros/Extensions/Tooltip/Generic.lua` (IndexActionBars)
