# CleveRoidMacros Extension System

## Summary

The extension system in CleveRoidMacros provides a modular architecture for adding functionality without modifying core code. Extensions can:
- Register for WoW events
- Hook global functions
- Hook methods on objects (like GameTooltip)
- Add mouseover tracking for different UI addons

Each extension gets its own hidden frame for event handling and maintains its own tables for hooks and event handlers.

**Key Files:**
- `/ExtensionsManager.lua` - Core extension registration and lifecycle management
- `/Extensions/Mouseover/*.lua` - 12 extensions for tracking mouseover on various addon frames
- `/Extensions/Tooltip/Generic.lua` - Spell/item indexing (misnamed, not actually tooltip-related)
- `/Extensions/MacroLengthWarn.lua` - Safety check for macro line length

---

## Extension Registration

### How Extensions Are Registered

Extensions are registered via `CleveRoids.RegisterExtension(name)` (ExtensionsManager.lua:53-113):

```lua
local Extension = CleveRoids.RegisterExtension("MyExtension")
```

This creates an extension object with:
- `internal.frame` - A hidden frame for event handling (line 57)
- `internal.eventHandlers` - Table mapping event names to callback names (line 58)
- `internal.hooks` - Table of global function hooks (line 59)
- `internal.memberHooks` - Table of object method hooks (line 60)

### Extension API

Each extension object has these methods:

| Method | Description | Location |
|--------|-------------|----------|
| `RegisterEvent(eventName, callbackName)` | Register for a WoW event | Line 64-66 |
| `UnregisterEvent(eventName, callbackName)` | Stop listening to an event | Line 77-79 |
| `Hook(functionName, callbackName, dontCallOriginal)` | Hook a global function | Line 68-70 |
| `HookMethod(object, functionName, callbackName, dontCallOriginal)` | Hook a method on an object | Line 72-74 |

### Extension Lifecycle

1. **Loading** - Extensions are loaded via `.toc` file order (after ExtensionsManager.lua)
2. **Registration** - Each extension file calls `RegisterExtension()` at load time
3. **Initialization** - `CleveRoids.InitializeExtensions()` is called on `ADDON_LOADED` (Core.lua:1248)
4. **OnLoad** - Each extension's `OnLoad()` function is called (ExtensionsManager.lua:12-21)

---

## Mouseover Extensions

The mouseover system allows macros to target units under the mouse cursor. There are **12 mouseover extensions** supporting different UI addons:

| Extension | Addon Supported | File |
|-----------|-----------------|------|
| Blizzard | Default Blizzard frames | Mouseover/Blizzard.lua |
| GameTooltip | Any addon using GameTooltip:SetUnit() | Mouseover/GameTooltip.lua |
| CT_RaidAssist | CT_RaidAssist | Mouseover/CT_RaidAssist.lua |
| CT_UnitFrames | CT_UnitFrames (TargetOfTarget) | Mouseover/CT_UnitFrames.lua |
| DiscordUnitFrames | Discord Unit Frames | Mouseover/DiscordUnitFrames.lua |
| FocusFrame | FocusFrame addon | Mouseover/FocusFrame.lua |
| Grid | Grid raid frames | Mouseover/Grid.lua |
| NotGrid | NotGrid raid frames | Mouseover/NotGrid.lua |
| PerfectRaid | PerfectRaid addon | Mouseover/PerfectRaid.lua |
| pfUI | pfUI unit frames | Mouseover/pfUI.lua |
| sRaidFrames | sRaidFrames addon | Mouseover/sRaidFrames.lua |
| ag_UnitFrames | ag_UnitFrames | Mouseover/ag_UnitFrames.lua |

### How Mouseover Tracking Works

All mouseover extensions use the same pattern - they set/clear `CleveRoids.mouseoverUnit`:

```lua
-- On mouse enter
CleveRoids.mouseoverUnit = "party1"  -- or "raid5", "target", etc.

-- On mouse leave
CleveRoids.mouseoverUnit = nil
```

The mouseover value is consumed in `Conditionals.lua:65-69`:
```lua
if (not CleveRoids.mouseoverUnit) and not UnitName("mouseover") then
    return false
end
```

### Hooking Patterns Used

