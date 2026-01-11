# Conditionals.lua Analysis

## Summary

`Conditionals.lua` (958 lines) implements the conditional evaluation system for CleveRoidMacros. It provides:

1. **Logic Operators**: `And()` and `Or()` functions for combining multiple condition checks
2. **Target Validation**: Functions to validate targets based on help/harm and existence
3. **State Checks**: Stance/form detection, stealth, combat, channeling states
4. **Resource Validation**: HP, power (mana/rage/energy), combo points with numeric comparisons
5. **Aura System**: Buff/debuff detection on player and units with duration/stack tracking
6. **Equipment Checks**: Weapon type and gear equipped detection
7. **Cooldown System**: Spell and item cooldown tracking with GCD awareness
8. **Keywords Table**: 60+ conditional keywords mapped to evaluation functions

This file **does not parse** macro text - parsing occurs in `Core.lua`. This file provides the evaluation functions that are called after parsing produces a `conditionals` table.

---

## Key Data Structures

### CleveRoids.Keywords (Lines 541-958)

The central dispatch table mapping conditional names to evaluation functions:

```lua
CleveRoids.Keywords = {
    exists = function(conditionals) ... end,
    help = function(conditionals) ... end,
    harm = function(conditionals) ... end,
    stance = function(conditionals) ... end,
    -- ... 60+ entries
}
```

**Memory Note**: This table is created once at load time - not a memory concern.

### CleveRoids.operators (Defined in Utility.lua:177-190)

Static lookup table for operator symbols:

```lua
CleveRoids.operators = {
    ["<"] = "lt", ["lt"] = "<",
    [">"] = "gt", ["gt"] = ">",
    ["="] = "eq", ["eq"] = "=",
    -- etc.
}
```

### CleveRoids.comparators (Defined in Utility.lua:192-205)

Static function table for numeric comparisons:

```lua
CleveRoids.comparators = {
    lt  = function(a, b) return (a <  b) end,
    gt  = function(a, b) return (a >  b) end,
    -- etc.
}
```

### External Dependencies

- `CleveRoids.Localized.Spells` - Localized spell name lookups
- `CleveRoids.auraTextures` - Texture-to-spell-name mappings (non-SuperWoW)
- `CleveRoids.WeaponTypeNames` - Weapon type definitions
- `CleveRoids.CurrentSpell` - Current casting state
- `CleveRoids.spell_tracking` - Unit spell cast tracking (SuperWoW)

---

## Parsing Functions

**Important**: Parsing is NOT in this file. Parsing occurs in `Core.lua` (lines 456-537) in the `GetParsedMsg` function. The `conditionals` table is pre-built before any functions in `Conditionals.lua` are called.

### How Parsing Works (Core.lua reference)

```lua
-- Core.lua:456-537
function CleveRoids.GetParsedMsg(args)
    -- Creates conditionals table
    -- Parses [condition:arg1/arg2,condition2:arg3] blocks
    -- Returns msg, conditionals table
end
```

Key parsing operations that allocate:

1. **Line 459**: `string.gsub()` to strip `?` prefix - creates new string
2. **Line 460**: `string.find()` to extract condition block
3. **Line 461**: `string.find()` and `string.sub()` for action extraction
4. **Line 466**: `string.gsub()` to strip rank info
5. **Lines 513-516**: Multiple `string.gsub()` calls per argument
6. **Line 519**: `string.find()` for operator/amount extraction
7. **Line 524**: `table.insert()` creates table entries

---

## Evaluation Functions

### Logic Operators (Lines 9-36)

```lua
local function And(t, func) -- Lines 9-20
local function Or(t, func)  -- Lines 22-36
```

**MEMORY CONCERN - Line 12 and 24-25**:
```lua
if type(t) ~= "table" then
    t = { [1] = t }  -- Creates new table every call!
end
```

This creates a temporary table every time a non-table value is passed. This happens frequently because simple conditionals like `[combat]` pass boolean `true` rather than a table.

### Target Validation (Lines 44-70)

```lua
function CleveRoids.CheckHelp(target, help)      -- Lines 44-51
function CleveRoids.IsValidTarget(target, help)  -- Lines 57-70
```

