# Performance Fix Status

This document tracks the status of performance issues identified during the CleveRoidMacros analysis.

**PR**: https://github.com/USS-Enterprise-Guild/CleveRoidMacros/pull/1
**Date**: 2026-01-11

---

## Fixed

| Priority | Issue | File | Fix Applied |
|----------|-------|------|-------------|
| CRITICAL | IndexActionBars() in OnUpdate every 0.2s | `Core.lua:1039` | Commented out - action bars indexed on ACTIONBAR_SLOT_CHANGED instead |
| HIGH | O(n²) string concatenation in splitStringIgnoringQuotes | `Utility.lua:83-120` | Refactored to use table.concat() |
| HIGH | And()/Or() create wrapper tables for non-table values | `Conditionals.lua:12,24-25` | Handle non-table values directly |
| HIGH | ValidateAura creates wrapper table for string args | `Conditionals.lua:383` | Destructure args inline |
| HIGH | ValidateCooldown creates wrapper table for string args | `Conditionals.lua:355` | Destructure args inline |
| HIGH | ValidateKnown creates wrapper table for string args | `Conditionals.lua:209` | Destructure args inline |
| MEDIUM | Combat log handler creates intermediate args table | `Core.lua:1423` | Pass args directly without intermediate table |
| BUG | rawhp references wrong field (rawphp) | `Conditionals.lua:822` | Fixed typo |
| BUG | notype references wrong field (type) | `Conditionals.lua:856` | Fixed reference |

---

## Not Fixed (Future Work)

### High Priority

| Issue | File | Lines | Description |
|-------|------|-------|-------------|
| Closure creation in 40+ keyword functions | `Conditionals.lua` | 554-937 | Keywords like `stance`, `buff`, `cooldown` create new closures on every evaluation by passing `function(v)` to Or()/And(). Could be inlined. |
| pairs() iterators in OnUpdate | `Core.lua` | 1023-1030, 1033-1037 | Sequence iteration and spell_tracking cleanup create iterator objects every 0.2s |
| IndexActionSlot string concatenation | `Generic.lua` | 166 | Creates `name..(rank and ("("..rank..")") or "")` string on every slot index |
| IndexItems() table creation | `Generic.lua` | 78-148 | Creates new table for each item on every BAG_UPDATE event |

### Medium Priority

| Issue | File | Lines | Description |
|-------|------|-------|-------------|
| Closure creation in DoTarget | `Core.lua` | 797-807 | Creates new `action` closure every /target command |
| Closure creation in DoUse | `Core.lua` | 844-855 | Creates new `action` closure every /use command |
| Closure creation in DoEquip* | `Core.lua` | 902-922 | Creates new `action` closure every equip command |
| Closure creation in DoUnshift | `Core.lua` | 938-943 | Creates new `action` closure every /unshift command |
| String operations in CancelAura | `Conditionals.lua` | 92 | `string.lower(string.gsub(auraName, "_"," "))` creates 2 strings |
| String operations in CheckChanneled | `Conditionals.lua` | 170-171 | Two gsub allocations per call |
| String operations in ValidateCreatureType | `Conditionals.lua` | 341, 346 | Multiple string.lower() calls |
| String operations in HasWeaponEquipped | `Conditionals.lua` | 131-136 | Multiple string.find() with captures |
| /target lowercase in loop | `Console.lua` | 99-116 | `string.lower(name)` called in loop for party/raid matching |
| spell_tracking table fragmentation | `Core.lua` | 1035 | Setting entries to nil fragments the table |

### Low Priority

| Issue | File | Lines | Description |
|-------|------|-------|-------------|
| AddCombatLogEntry internal table | `Core.lua` | 101 | Still creates args table internally (caller fixed, function not) |
| Empty SPELLS_CHANGED handler | `Generic.lua` | 258-259 | Registered event but handler does nothing |
| Grid.lua duplicates CreateFrames | `Grid.lua` | 32-112 | Copy-pastes entire function instead of post-hooking |
| Some extensions don't unregister ADDON_LOADED | Various | - | Continue receiving events after target addon loads |
| Duplicate mouseoverUnit declaration | `Init.lua` | 14-15 | Different capitalization (`mouseoverUnit` vs `mouseOverUnit`) |

### Bugs (Not Critical)

| Issue | File | Lines | Description |
|-------|------|-------|-------------|
| pfUI typo | `Compatibility/pfUI.lua` | 20 | `hook.origininal()` should be `hook.original()` |
| Bongos string concat per macro | `Compatibility/Bongos.lua` | 4 | Creates `"BActionButton" .. slot` on every macro execution |

---

## Implementation Notes for Future Fixes

### Eliminating Closure Creation in Keywords

The biggest remaining optimization would be inlining the closure in keyword functions. Current pattern:

```lua
stance = function(conditionals)
    local i = CleveRoids.GetCurrentShapeshiftIndex()
    return Or(conditionals.stance, function (v)  -- Creates closure!
        return (i == tonumber(v))
    end)
end,
```

Fixed pattern (inline the check):

```lua
stance = function(conditionals)
    local i = CleveRoids.GetCurrentShapeshiftIndex()
    local stances = conditionals.stance
    if type(stances) ~= "table" then
        return i == tonumber(stances)
    end
    for _, v in stances do
        if i == tonumber(v) then return true end
    end
    return false
end,
```

This would need to be applied to 40+ keyword functions.

### Replacing pairs() with next()

To avoid iterator allocation:

```lua
-- Current (creates iterator):
for _, sequence in pairs(CleveRoids.Sequences) do

-- Fixed (no iterator):
local key, sequence = next(CleveRoids.Sequences)
while key do
    -- process sequence
    key, sequence = next(CleveRoids.Sequences, key)
end
```

### Pre-computing Strings

For IndexActionSlot, cache the formatted name:

```lua
-- Instead of computing every time:
local actionSlotName = name..(rank and ("("..rank..")") or "")

-- Cache on the spell object during IndexSpells:
spell.nameWithRank = spell.name..(spell.rank and ("("..spell.rank..")") or "")
```

### Debouncing BAG_UPDATE

IndexItems runs on every BAG_UPDATE, which can fire rapidly:

```lua
local itemIndexPending = false
function CleveRoids.Frame:BAG_UPDATE()
    if not itemIndexPending then
        itemIndexPending = true
        -- Defer to next OnUpdate tick
    end
end
```

---

## Estimated Impact

| Fix Category | Estimated Reduction |
|--------------|---------------------|
| IndexActionBars removal (DONE) | 50-70% of idle churn |
| And()/Or() table wrapping (DONE) | 10-15% |
| Validate* table wrapping (DONE) | 5-10% |
| splitString O(n²) fix (DONE) | Variable (parsing only) |
| Keyword closure elimination | 10-20% (during macro use) |
| pairs() replacement | 5-10% |
| IndexItems debouncing | Variable (bag changes) |

The fixes in PR #1 address the critical idle churn. The remaining issues primarily affect memory during active macro usage.
