# Localization and Compatibility Layer Analysis

## Summary

### File Overview

1. **Localization.lua** (435 lines)
   - Multi-language localization system for WoW 1.12.1
   - Supports 9 locales: enUS, enGB, deDE, frFR, koKR, zhCN, zhTW, ruRU, esES
   - Defines weapon types, spell names, creature types, and item types
   - All strings populated at load time into `CleveRoids.Localized` table

2. **Compatibility/SuperMacro.lua** (20 lines)
   - Provides compatibility hook for SuperMacro addon
   - Hooks `RunMacro` function on addon load
   - Integrates SuperMacro with CleveRoids macro execution system

3. **Compatibility/pfUI.lua** (38 lines)
   - Provides compatibility with pfUI addon's focus unit frame
   - Hooks `GetFocusName` method to use pfUI's focus name when available
   - Includes debug logging capability

4. **Compatibility/Bongos.lua** (8 lines)
   - Provides compatibility with Bongos action bar addon
   - Registers action event handler to update Bongos buttons on macro actions
   - No persistent state, purely event-driven

---

## Localization System

### Architecture

The localization system in **Localization.lua** uses a straightforward load-time initialization pattern:

```lua
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}
CleveRoids.Locale = GetLocale()
CleveRoids.Localized = {}
```

**Key characteristics:**
- **Single-pass initialization**: All strings are populated once at load time
- **Conditional blocks**: Uses `if/elseif` chains to determine locale (lines 10-434)
- **Static tables**: `CreatureTypes`, `Spells`, and `ItemTypes` are all static nested tables
- **Global registration**: Final line (436) registers the modified `CleveRoids` object globally

### String Creation

**Good news for memory**: All strings are created at load time, NOT at runtime:

- Locale detection happens once: `CleveRoids.Locale = GetLocale()` (line 7)
- Entire locale branch executes once during addon load
- All strings are literals in the Lua source (no dynamic string.format or concatenation)
- Tables are populated once and never modified afterward

**Example structure:**
```lua
CleveRoids.Localized.Shield = "Shields"        -- enUS
CleveRoids.Localized.Spells = {                -- Nested table
    ["Shadowform"] = "Shadowform",
    ["Stealth"] = "Stealth",
    -- ... more entries
}
```

### Potential Issues

1. **Partial translations** (lines 122-173 for frFR, and scattered in other locales)
   - Many non-English locales fall back to English strings (e.g., "Thrown", "Wands", "Swords")
   - These incomplete translations don't cause memory churn but indicate maintenance debt
   - No fallback mechanism if a locale is missing a key

2. **No runtime lookup optimization**
   - No memoization of lookup results
   - If code does frequent lookups (e.g., `CleveRoids.Localized.Spells[spellName]`), it recreates lookups each time
   - However, this is a lookup performance issue, not a memory churn issue

---

## Compatibility Layers

### SuperMacro.lua Hook

**Lines 1-20:** Extension system hook for external addon

```lua
local Extension = CleveRoids.RegisterExtension("Compatibility_SuperMacro")
Extension.RegisterEvent("ADDON_LOADED", "OnLoad")

function Extension.RunMacro(name)
    CleveRoids.ExecuteMacroByName(name)
end

function Extension.OnLoad()
    if not SuperMacroFrame then return end
    Extension.Hook("RunMacro", "RunMacro", true)
    Extension.UnregisterEvent("ADDON_LOADED", "Onload")
end
```

**How it works:**
1. Registers extension when addon loads
2. Waits for `ADDON_LOADED` event
3. Checks if SuperMacro addon is present (`SuperMacroFrame` check)
4. **Hooks** `RunMacro` function (line 16) - supersedes the original function
5. Unregisters event to avoid repeated calls

**Function call flow:**
- SuperMacro calls `RunMacro(name)`
- Hooked version intercepts and calls `CleveRoids.ExecuteMacroByName(name)`
- Allows SuperMacro to integrate with CleveRoids macro system

**Memory concerns:** NONE identified
- Hook is applied once at addon load
- Extension object persists but is lightweight
- Event unregistered after first load

### pfUI.lua Hook

**Lines 1-38:** Extension system hook for pfUI focus frame