**1. Script Replacement (Most Common)**
Used by: Blizzard, FocusFrame, CT_UnitFrames, NotGrid, pfUI

```lua
-- Blizzard.lua:19-31
local onenter = frame:GetScript("OnEnter")
local onleave = frame:GetScript("OnLeave")

frame:SetScript("OnEnter", function()
    CleveRoids.mouseoverUnit = unit
    if onenter then onenter() end
end)

frame:SetScript("OnLeave", function()
    CleveRoids.mouseoverUnit = nil
    if onleave then onleave() end
end)
```

**2. Method Hooking via Extension API**
Used by: GameTooltip, CT_RaidAssist, sRaidFrames, DiscordUnitFrames

```lua
-- GameTooltip.lua:21-23
Extension.HookMethod(_G["GameTooltip"], "SetUnit", "SetUnit")
Extension.HookMethod(_G["GameTooltip"], "Hide", "OnClose")
Extension.HookMethod(_G["GameTooltip"], "FadeOut", "OnClose")
```

**3. Prototype/Class Hooking**
Used by: Grid, ag_UnitFrames, PerfectRaid

```lua
-- Grid.lua:27-28 (replaces CreateFrames to inject OnEnter/OnLeave)
CleveRoids.Hooks.Grid = { CreateFrames = GridFrame.frameClass.prototype.CreateFrames }
GridFrame.frameClass.prototype.CreateFrames = CleveRoids.GrdCreateFrames
```

---

## Tooltip Extensions

### Generic.lua Analysis

**Note:** Despite being in the `Tooltip` folder, `Generic.lua` is primarily about **spell, item, and talent indexing**, not tooltip handling.

Key functions (Generic.lua):

| Function | Purpose | Lines |
|----------|---------|-------|
| `CleveRoids.IndexSpells()` | Index all known spells and pet spells | 10-64 |
| `CleveRoids.IndexTalents()` | Index all talent points | 66-75 |
| `CleveRoids.IndexItems()` | Index all bag and equipped items | 78-148 |
| `CleveRoids.IndexActionBars()` | Index all 120 action bar slots | 190-194 |
| `CleveRoids.GetSpell(text)` | Look up a spell by name | 196-206 |
| `CleveRoids.GetItem(text)` | Look up an item by name or ID | 213-236 |

The extension registers for `SPELLS_CHANGED` but the handler is empty (lines 253-259).

---

## Memory Concerns

### Critical Finding: OnUpdate in Core.lua

The main memory concern is in `Core.lua:1007-1040`:

```lua
function CleveRoids.OnUpdate(self)
    if not CleveRoids.ready then return end

    local time = GetTime()
    -- Throttled to 5 times per second (every 0.2s)
    if (time - CleveRoids.lastUpdate) < 0.2 then return end
    CleveRoids.lastUpdate = time

    -- ... spell tracking cleanup ...

    -- THIS RUNS EVERY 0.2 SECONDS:
    CleveRoids.IndexActionBars()  -- Line 1039
end
```

**`IndexActionBars()` (Generic.lua:190-194) loops through 120 action slots every 200ms!**

```lua
function CleveRoids.IndexActionBars()
    for i = 1, 120 do
        CleveRoids.IndexActionSlot(i)  -- Creates tables, strings
    end
end
```

### Memory Allocation Sources

| Location | Issue | Severity |
|----------|-------|----------|
| Core.lua:1039 | `IndexActionBars()` runs 5x/sec, iterates 120 slots | **HIGH** |
| Generic.lua:165-166 | String concatenation in `actionSlotName = name..(rank and...)` | HIGH |
| Generic.lua:78-148 | `IndexItems()` creates many tables (runs on BAG_UPDATE) | MEDIUM |
| ExtensionsManager.lua:156-158 | Hook wrappers create closure on every call | LOW |

### Hook Wrapper Allocation

Every hooked function creates a new function closure (ExtensionsManager.lua:156-158):
```lua
_G[functionName] = function(arg1, arg2, ...)  -- New function object
    return extension.internal.OnHook(nil, functionName, arg1, ...)
end
```

This is a one-time cost at load, not ongoing.

### Extension Frame Creation

Each extension creates a frame (ExtensionsManager.lua:57):
```lua
internal = {
    frame = CreateFrame("FRAME"),  -- 1 frame per extension
    -- ...
}
```