No significant allocations - uses only comparisons and API calls.

### Shapeshift/Stance (Lines 74-88)

```lua
function CleveRoids.GetCurrentShapeshiftIndex()  -- Lines 74-88
```

No allocations - returns integer.

### CancelAura (Lines 90-105)

```lua
function CleveRoids.CancelAura(auraName)
    auraName = string.lower(string.gsub(auraName, "_"," "))  -- Line 92
```

**MEMORY CONCERN**: Creates two new strings every call (gsub result, then lower result).

### Equipment Checks (Lines 110-143)

```lua
function CleveRoids.HasGearEquipped(gearId)      -- Lines 110-113
function CleveRoids.HasWeaponEquipped(weaponType) -- Lines 118-143
```

**MEMORY CONCERN - Lines 131-136**:
```lua
local _,_,itemId = string.find(slotLink,"item:(%d+)")
-- ...
local fist = string.find(subtype,"^Fist")
local _,_,subtype = string.find(subtype,"%s?(%S+)$")
```

Multiple `string.find()` calls with captures create intermediate strings.

### Channeled Spell Check (Lines 166-191)

```lua
function CleveRoids.CheckChanneled(channeledSpell)
    local spellName = string.gsub(CleveRoids.CurrentSpell.spellName, "%(.-%)%s*", "")  -- Line 170
    local channeled = string.gsub(channeledSpell, "%(.-%)%s*", "")  -- Line 171
```

**MEMORY CONCERN**: Two `string.gsub()` allocations per call.

### Numeric Validations (Lines 193-330)

All follow the same pattern:

```lua
function CleveRoids.ValidatePower(unit, operator, amount)
    if not unit or not operator or not amount then return false end
    local powerPercent = 100 / UnitManaMax(unit) * UnitMana(unit)
    if CleveRoids.operators[operator] then
        return CleveRoids.comparators[operator](powerPercent, amount)
    end
    return false
end
```

**No significant allocations** - pure arithmetic and table lookups.

Functions in this category:
- `ValidatePower` (Lines 241-250)
- `ValidateRawPower` (Lines 257-266)
- `ValidatePowerLost` (Lines 273-282)
- `ValidateHp` (Lines 289-298)
- `ValidateRawHp` (Lines 305-314)
- `ValidateHpLost` (Lines 321-330)
- `ValidateComboPoints` (Lines 193-202)

### Creature Type Validation (Lines 337-349)

```lua
function CleveRoids.ValidateCreatureType(creatureType, target)
    local ct = string.lower(creatureType)  -- Line 341
```

**MEMORY CONCERN**: `string.lower()` creates new string.

### Known Spell/Talent Validation (Lines 204-227)

```lua
function CleveRoids.ValidateKnown(args)
    if type(args) ~= "table" then
        args = { name = args }  -- Line 209 - Creates table!
    end
    -- ...
    local rank = spell and string.gsub(spell.rank, "Rank ", "") or talent  -- Line 218
```

**MEMORY CONCERNS**:
- Line 209: Creates temporary table
- Line 218: `string.gsub()` allocation

### Cooldown System (Lines 352-491)

```lua
function CleveRoids.ValidateCooldown(args, ignoreGCD)
    if type(args) ~= "table" then
        args = {name = args}  -- Line 355 - Creates table!
    end
```

**MEMORY CONCERN**: Table creation for simple cooldown checks.

### Aura Validation (Lines 367-438)

```lua
function CleveRoids.ValidateAura(unit, args, isbuff)
    if type(args) ~= "table" then
        args = {name = args}  -- Line 383 - Creates table!
    end
```

**MEMORY CONCERN**: The most frequently called function, creates a temporary table when passed a simple spell name string.

The while loop (lines 391-411) iterates through all buffs/debuffs - no allocations in the loop itself.

---

## Memory Concerns - Detailed Analysis

### Critical Issues

#### 1. Closure Creation in Keywords Table (Lines 541-958)

Every keyword evaluation creates closures passed to `And()` or `Or()`:

```lua
stance = function(conditionals)
    local i = CleveRoids.GetCurrentShapeshiftIndex()
    return Or(conditionals.stance, function (v)  -- NEW CLOSURE EVERY CALL
        return (i == tonumber(v))
    end)
end,
```

**Impact**: Each macro execution creates 1 closure per conditional used.

**Affected Keywords** (with closure creation):
- `stance` (Line 554-558)
- `form` (Line 561-565)
- `mod` (Line 568-575)
- `nomod` (Line 577-584)
- `casting` (Line 612-617)
- `nocasting` (Line 619-624)
- `zone` (Line 626-632)
- `nozone` (Line 634-640)
- `equipped` (Line 642-646)
- `noequipped` (Line 648-652)
- `reactive` (Line 662-666)
- `noreactive` (Line 668-672)
- `member` (Line 674-680)
- `group` (Line 698-709)
- `checkchanneled` (Line 711-715)
- `buff` (Line 717-721)
- `nobuff` (Line 723-727)
- `debuff` (Line 729-733)
- `nodebuff` (Line 735-739)
- `mybuff` (Line 741-745)
- `nomybuff` (Line 747-751)
- `mydebuff` (Line 753-757)
- `nomydebuff` (Line 759-763)
- `power` (Line 765-770)
- `mypower` (Line 772-777)
- `rawpower` (Line 779-784)
- `myrawpower` (Line 786-791)
- `powerlost` (Line 793-798)
- `mypowerlost` (Line 800-805)
- `hp` (Line 807-812)
- `myhp` (Line 814-819)
- `rawhp` (Line 821-826)
- `myrawhp` (Line 828-833)
- `hplost` (Line 835-840)
- `myhplost` (Line 842-847)
- `type` (Line 849-853)
- `notype` (Line 855-859)
- `cooldown` (Line 861-865)
- `nocooldown` (Line 867-871)
- `cdgcd` (Line 873-877)
- `nocdgcd` (Line 879-883)
- `targeting` (Line 893-897)
- `notargeting` (Line 899-903)
- `inrange` (Line 913-918)
- `noinrange` (Line 920-925)
- `combo` (Line 927-931)
- `nocombo` (Line 933-937)
- `known` (Line 939-943)
- `noknown` (Line 945-949)

#### 2. Temporary Table Wrapping (Lines 12, 24-25, 209, 355, 383)

The `And()` and `Or()` functions wrap non-table values:
```lua
if type(t) ~= "table" then
    t = { [1] = t }
end
```

#### 3. String Operations

| Location | Operation | Allocation |
|----------|-----------|------------|
| Line 92 | `string.gsub + string.lower` | 2 strings |
| Line 131-136 | `string.find` with captures | Multiple strings |
| Line 170-171 | `string.gsub` x2 | 2 strings |
| Line 218 | `string.gsub` | 1 string |
| Line 341, 346, 348 | `string.lower` | 3 strings |

---

## Hot Paths

Functions called during every macro execution (in order of frequency):

### Tier 1 - Called Every Frame (with macro spam)

1. **`And()` / `Or()`** - Called for every conditional check
2. **`CleveRoids.Keywords[k](conditionals)`** - Dispatches to specific checks
3. **`CleveRoids.CheckHelp()`** - Called for targeting validation
4. **`CleveRoids.IsValidTarget()`** - Called for most conditionals

### Tier 2 - Called Per-Conditional

5. **`CleveRoids.ValidateAura()`** - For buff/debuff checks (very common)
6. **`CleveRoids.ValidateCooldown()`** - For cooldown checks
7. **`CleveRoids.GetCurrentShapeshiftIndex()`** - For stance/form checks

### Tier 3 - Called Based on Macro Content

8. **`CleveRoids.ValidateHp/Power/etc`** - Resource checks
9. **`CleveRoids.HasWeaponEquipped()`** - Equipment checks
10. **`CleveRoids.CheckChanneled()`** - Channel checks

---

## Recommendations

### HIGH PRIORITY

#### 1. Eliminate Closure Creation in Or()/And() Calls

**Current** (creates closure every call):
```lua
-- Line 554-558
stance = function(conditionals)
    local i = CleveRoids.GetCurrentShapeshiftIndex()
    return Or(conditionals.stance, function (v)
        return (i == tonumber(v))
    end)
end,
```