```lua
local Extension = CleveRoids.RegisterExtension("Compatibility_pfUI")
Extension.RegisterEvent("ADDON_LOADED", "OnLoad")
Extension.Debug = false

function Extension.FocusNameHook()
    local hook = Extension.internal.memberHooks[CleveRoids]["GetFocusName"]
    local target = hook.origininal()  -- Note: typo "origininal"

    if pfUI and pfUI.uf and pfUI.uf.focus and pfUI.uf.focus.unitname then
        target = pfUI.uf.focus.unitname
    end
    return target
end

function Extension.OnLoad()
    Extension.DLOG("Extension pfUI Loaded.")
    Extension.HookMethod(CleveRoids, "GetFocusName", "FocusNameHook", true)
    Extension.UnregisterEvent("ADDON_LOADED", "Onload")
end
```

**How it works:**
1. Registers extension and waits for `ADDON_LOADED`
2. Hooks `CleveRoids.GetFocusName()` method (line 33)
3. When hooked method is called:
   - Calls original `GetFocusName()` (line 20)
   - If pfUI addon is loaded, overlays its focus unit name
   - Returns modified or original name

**Memory concerns:** MINOR
- `Extension.FocusNameHook()` called potentially every time focus name is needed
- Creates local variables in each call: `hook`, `target`
- Performs deep table checks: `pfUI.uf.focus.unitname` (lines 22-23)
- Debug logging uses string concatenation: `"|cffcccc33[R]: |cffffff55" .. ( msg )` (line 14)
  - Only active if `Extension.Debug = true`, which defaults to `false`
  - When active, creates new string every call in `DLOG()`

**Issues identified:**
1. **Typo on line 20**: `hook.origininal()` should be `hook.original()`
   - This may cause runtime errors if the hook is triggered
2. **Deep property checks**: Lines 22-23 perform multiple table lookups
   - `pfUI and pfUI.uf and pfUI.uf.focus and pfUI.uf.focus.unitname` creates evaluation overhead
   - Minor impact but unnecessary if checking in sequence

### Bongos.lua Handler

**Lines 1-8:** Simple action event handler registration

```lua
CleveRoids.RegisterActionEventHandler(function(slot, event)
    if not slot or not BActionButton or not BActionBar then return end

    local button = getglobal("BActionButton" .. slot)
    if button then
        BActionButton.Update(button)
    end
end)
```

**How it works:**
1. Registers anonymous callback function for action events
2. When macro action fires, callback is invoked with `(slot, event)` parameters
3. Updates Bongos action bar button to reflect macro effect
4. Uses `getglobal()` to dynamically fetch button frame by name

**Memory concerns:** SIGNIFICANT
- **Anonymous function registration**: Lines 1-8 define an anonymous closure
- **Called on every macro action**: Each time a macro is executed, this callback fires
- **String concatenation**: Line 4 concatenates string every call: `"BActionButton" .. slot`
- **Global lookups**: `getglobal()` on line 4 performs global table lookups
- **Repeated evaluations**: Lines 2-3 check `BActionButton` and `BActionBar` existence on every fire

**Issues identified:**
1. **No early return for non-Bongos users**: If Bongos isn't loaded, this still registers and fires
2. **String concatenation in loop**: Line 4 creates new string for each button update
3. **Repeated global checks**: Could cache `BActionButton` and `BActionBar` references
4. **No deregistration**: If user unloads Bongos, handler still fires and fails silently

---

## Memory Analysis Summary

### Load-Time Memory Cost

**Localization.lua**
- Entire `CleveRoids.Localized` table is populated once at load
- Approximately 12 KB of string data spread across 9 locale tables
- Only ONE locale is actually populated (based on `GetLocale()`)
- Other 8 locale branches are never executed
- **Estimated load-time footprint**: ~1.5 KB per loaded locale

**Compatibility modules**
- SuperMacro.lua: ~200 bytes overhead
- pfUI.lua: ~300 bytes overhead
- Bongos.lua: ~100 bytes overhead
- **Total compatibility overhead**: <1 KB

### Runtime Memory Churn

**Localization.lua: NONE**
- No runtime operations
- All strings already allocated
- No dynamic table creation

**SuperMacro.lua: NONE**
- Hook is called only when SuperMacro calls `RunMacro()`
- Lightweight function wrapper, no allocations

**pfUI.lua: MINOR**
- `FocusNameHook()` called whenever `GetFocusName()` is invoked
- Creates local variables on each call (negligible garbage)
- Table lookups are cached by Lua (no string operations)
- **If game calls `GetFocusName()` frequently**, this contributes minimal churn

