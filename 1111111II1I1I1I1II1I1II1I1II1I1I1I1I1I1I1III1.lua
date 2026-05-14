local function extract_line_number(err)
    local text = tostring(err or "")
    local num = text:match(":(%d+):")
    return tonumber(num)
end

local function panic()
    error("I love your try pookie! (anti-tamper tripped)", 0)
end

local function trigger_invalid_pow_error()
    local bad = "naCud"
    return "dummy" / (11092000 - bad ^ 8329902)
end

local function trigger_invalid_pow_error_2()
    local bad = "UwhoTF9Lo"
    return "dummy" / (15140264 - bad ^ 15173052)
end

local function trigger_invalid_concat_error()
    -- Intentional type error
    return 1 .. {}
end

local function trigger_invalid_index_error()
    local t = nil
    return t[1]
end

local function resolve_loader()
    local env = getfenv and getfenv(print)
    local loader = loadstring or load
    if not loader and env then
        loader = env.load or env.loadstring
    end
    if not loader then
        local ok, mod = pcall(function()
            return require("@lune/luau")
        end)
        loader = ok and mod and mod.load or nil
    end
    return loader
end

local function safe_random(min, max)
    -- Fallback in case math.random or math.randomseed are messed with
    local ok, r = pcall(math.random, min, max)
    if not ok or type(r) ~= "number" then
        return (os.time() % (max - min + 1)) + min
    end
    return r
end

local function shuffle_table(t)
    local n = #t
    for i = n, 2, -1 do
        local j = safe_random(1, i)
        t[i], t[j] = t[j], t[i]
    end
end