With 14 extensions, this creates 14 frames. This is acceptable.

---

## Hot Paths

### Code That Runs Continuously

| Code Path | Frequency | Location | Creates Memory? |
|-----------|-----------|----------|-----------------|
| `CleveRoids.OnUpdate()` | Every frame | Core.lua:1007 | Yes (via IndexActionBars) |
| `IndexActionBars()` | 5x/second | Generic.lua:190 | Yes (strings, tables) |
| `IndexActionSlot()` | 600x/second (120*5) | Generic.lua:157 | Yes |
| Sequence timeout checks | 5x/second | Core.lua:1023-1030 | No |
| Spell tracking cleanup | 5x/second | Core.lua:1033-1037 | No (only removes) |

### Code That Runs On-Demand

| Code Path | Trigger | Location |
|-----------|---------|----------|
| Mouseover OnEnter/OnLeave | Mouse movement over frames | Extensions/Mouseover/*.lua |
| `IndexSpells()` | SPELLS_CHANGED event | Generic.lua:10 |
| `IndexItems()` | BAG_UPDATE, UNIT_INVENTORY_CHANGED | Generic.lua:78 |
| Hook callbacks | When hooked function is called | ExtensionsManager.lua:91-105 |

---

## Recommendations

### Critical (High Memory Impact)

**1. Throttle or Remove Continuous ActionBar Indexing**
- **Location:** Core.lua:1039
- **Issue:** `CleveRoids.IndexActionBars()` runs every 0.2 seconds
- **Fix:** Only call on `ACTIONBAR_SLOT_CHANGED` event, not in OnUpdate

```lua
-- REMOVE from OnUpdate:
-- CleveRoids.IndexActionBars()  -- Line 1039

-- Already registered: Core.lua:1228
CleveRoids.Frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")

-- Already exists: Core.lua:1316-1318
function CleveRoids.Frame:ACTIONBAR_SLOT_CHANGED(slot)
    CleveRoids.IndexActionSlot(slot)  -- Only update changed slot!
end
```

The event handler already exists and only updates the changed slot. The OnUpdate call is redundant.

**2. Pre-allocate String in IndexActionSlot**
- **Location:** Generic.lua:165-166
- **Issue:** Creates new string every call via concatenation

```lua
-- Current (creates garbage):
local actionSlotName = name..(rank and ("("..rank..")") or "")

-- Consider: Cache or use format with reused buffer
```

### Medium Priority

**3. Avoid Table Creation in IndexItems on Every BAG_UPDATE**
- **Location:** Generic.lua:89-106
- **Issue:** Creates new table for each item slot

```lua
items[name] = {
    bagID = bagID,
    slot = slot,
    -- ... creates new table every time
}
```

**Fix:** Reuse existing table entries, only update fields.

**4. Remove Empty SPELLS_CHANGED Handler**
- **Location:** Generic.lua:258-259
- **Issue:** Registers event but handler does nothing

```lua
function Extension.SPELLS_CHANGED()
    -- Empty - wastes event dispatch
end
```

### Low Priority

**5. Grid Extension Duplicates Entire CreateFrames Function**
- **Location:** Grid.lua:32-112
- **Issue:** Copy-pastes Grid's CreateFrames instead of post-hooking
- **Risk:** Will break if Grid updates its CreateFrames function

**6. Some Extensions Don't Unregister ADDON_LOADED**
- **Locations:** CT_RaidAssist.lua, Grid.lua, PerfectRaid.lua, sRaidFrames.lua
- **Issue:** Continue receiving ADDON_LOADED events after their target addon loads
- **Note:** NotGrid.lua:51 and ag_UnitFrames.lua:26 correctly unregister

---

## Extension Loading Order

From `CleveRoidMacros.toc`:

1. Core systems: Localization, Init, Utility, Core, Conditionals, Console
2. ExtensionsManager.lua
3. Compatibility modules: SuperMacro, pfUI, Bongos
4. Extensions:
   - MacroLengthWarn.lua
   - Mouseover extensions (12 files)
   - Tooltip/Generic.lua

Extensions are initialized after `ADDON_LOADED` fires for CleveRoidMacros.