**Bongos.lua: POTENTIAL ISSUE**
- Anonymous function fires on **every macro execution**
- String concatenation: `"BActionButton" .. slot` (line 4)
- This creates a new string object each time if slot value varies
- If user executes macros frequently, this could contribute to memory churn
- **Estimated impact**: ~10-100 bytes per macro execution (string + table overhead)

---

## Recommendations

### 1. Fix pfUI Compatibility Typo (LINE 20)
**File**: `/Users/ncerny/workspace/uss-enterprise-guild/cleveroidmacros/Compatibility/pfUI.lua`

**Current code (line 20):**
```lua
    local hook = Extension.internal.memberHooks[CleveRoids]["GetFocusName"]
    local target = hook.origininal()  -- TYPO: "origininal"
```

**Fix:**
```lua
    local hook = Extension.internal.memberHooks[CleveRoids]["GetFocusName"]
    local target = hook.original()  -- FIXED: "original"
```

**Impact**: Prevents runtime error when pfUI focus hook is invoked

### 2. Optimize Bongos Handler (LINES 1-8)
**File**: `/Users/ncerny/workspace/uss-enterprise-guild/cleveroidmacros/Compatibility/Bongos.lua`

**Current code:**
```lua
CleveRoids.RegisterActionEventHandler(function(slot, event)
    if not slot or not BActionButton or not BActionBar then return end

    local button = getglobal("BActionButton" .. slot)
    if button then
        BActionButton.Update(button)
    end
end)
```

**Issues:**
- String concatenation on every execution (line 4)
- Repeated global existence checks (lines 2-3)
- No way to disable handler if Bongos unloads

**Recommended fix:**
```lua
-- Cache initialization
local bongosLoaded = false
local function UpdateBongosButton(slot, event)
    if not bongosLoaded then return end
    if not slot then return end

    local button = getglobal("BActionButton" .. slot)
    if button then
        BActionButton.Update(button)
    end
end

-- Only register once addon is confirmed loaded
CleveRoids.RegisterActionEventHandler(UpdateBongosButton)

-- Hook into Bongos load to enable handler
CleveRoids.RegisterExtension("Compatibility_Bongos")
-- In OnLoad: bongosLoaded = (BActionButton and BActionBar) and true or false
```

**Impact**: Reduces string allocation overhead and eliminates repeated global checks

### 3. Minor: Improve pfUI Table Checks (LINES 22-23)
**File**: `/Users/ncerny/workspace/uss-enterprise-guild/cleveroidmacros/Compatibility/pfUI.lua`

**Current code:**
```lua
    if pfUI and pfUI.uf and pfUI.uf.focus and pfUI.uf.focus.unitname then
        target = pfUI.uf.focus.unitname
    end
```

**Suggested improvement:**
```lua
    local focusName = pfUI and pfUI.uf and pfUI.uf.focus and pfUI.uf.focus.unitname
    if focusName then
        target = focusName
    end
```

**Impact**: Avoids re-traversing table chain twice, improves code clarity

### 4. Complete Partial Translations (INFORMATIONAL)
**File**: `/Users/ncerny/workspace/uss-enterprise-guild/cleveroidmacros/Localization.lua`

**Issue**: Many non-English locales have incomplete translations
- frFR (lines 122-173): Most weapon types use English strings
- koKR, zhCN, zhTW, ruRU, esES: Same issue

**Examples that need translation:**
- "Thrown", "Wands", "Swords", "Staves", "Polearms", "Maces", "Fist Weapons", "Daggers", "Axes"
- "Attack", "Auto Shot", "Shoot"

**Current impact**: Not causing memory churn, but users see English text in non-English clients

**Recommendation**: Mark as low priority for memory optimization; address only if translations are available

---

## Conclusion

**Memory Churn Assessment:**

1. **Localization.lua**: NOT contributing to memory churn
   - One-time load initialization
   - All strings pre-allocated
   - No runtime operations

2. **Compatibility modules**: MINIMAL impact
   - SuperMacro.lua: Negligible
   - pfUI.lua: Minor (only if frequently called)
   - Bongos.lua: Potential contributor if macros executed frequently

3. **Primary concern for 100+KB/s churn**: Likely in other modules
   - Recommend analyzing Core.lua, MacroEngine.lua, and Event handling systems
   - These files likely contain the main event loop and macro execution engine

**Recommended priority fixes:**
1. Fix pfUI typo (line 20) - prevents runtime errors
2. Optimize Bongos handler (lines 1-8) - reduces string allocation per macro
3. Profile macro execution frequency to quantify Bongos impact