**Fixed** (inline the check):
```lua
stance = function(conditionals)
    local i = CleveRoids.GetCurrentShapeshiftIndex()
    local stances = conditionals.stance
    if type(stances) ~= "table" then
        return i == tonumber(stances)
    end
    for _, v in pairs(stances) do
        if i == tonumber(v) then return true end
    end
    return false
end,
```

**Apply to all 40+ keywords that create closures.**

#### 2. Fix And()/Or() Table Wrapping

**Current** (Lines 12, 24-25):
```lua
if type(t) ~= "table" then
    t = { [1] = t }
end
```

**Fixed** (handle non-table inline):
```lua
local function Or(t, func)
    if type(func) ~= "function" then return false end
    if type(t) ~= "table" then
        return func(t) == true
    end
    for k, v in pairs(t) do
        if func(v) then return true end
    end
    return false
end
```

#### 3. Fix ValidateAura Table Wrapping

**Current** (Line 382-384):
```lua
if type(args) ~= "table" then
    args = {name = args}
end
```

**Fixed**:
```lua
local argName = type(args) == "table" and args.name or args
local argOperator = type(args) == "table" and args.operator or nil
local argAmount = type(args) == "table" and args.amount or nil
local checkStacks = type(args) == "table" and args.checkStacks or nil
-- Use these local variables instead of args.X throughout
```

### MEDIUM PRIORITY

#### 4. Cache String Operations in CancelAura

**Current** (Line 92):
```lua
auraName = string.lower(string.gsub(auraName, "_"," "))
```

**Fixed** (pre-normalize at parse time, not evaluation time).

#### 5. Cache CheckChanneled String Operations

**Current** (Lines 170-171):
```lua
local spellName = string.gsub(CleveRoids.CurrentSpell.spellName, "%(.-%)%s*", "")
local channeled = string.gsub(channeledSpell, "%(.-%)%s*", "")
```

**Fixed**: Store normalized spell names at parse/cast time.

#### 6. Pre-lowercase Creature Types

**Current** (Lines 341, 346):
```lua
local ct = string.lower(creatureType)
-- ...
if string.lower(creatureType) == "boss" then
```

**Fixed**: Normalize at parse time, store lowercase in conditionals table.

### LOW PRIORITY

#### 7. Cache Weapon Type Lookups

**Lines 131-136** perform repeated `string.find()` calls. Consider caching equipped weapon info on PLAYER_EQUIPMENT_CHANGED events.

#### 8. ValidateKnown Table Wrap

**Line 209**:
```lua
if type(args) ~= "table" then
    args = { name = args }
end
```

Same fix as ValidateAura - destructure inline.

---

## Estimated Memory Impact

With a typical macro like:
```
/cast [stance:1/2,nocooldown:Spell,mybuff:Buff] Spell
```

**Current allocations per execution**:
- 3 closures (stance, nocooldown, mybuff keywords)
- 1-3 table wraps in And()/Or()
- 1 table wrap in ValidateCooldown
- 1 table wrap in ValidateAura
- **Total: ~6-8 table allocations + 3 closures per execution**

At 60 FPS with macro spam: **360-480 allocations/second**

With fixes: **0 allocations per execution** (all logic inlined)

---

## Code Quality Notes

1. **Duplicate Code** (Lines 24-28): The `Or()` function has duplicate table type check
2. **Bug in rawhp** (Line 822): References `conditionals.rawphp` (typo, should be `conditionals.rawhp`)
3. **Inconsistent Nil Handling**: Some functions return `false`, others return `nil`
4. **notype Bug** (Line 856): Uses `conditionals.type` instead of `conditionals.notype`

---

## File Dependencies

```
Conditionals.lua
├── Requires: Utility.lua (operators, comparators, kmods)
├── Requires: Localization.lua (spell names, creature types)
├── Requires: Init.lua (CleveRoids table, playerClass)
├── Used by: Core.lua (keyword evaluation in DoWithConditionals)
└── Uses: WoW API (Unit*, GetSpell*, GetPlayerBuff*, etc.)
```