local function anti_tamper_passed()
    local passed = true
    local internal_trust_score = 0
    local internal_penalty = 0

    -- decoy state: looks important but is only partially used
    local honey_flags = {
        probeA = false,
        probeB = false,
        probeC = false,
        noise = 0,
        checksum = 0,
    }

    -- 1) Simple probing of getgenv / metamethods (silently)
    pcall(function()
        local g = getgenv and getgenv() or _G
        g["Dark was here :)"] = function() end
        honey_flags.probeA = true
    end)

    -- 2) Basic pcall / flag test
    local probe_flag = false
    local pcall_sets_flag = pcall(function()
        probe_flag = true
    end) and probe_flag

    if pcall_sets_flag then
        internal_trust_score = internal_trust_score + 5
    else
        internal_penalty = internal_penalty + 5
    end

    -- 3) Extra: xpcall consistency check
    local xpcall_ok = false
    local xpcall_handler_called = false
    if xpcall then
        xpcall_ok = xpcall(function()
            error("xpcall-test", 0)
        end, function(msg)
            xpcall_handler_called = msg == "xpcall-test"
        end)
        -- xpcall should return false on error
        if (xpcall_ok == false) and xpcall_handler_called then
            internal_trust_score = internal_trust_score + 5
        else
            internal_penalty = internal_penalty + 3
        end
    else
        -- environments without xpcall are unusual, so small penalty
        internal_penalty = internal_penalty + 1
    end

    -- 4) Core random / checksum loop + error pattern matching
    local random = safe_random
    local unpack_fn = (table and table.unpack) or unpack
    local select_fn = select

    local loop_count = random(33, 99) -- 10x more iterations-ish
    local checksum_actual = 0
    local checksum_expected = 0

    -- baseline error to compare
    local first_error = ({ pcall(function()
        return trigger_invalid_pow_error()
    end) })[2]
    local first_line = extract_line_number(first_error)

    -- sanity check: baseline line must exist
    if not first_line then
        passed = false
        internal_penalty = internal_penalty + 10
    else
        internal_trust_score = internal_trust_score + 3
    end

    -- Additional reference errors for cross-line checks
    local pow2_error = ({ pcall(function()
        return trigger_invalid_pow_error_2()
    end) })[2]
    local pow2_line = extract_line_number(pow2_error)

    local concat_error = ({ pcall(function()
        return trigger_invalid_concat_error()
    end) })[2]
    local concat_line = extract_line_number(concat_error)

    local index_error = ({ pcall(function()
        return trigger_invalid_index_error()
    end) })[2]
    local index_line = extract_line_number(index_error)

    -- If any of these fail to have line numbers, environment is suspicious
    if not pow2_line or not concat_line or not index_line then
        internal_penalty = internal_penalty + 8
    else
        internal_trust_score = internal_trust_score + 4
    end

    -- Variation patterns for error strings
    local base_error_text = tostring(first_error or "")
    local error_morphs = {}
    do
        local seeds = { 13, 29, 47, 71, 89 }
        for i = 1, #seeds do
            local new_num = random(1, 10000)
            local morph = base_error_text:gsub(":(%d+):", ":" .. tostring(new_num) .. ":")
            error_morphs[#error_morphs + 1] = morph
        end
        shuffle_table(error_morphs)
    end

    -- 5) Randomized loops with mixed behavior
    for i = 1, loop_count do
        local width = random(4, 128)
        local forced_byte = random(0, 255)
        local forced_index = random(1, width)
        local should_throw = random(1, 3) == 1

        local expected_error = error_morphs[(i % #error_morphs) + 1]

        local result = {
            pcall(function()
                -- Randomly re-check line equality between pow errors
                if random(1, 4) == 1 or i == loop_count then
                    local second_error = ({ pcall(function()
                        return trigger_invalid_pow_error_2()
                    end) })[2]
                    local second_line = extract_line_number(second_error)
                    local lines_match = (first_line == second_line)
                    passed = passed and lines_match
                    if not lines_match then
                        internal_penalty = internal_penalty + 10
                    else
                        internal_trust_score = internal_trust_score + 1
                    end
                end

                -- occasional cross checks between concat/index errors
                if random(1, 5) == 1 then
                    local ce_line = extract_line_number(concat_error)
                    local ie_line = extract_line_number(index_error)
                    -- lines likely differ; the *existence* is what matters
                    if not ce_line or not ie_line then
                        internal_penalty = internal_penalty + 4
                        passed = false
                    end
                end

                if should_throw then
                    -- raise morph error with level 0, expecting exact string
                    error(expected_error, 0)
                end

                -- build random bytes with forced position, using select/unpack combos
                local bytes = {}
                for j = 1, width do
                    bytes[j] = random(0, 255)
                end
                bytes[forced_index] = forced_byte

                if select_fn and random(1, 2) == 1 then
                    -- use select to create offset view
                    return select_fn(1, unpack_fn(bytes))
                else
                    return unpack_fn(bytes)
                end
            end),
        }

        if should_throw then
            local ok = result[1]
            local err = result[2]
            local eq = (ok == false) and (err == expected_error)
            passed = passed and eq
            if eq then
                internal_trust_score = internal_trust_score + 2
            else
                internal_penalty = internal_penalty + 5
            end
        else
            local ok = result[1]
            passed = passed and ok
            if ok then
                local val = result[forced_index + 1]
                checksum_actual = (checksum_actual + (val or 0)) % 256
                checksum_expected = (checksum_expected + forced_byte) % 256
            else
                internal_penalty = internal_penalty + 3
            end
        end

        -- track some honey noise
        honey_flags.noise = (honey_flags.noise + width + forced_byte + (should_throw and 1 or 0)) % 65535
    end

    -- 6) loader probing
    local loader = resolve_loader()
    local loader_probe_ok = true

    if loader then
        local function run_loader(code)
            local loaded, load_err = loader(code)
            if not loaded then
                return nil, load_err
            end
            local ok, a, b = pcall(loaded)
            if not ok then
                -- error from running the loaded chunk
                return nil, a
            end
            -- expected pcall inside code: return pcall(...)
            return a, b
        end

        -- script A – no leading newline
        local a_ok, a_err = run_loader("return pcall(function()return 1/'abc'end)")
        local line_a = extract_line_number(a_err)

        -- script B – leading newline
        local b_ok, b_err = run_loader("\nreturn pcall(function()return 1/'abc'end)")
        local line_b = extract_line_number(b_err)

        -- script C – leading comments and extra lines
        local c_ok, c_err = run_loader([[
-- test
-- test2
return pcall(function()
    return 1/"abc"
end)
        ]])
        local line_c = extract_line_number(c_err)

        -- we expect lines to differ between scripts with different layout
        loader_probe_ok = (line_a and line_b and line_c)
            and (line_a ~= line_b)
            and (line_b ~= line_c)
            and (line_a ~= line_c)

        if loader_probe_ok then
            internal_trust_score = internal_trust_score + 7
        else
            internal_penalty = internal_penalty + 12
        end
    else
        -- no loader found: not fatal, but suspicious in some contexts
        internal_penalty = internal_penalty + 2
    end

    -- 7) checksum integrity
    local checksum_ok = (checksum_actual == checksum_expected)
    if checksum_ok then
        internal_trust_score = internal_trust_score + 10
    else
        internal_penalty = internal_penalty + 10
    end

    honey_flags.checksum = (checksum_actual ~ checksum_expected)

    -- 8) optional debug.* presence check (if available)
    do
        local dbg = debug
        if dbg and dbg.getinfo then
            local ok_dbg, info = pcall(dbg.getinfo, panic, "Sl")
            if ok_dbg and info and info.currentline and info.short_src then
                internal_trust_score = internal_trust_score + 3
                honey_flags.probeB = true
            else
                internal_penalty = internal_penalty + 3
            end
        else
            internal_penalty = internal_penalty + 1
        end
    end

    -- 9) final aggregation of all conditions
    passed = passed
        and pcall_sets_flag
        and checksum_ok
        and loader_probe_ok

    -- convert trust/penalty into final decision
    local final_score = internal_trust_score - internal_penalty

    -- A bit of extra randomness to avoid trivial static patching:
    local random_bias = safe_random(-3, 3)
    final_score = final_score + random_bias

    -- honey flag: if someone naively flips 'passed', this still might gate
    local honey_gate = (honey_flags.probeA or honey_flags.probeB) and (honey_flags.checksum ~= 0)

    if not honey_gate then
        final_score = final_score - 5
    else
        final_score = final_score + 2
    end

    if final_score < 0 then
        passed = false
    end

    return passed
end

local ok = anti_tamper_passed()
if not ok then
    panic()
end

return ok
