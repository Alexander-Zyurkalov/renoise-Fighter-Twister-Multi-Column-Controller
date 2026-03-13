-- column_controls_spec.lua
-- Unit tests for the ColumnControls module using busted
--
-- Run: busted --lua=lua5.1 column_controls_spec.lua

--------------------------------------------------------------------
-- Stubs & helpers
--------------------------------------------------------------------

-- Stub automation_helpers BEFORE requiring column_controls
local automation_helpers_stub = {
    get_all_track_automations = function()
        return {}
    end,
    get_automation_and_prev_point = function(_param)
        return nil, nil
    end,
}
package.loaded["automation_helpers"] = automation_helpers_stub

-- Default color config shared by all tests
local function make_color_config()
    return {
        NOTE_COLOR = 50,
        EMPTY_NOTE_COLOR = 40,
        OTHER_PARAM_COLOR = 66,
        EMPTY_COLOR = 64,
        FX_COLOR = 70,
        EMPTY_FX_COLOR = 75,
        EFFECT_COLOR = 80,
        EMPTY_EFFECT_COLOR = 85,
        CURSOR_COLOR = 30,
        AUTOMATION_COLOR = 90,
        AUTOMATION_SCALING_COLOR = 100,
        AUTOMATION_PREV_SCALING_COLOR = 100,
        EMPTY_AUTOMATION_COLOR = 110,
    }
end

-- A minimal stub column-param object
-- Mimics the interface: getter, setter, is_absent, min_value, max_value, default_value
local function make_param_stub(opts)
    opts = opts or {}
    local stored_value = opts.initial or 0
    local absent = opts.absent or false
    local min_val = opts.min or 0
    local max_val = opts.max or 127
    local default_val = opts.default or 0

    return {
        getter = function(_self, _col)
            return stored_value
        end,
        setter = function(_self, _col, v, _idx)
            stored_value = v
        end,
        is_absent = function(_self, _col)
            return absent
        end,
        min_value = function(_self, _col)
            return min_val
        end,
        max_value = function(_self, _col)
            return max_val
        end,
        default_value = function(_self, _col)
            return default_val
        end,
        -- test helpers to change state between assertions
        _set_stored = function(v)
            stored_value = v
        end,
        _set_absent = function(v)
            absent = v
        end,
    }
end

-- Build a fake renoise global with configurable state
local function install_renoise(overrides)
    overrides = overrides or {}

    local note_col_stub = { volume_value = 64, panning_value = 64, delay_value = 0,
                            effect_number_value = 0, effect_amount_value = 0, note_value = 48 }
    local effect_col_stub = { number_value = 0, amount_value = 0 }

    local line_stub = {
        note_columns = overrides.note_columns or { note_col_stub },
        effect_columns = overrides.effect_columns or { effect_col_stub },
    }

    local track_stub = {
        visible_note_columns = overrides.visible_note_columns or 1,
        visible_effect_columns = overrides.visible_effect_columns or 0,
        volume_column_visible = overrides.volume_column_visible or false,
        panning_column_visible = overrides.panning_column_visible or false,
        delay_column_visible = overrides.delay_column_visible or false,
        sample_effects_column_visible = overrides.sample_effects_column_visible or false,
    }

    local pattern_stub = {
        number_of_lines = overrides.number_of_lines or 64,
    }

    local selected_line_value = line_stub
    if overrides.selected_line_nil then
        selected_line_value = nil
    elseif overrides.selected_line then
        selected_line_value = overrides.selected_line
    end

    local edit_mode_value = true
    if overrides.edit_mode ~= nil then
        edit_mode_value = overrides.edit_mode
    end

    local song_stub = {
        selected_track = track_stub,
        selected_track_index = 1,
        selected_line = selected_line_value,
        selected_line_index = overrides.selected_line_index or 1,
        selected_pattern = pattern_stub,
        selected_sequence_index = 1,
        selected_note_column_index = 0,
        selected_effect_column_index = 0,
        selection_in_pattern = nil,
        selected_automation_parameter = nil,
        transport = { edit_mode = edit_mode_value },
    }

    local window_stub = {
        active_lower_frame = 0,
    }

    _G.renoise = {
        song = function()
            return song_stub
        end,
        app = function()
            return { window = window_stub }
        end,
        ApplicationWindow = {
            LOWER_FRAME_TRACK_AUTOMATION = 42,
        },
    }

    return {
        song = song_stub,
        track = track_stub,
        line = line_stub,
        pattern = pattern_stub,
        window = window_stub,
        note_col = note_col_stub,
        effect_col = effect_col_stub,
    }
end

-- Feedback recorder: captures all send_midi_feedback / send_color_feedback calls
local function make_feedback_spy()
    local calls = { midi = {}, color = {} }
    return {
        calls = calls,
        send_midi = function(cc, value)
            table.insert(calls.midi, { cc = cc, value = value })
        end,
        send_color = function(cc, color)
            table.insert(calls.color, { cc = cc, color = color })
        end,
        reset = function()
            calls.midi = {}
            calls.color = {}
        end,
    }
end

-- Factory: build a ColumnControls instance wired to stubs
local ColumnControls = require("column_controls")

local function build_ctrl(overrides)
    overrides = overrides or {}
    local fb = overrides.feedback or make_feedback_spy()
    local params = overrides.column_params or {
        volume = make_param_stub({ initial = 64, max = 128, min = 0, default = 0 }),
        pan = make_param_stub({ initial = 64, max = 128, min = 0, default = 64 }),
        delay = make_param_stub({ initial = 0, max = 255, min = 0, default = 0 }),
        note = make_param_stub({ initial = 48, max = 120, min = 0, default = 0, absent = true }),
        fx_number_xx = make_param_stub(),
        fx_number_yy = make_param_stub(),
        fx_amount_x = make_param_stub(),
        fx_amount_y = make_param_stub(),
        effect_number_xx = make_param_stub(),
        effect_number_yy = make_param_stub(),
        effect_amount_x = make_param_stub(),
        effect_amount_y = make_param_stub(),
        automation = make_param_stub(),
        automation_scaling = make_param_stub(),
        automation_prev_scaling = make_param_stub(),
    }

    local ctrl = ColumnControls.new({
        available_ccs = overrides.available_ccs or { 12, 13, 14, 15, 8, 9, 10, 11 },
        number_of_steps = overrides.number_of_steps or 3,
        column_params = params,
        color_config = overrides.color_config or make_color_config(),
        send_midi_feedback = fb.send_midi,
        send_color_feedback = fb.send_color,
        search_backwards = overrides.search_backwards or function()
            return 0
        end,
    })

    return ctrl, fb, params
end


--------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------

describe("ColumnControls", function()

    -- ============================================================
    -- new()
    -- ============================================================
    describe("new()", function()
        it("returns an object with empty controls and last_controls", function()
            install_renoise()
            local ctrl = build_ctrl()
            assert.is_table(ctrl.controls)
            assert.is_table(ctrl.last_controls)
            assert.are.equal(0, #ctrl.controls) -- hash part, but # on empty is 0
            assert.are.equal(0, #ctrl.last_controls)
        end)

        it("stores config fields on the instance", function()
            install_renoise()
            local ctrl = build_ctrl({ number_of_steps = 7, available_ccs = { 1, 2, 3 } })
            assert.are.equal(7, ctrl.number_of_steps)
            assert.are.same({ 1, 2, 3 }, ctrl.available_ccs)
        end)
    end)

    -- ============================================================
    -- get_column_color()
    -- ============================================================
    describe("get_column_color()", function()
        local ctrl, C

        before_each(function()
            install_renoise()
            ctrl = build_ctrl()
            C = make_color_config()
        end)

        it("returns CURSOR_COLOR for cursor type", function()
            assert.are.equal(C.CURSOR_COLOR, ctrl:get_column_color("cursor", true, nil))
            assert.are.equal(C.CURSOR_COLOR, ctrl:get_column_color("cursor", false, nil))
        end)

        it("returns AUTOMATION_COLOR when automated", function()
            local param = { is_automated = true }
            assert.are.equal(C.AUTOMATION_COLOR, ctrl:get_column_color("automation", true, param))
        end)

        it("returns EMPTY_AUTOMATION_COLOR when not automated", function()
            local param = { is_automated = false }
            assert.are.equal(C.EMPTY_AUTOMATION_COLOR, ctrl:get_column_color("automation", true, param))
        end)

        it("returns EMPTY_AUTOMATION_COLOR when automation_parameter is nil", function()
            assert.are.equal(C.EMPTY_AUTOMATION_COLOR, ctrl:get_column_color("automation", false, nil))
        end)

        it("returns AUTOMATION_SCALING_COLOR when automated", function()
            local param = { is_automated = true }
            assert.are.equal(C.AUTOMATION_SCALING_COLOR, ctrl:get_column_color("automation_scaling", true, param))
        end)

        it("returns EMPTY_AUTOMATION_COLOR for automation_scaling when not automated", function()
            local param = { is_automated = false }
            assert.are.equal(C.EMPTY_AUTOMATION_COLOR, ctrl:get_column_color("automation_scaling", true, param))
        end)

        it("returns AUTOMATION_PREV_SCALING_COLOR when prev_point exists", function()
            local param = { is_automated = true }
            automation_helpers_stub.get_automation_and_prev_point = function()
                return {}, { time = 1, value = 0.5 }
            end
            assert.are.equal(C.AUTOMATION_PREV_SCALING_COLOR,
                    ctrl:get_column_color("automation_prev_scaling", true, param))
        end)

        it("returns EMPTY_AUTOMATION_COLOR for automation_prev_scaling when no prev_point", function()
            local param = { is_automated = true }
            automation_helpers_stub.get_automation_and_prev_point = function()
                return {}, nil
            end
            assert.are.equal(C.EMPTY_AUTOMATION_COLOR,
                    ctrl:get_column_color("automation_prev_scaling", true, param))
        end)

        it("returns EMPTY_AUTOMATION_COLOR for automation_prev_scaling when not automated", function()
            local param = { is_automated = false }
            assert.are.equal(C.EMPTY_AUTOMATION_COLOR,
                    ctrl:get_column_color("automation_prev_scaling", true, param))
        end)

        -- Note column with/without value
        it("returns NOTE_COLOR when note has value", function()
            assert.are.equal(C.NOTE_COLOR, ctrl:get_column_color("note", true, nil))
        end)

        it("returns EMPTY_NOTE_COLOR when note is empty", function()
            assert.are.equal(C.EMPTY_NOTE_COLOR, ctrl:get_column_color("note", false, nil))
        end)

        -- FX types
        for _, fx_type in ipairs({ "fx_number_xx", "fx_number_yy", "fx_amount_x", "fx_amount_y" }) do
            it("returns FX_COLOR for " .. fx_type .. " with value", function()
                assert.are.equal(C.FX_COLOR, ctrl:get_column_color(fx_type, true, nil))
            end)
            it("returns EMPTY_FX_COLOR for " .. fx_type .. " without value", function()
                assert.are.equal(C.EMPTY_FX_COLOR, ctrl:get_column_color(fx_type, false, nil))
            end)
        end

        -- Effect types
        for _, eff_type in ipairs({ "effect_number_xx", "effect_number_yy", "effect_amount_x", "effect_amount_y" }) do
            it("returns EFFECT_COLOR for " .. eff_type .. " with value", function()
                assert.are.equal(C.EFFECT_COLOR, ctrl:get_column_color(eff_type, true, nil))
            end)
            it("returns EMPTY_EFFECT_COLOR for " .. eff_type .. " without value", function()
                assert.are.equal(C.EMPTY_EFFECT_COLOR, ctrl:get_column_color(eff_type, false, nil))
            end)
        end

        -- Other params (volume, pan, delay)
        for _, param_type in ipairs({ "volume", "pan", "delay" }) do
            it("returns OTHER_PARAM_COLOR for " .. param_type .. " with value", function()
                assert.are.equal(C.OTHER_PARAM_COLOR, ctrl:get_column_color(param_type, true, nil))
            end)
            it("returns EMPTY_COLOR for " .. param_type .. " without value", function()
                assert.are.equal(C.EMPTY_COLOR, ctrl:get_column_color(param_type, false, nil))
            end)
        end
    end)

    -- ============================================================
    -- rebuild()
    -- ============================================================
    describe("rebuild()", function()
        it("assigns cursor to first CC", function()
            install_renoise({ visible_note_columns = 0, visible_effect_columns = 0 })
            local ctrl = build_ctrl({ available_ccs = { 10, 11, 12 } })
            ctrl:rebuild()

            assert.is_not_nil(ctrl.controls[10])
            assert.are.equal("cursor", ctrl.controls[10].type)
        end)

        it("assigns volume CCs for each visible note column when volume is visible", function()
            install_renoise({
                visible_note_columns = 2,
                visible_effect_columns = 0,
                volume_column_visible = true,
            })
            local ctrl = build_ctrl({ available_ccs = { 10, 11, 12, 13, 14 } })
            ctrl:rebuild()

            -- CC 10 = cursor, CC 11 = volume col 1, CC 12 = volume col 2
            assert.are.equal("cursor", ctrl.controls[10].type)
            assert.are.equal("volume", ctrl.controls[11].type)
            assert.are.equal(1, ctrl.controls[11].note_column_index)
            assert.are.equal("volume", ctrl.controls[12].type)
            assert.are.equal(2, ctrl.controls[12].note_column_index)
        end)

        it("assigns multiple param types per note column when several are visible", function()
            install_renoise({
                visible_note_columns = 1,
                visible_effect_columns = 0,
                volume_column_visible = true,
                panning_column_visible = true,
            })
            local ctrl = build_ctrl({ available_ccs = { 10, 11, 12, 13 } })
            ctrl:rebuild()

            assert.are.equal("cursor", ctrl.controls[10].type)
            assert.are.equal("volume", ctrl.controls[11].type)
            assert.are.equal("pan", ctrl.controls[12].type)
        end)

        it("assigns sample_effects columns (4 CCs per note column)", function()
            install_renoise({
                visible_note_columns = 1,
                visible_effect_columns = 0,
                sample_effects_column_visible = true,
            })
            local ctrl = build_ctrl({ available_ccs = { 0, 1, 2, 3, 4, 5 } })
            ctrl:rebuild()

            -- CC 0 = cursor, CCs 1-4 = fx params for note col 1
            assert.are.equal("fx_number_xx", ctrl.controls[1].type)
            assert.are.equal("fx_number_yy", ctrl.controls[2].type)
            assert.are.equal("fx_amount_x", ctrl.controls[3].type)
            assert.are.equal("fx_amount_y", ctrl.controls[4].type)
        end)

        it("assigns effect column CCs", function()
            install_renoise({
                visible_note_columns = 0,
                visible_effect_columns = 1,
            })
            local ctrl = build_ctrl({ available_ccs = { 0, 1, 2, 3, 4, 5 } })
            ctrl:rebuild()

            -- CC 0 = cursor, CCs 1-4 = effect params for effect col 1
            assert.are.equal("effect_number_xx", ctrl.controls[1].type)
            assert.are.equal(1, ctrl.controls[1].effect_column_index)
            assert.are.equal("effect_number_yy", ctrl.controls[2].type)
            assert.are.equal("effect_amount_x", ctrl.controls[3].type)
            assert.are.equal("effect_amount_y", ctrl.controls[4].type)
        end)

        it("assigns automation CCs when automations exist", function()
            local auto_param = { name = "Cutoff", is_automated = true }
            automation_helpers_stub.get_all_track_automations = function()
                return { auto_param }
            end

            install_renoise({ visible_note_columns = 0, visible_effect_columns = 0 })
            local ctrl = build_ctrl({ available_ccs = { 0, 1, 2, 3, 4 } })
            ctrl:rebuild()

            -- CC 0 = cursor, CC 1 = automation_prev_scaling, CC 2 = automation, CC 3 = automation_scaling
            assert.are.equal("automation_prev_scaling", ctrl.controls[1].type)
            assert.are.equal(auto_param, ctrl.controls[1].automation_parameter)
            assert.are.equal("automation", ctrl.controls[2].type)
            assert.are.equal("automation_scaling", ctrl.controls[3].type)

            -- restore
            automation_helpers_stub.get_all_track_automations = function()
                return {}
            end
        end)

        it("stops assigning when CCs are exhausted", function()
            install_renoise({
                visible_note_columns = 1,
                visible_effect_columns = 0,
                volume_column_visible = true,
                panning_column_visible = true,
                delay_column_visible = true,
            })
            -- Only 3 CCs: cursor + volume + pan; delay won't fit
            local ctrl = build_ctrl({ available_ccs = { 0, 1, 2 } })
            ctrl:rebuild()

            assert.are.equal("cursor", ctrl.controls[0].type)
            assert.are.equal("volume", ctrl.controls[1].type)
            assert.are.equal("pan", ctrl.controls[2].type)
            -- No delay assigned
            local count = 0
            for _ in pairs(ctrl.controls) do
                count = count + 1
            end
            assert.are.equal(3, count)
        end)

        it("resets disabled CCs from previous rebuild", function()
            install_renoise({
                visible_note_columns = 1,
                visible_effect_columns = 0,
                volume_column_visible = true,
            })
            local fb = make_feedback_spy()
            local ctrl = build_ctrl({ available_ccs = { 0, 1, 2, 3 }, feedback = fb })
            ctrl:rebuild()
            fb:reset()

            -- Now rebuild with volume hidden — CC 1 (was volume) should be reset
            renoise.song().selected_track.volume_column_visible = false
            ctrl:rebuild()

            -- Check that CC 1 was reset (send_midi_feedback(1, 0) and send_color_feedback(1, EMPTY_COLOR))
            local found_midi_reset = false
            for _, call in ipairs(fb.calls.midi) do
                if call.cc == 1 and call.value == 0 then
                    found_midi_reset = true
                end
            end
            assert.is_true(found_midi_reset, "Expected CC 1 to be reset via send_midi_feedback")

            local found_color_reset = false
            for _, call in ipairs(fb.calls.color) do
                if call.cc == 1 and call.color == 64 then
                    -- EMPTY_COLOR = 64
                    found_color_reset = true
                end
            end
            assert.is_true(found_color_reset, "Expected CC 1 color to be reset to EMPTY_COLOR")
        end)

        it("initializes last_controls for every assigned CC", function()
            install_renoise({
                visible_note_columns = 1,
                visible_effect_columns = 0,
                volume_column_visible = true,
            })
            local ctrl = build_ctrl({ available_ccs = { 5, 6, 7 }, number_of_steps = 4 })
            ctrl:rebuild()

            for cc, _ in pairs(ctrl.controls) do
                local lc = ctrl.last_controls[cc]
                assert.is_not_nil(lc, "last_controls should exist for CC " .. cc)
                assert.are.equal(0, lc.command)
                assert.are.equal(0, lc.count)
                assert.are.equal(4, lc.number_of_steps_to_change_value)
            end
        end)
    end)

    -- ============================================================
    -- search_backwards_for_value()
    -- ============================================================
    describe("search_backwards_for_value()", function()
        it("delegates to the search_backwards function with correct args", function()
            install_renoise()
            local captured = {}
            local ctrl = build_ctrl({
                search_backwards = function(song, is_eff, line_idx, col_idx, params)
                    captured = { song = song, is_eff = is_eff, line_idx = line_idx, col_idx = col_idx, params = params }
                    return 42
                end,
            })

            local result = ctrl:search_backwards_for_value("volume", 3, 10, "fake_song", true)
            assert.are.equal(42, result)
            assert.are.equal("fake_song", captured.song)
            assert.is_true(captured.is_eff)
            assert.are.equal(10, captured.line_idx)
            assert.are.equal(3, captured.col_idx)
        end)

        it("returns 0 for unknown column_type", function()
            install_renoise()
            local ctrl = build_ctrl()
            assert.are.equal(0, ctrl:search_backwards_for_value("nonexistent", 1, 1, nil, false))
        end)
    end)

    -- ============================================================
    -- has_value_at_current_position()
    -- ============================================================
    describe("has_value_at_current_position()", function()
        it("returns true for cursor type always", function()
            install_renoise()
            local ctrl = build_ctrl()
            assert.is_true(ctrl:has_value_at_current_position("cursor", 1, false, nil))
        end)

        it("returns true for automation when parameter is present", function()
            install_renoise()
            local ctrl = build_ctrl()
            assert.is_true(ctrl:has_value_at_current_position("automation", 0, false, { is_automated = true }))
        end)

        it("returns false for automation when parameter is nil", function()
            install_renoise()
            local ctrl = build_ctrl()
            assert.is_false(ctrl:has_value_at_current_position("automation", 0, false, nil))
        end)

        it("returns true for automation_scaling when parameter is present", function()
            install_renoise()
            local ctrl = build_ctrl()
            assert.is_true(ctrl:has_value_at_current_position("automation_scaling", 0, false, {}))
        end)

        it("checks prev_point for automation_prev_scaling", function()
            install_renoise()
            local ctrl = build_ctrl()
            automation_helpers_stub.get_automation_and_prev_point = function()
                return {}, { time = 1 }
            end
            assert.is_true(ctrl:has_value_at_current_position("automation_prev_scaling", 0, false, { is_automated = true }))

            automation_helpers_stub.get_automation_and_prev_point = function()
                return {}, nil
            end
            assert.is_false(ctrl:has_value_at_current_position("automation_prev_scaling", 0, false, { is_automated = true }))
        end)

        it("returns false for automation_prev_scaling when parameter is nil", function()
            install_renoise()
            local ctrl = build_ctrl()
            assert.is_false(ctrl:has_value_at_current_position("automation_prev_scaling", 0, false, nil))
        end)

        it("returns false when selected_line is nil", function()
            install_renoise({ selected_line_nil = true })
            local ctrl = build_ctrl()
            assert.is_false(ctrl:has_value_at_current_position("volume", 1, false, nil))
        end)

        it("returns true when param is not absent for note column", function()
            install_renoise()
            local ctrl, _, params = build_ctrl()
            params.volume._set_absent(false)
            assert.is_true(ctrl:has_value_at_current_position("volume", 1, false, nil))
        end)

        it("returns false when param is absent for note column", function()
            install_renoise()
            local ctrl, _, params = build_ctrl()
            params.volume._set_absent(true)
            assert.is_false(ctrl:has_value_at_current_position("volume", 1, false, nil))
        end)

        it("reads effect_columns when is_effect_column is true", function()
            install_renoise()
            local ctrl, _, params = build_ctrl()
            params.effect_number_xx._set_absent(false)
            assert.is_true(ctrl:has_value_at_current_position("effect_number_xx", 1, true, nil))
        end)

        it("returns false when column_index is out of range", function()
            install_renoise()
            local ctrl = build_ctrl()
            -- note_columns has 1 element, asking for index 5
            assert.is_false(ctrl:has_value_at_current_position("volume", 5, false, nil))
        end)

        it("returns false when column_index is 0", function()
            install_renoise()
            local ctrl = build_ctrl()
            assert.is_false(ctrl:has_value_at_current_position("volume", 0, false, nil))
        end)
    end)

    -- ============================================================
    -- get_current_column_value()
    -- ============================================================
    describe("get_current_column_value()", function()
        it("returns selected_line_index for cursor type", function()
            install_renoise({ selected_line_index = 17 })
            local ctrl = build_ctrl()
            local val, col, q = ctrl:get_current_column_value("cursor", 0, false, nil)
            assert.are.equal(17, val)
            assert.is_nil(col)
            assert.are.equal(1, q)
        end)

        it("returns automation getter value and computed quantum", function()
            install_renoise()
            local ctrl, _, params = build_ctrl()
            params.automation._set_stored(64)
            local auto_param = {
                value_quantum = 0.01,
                value_max = 1.0,
                value_min = 0.0,
            }
            local val, col, q = ctrl:get_current_column_value("automation", 0, false, auto_param)
            assert.are.equal(64, val)
            assert.are.equal(auto_param, col)
            -- value_quantum/(max-min)+min = 0.01/1+0 = 0.01, ceil(0.01*127) = ceil(1.27) = 2
            assert.are.equal(2, q)
        end)

        it("returns value_quantum of 1 when computed quantum is 0", function()
            install_renoise()
            local ctrl, _, params = build_ctrl()
            params.automation._set_stored(64)
            local auto_param = {
                value_quantum = 0.0,
                value_max = 1.0,
                value_min = 0.0,
            }
            local _, _, q = ctrl:get_current_column_value("automation", 0, false, auto_param)
            assert.are.equal(1, q)
        end)

        it("returns 0 when selected_line is nil", function()
            install_renoise({ selected_line_nil = true })
            local ctrl = build_ctrl()
            local val, col = ctrl:get_current_column_value("volume", 1, false, nil)
            assert.are.equal(0, val)
            assert.is_nil(col)
        end)

        it("returns stored value for a note column param", function()
            install_renoise()
            local ctrl, _, params = build_ctrl()
            params.volume._set_stored(100)
            params.volume._set_absent(false)
            local val, _, q = ctrl:get_current_column_value("volume", 1, false, nil)
            assert.are.equal(100, val)
            assert.are.equal(1, q)
        end)

        it("calls search_backwards when value is absent", function()
            install_renoise({ selected_line_index = 5 })
            local searched = false
            local ctrl, _, params = build_ctrl({
                search_backwards = function()
                    searched = true;
                    return 77
                end,
            })
            params.volume._set_absent(true)
            local val = ctrl:get_current_column_value("volume", 1, false, nil)
            assert.is_true(searched)
            assert.are.equal(77, val)
        end)

        it("returns 0 when column_index is out of range", function()
            install_renoise()
            local ctrl = build_ctrl()
            local val, col = ctrl:get_current_column_value("volume", 99, false, nil)
            assert.are.equal(0, val)
            assert.is_nil(col)
        end)

        it("returns 0 when column_params entry is missing", function()
            install_renoise()
            local ctrl = build_ctrl()
            -- "unknown_type" is not in column_params
            local val, col = ctrl:get_current_column_value("unknown_type", 1, false, nil)
            assert.are.equal(0, val)
            assert.is_nil(col)
        end)
    end)

    -- ============================================================
    -- set_selection()
    -- ============================================================
    describe("set_selection()", function()
        it("does nothing for cursor type", function()
            local env = install_renoise()
            local ctrl = build_ctrl()
            -- Should not error or change state
            ctrl:set_selection("cursor", 1, false, nil)
            assert.are.equal(0, env.song.selected_note_column_index)
        end)

        it("switches to automation view for automation type", function()
            local env = install_renoise()
            local ctrl = build_ctrl()
            local param = { name = "Volume" }
            ctrl:set_selection("automation", 0, false, param)
            assert.are.equal(42, env.window.active_lower_frame) -- LOWER_FRAME_TRACK_AUTOMATION
            assert.are.equal(param, env.song.selected_automation_parameter)
        end)

        it("switches to automation view for automation_scaling", function()
            local env = install_renoise()
            local ctrl = build_ctrl()
            ctrl:set_selection("automation_scaling", 0, false, { name = "X" })
            assert.are.equal(42, env.window.active_lower_frame)
        end)

        it("switches to automation view for automation_prev_scaling", function()
            local env = install_renoise()
            local ctrl = build_ctrl()
            ctrl:set_selection("automation_prev_scaling", 0, false, { name = "Y" })
            assert.are.equal(42, env.window.active_lower_frame)
        end)

        it("does not set automation parameter when nil", function()
            local env = install_renoise()
            local ctrl = build_ctrl()
            ctrl:set_selection("automation", 0, false, nil)
            assert.is_nil(env.song.selected_automation_parameter)
        end)

        it("sets note column index for non-effect column", function()
            local env = install_renoise()
            local ctrl = build_ctrl()
            ctrl:set_selection("volume", 2, false, nil)
            assert.are.equal(2, env.song.selected_note_column_index)
        end)

        it("sets effect column index for effect column", function()
            local env = install_renoise()
            env.track.visible_note_columns = 3
            local ctrl = build_ctrl()
            ctrl:set_selection("effect_number_xx", 1, true, nil)
            assert.are.equal(1, env.song.selected_effect_column_index)
            -- select_column = visible_note_columns + effect_col = 3 + 1 = 4
            assert.are.equal(4, env.song.selection_in_pattern.start_column)
        end)

        it("does nothing when selected_line is nil", function()
            local env = install_renoise({ selected_line_nil = true })
            local ctrl = build_ctrl()
            ctrl:set_selection("volume", 1, false, nil)
            assert.are.equal(0, env.song.selected_note_column_index)
        end)
    end)

    -- ============================================================
    -- map_to_midi_range()
    -- ============================================================
    describe("map_to_midi_range()", function()
        it("maps cursor value to 0-127 based on pattern length", function()
            install_renoise({ number_of_lines = 64 })
            local ctrl = build_ctrl()
            -- Line 1 -> 0, Line 64 -> 127
            assert.are.equal(0, ctrl:map_to_midi_range("cursor", 1, nil, nil))
            assert.are.equal(127, ctrl:map_to_midi_range("cursor", 64, nil, nil))
            -- Midpoint: (32-1)/(64-1) * 127 ≈ 62.5 -> floor(62.5 + 0.5) = 63... actually
            -- 31/63 * 127 = 62.492... + 0.5 = 62.992... -> floor = 62
            assert.are.equal(62, ctrl:map_to_midi_range("cursor", 32, nil, nil))
        end)

        it("returns 0 for cursor when pattern has 1 line", function()
            install_renoise({ number_of_lines = 1 })
            local ctrl = build_ctrl()
            assert.are.equal(0, ctrl:map_to_midi_range("cursor", 1, nil, nil))
        end)

        it("passes through automation values unchanged", function()
            install_renoise()
            local ctrl = build_ctrl()
            assert.are.equal(99, ctrl:map_to_midi_range("automation", 99, nil, nil))
            assert.are.equal(42, ctrl:map_to_midi_range("automation_scaling", 42, nil, nil))
            assert.are.equal(5, ctrl:map_to_midi_range("automation_prev_scaling", 5, nil, nil))
        end)

        it("returns 0 for unknown column_type", function()
            install_renoise()
            local ctrl = build_ctrl()
            assert.are.equal(0, ctrl:map_to_midi_range("nonexistent", 50, nil, nil))
        end)

        it("maps regular column value to 0-127 range", function()
            install_renoise()
            local ctrl, _, params = build_ctrl()
            -- volume: min=0, max=128
            -- value 64 -> (64-0)/128 * 127 = 63.5 -> 64
            local col = {} -- dummy column
            assert.are.equal(64, ctrl:map_to_midi_range("volume", 64, nil, col))
            -- value 0 -> 0
            assert.are.equal(0, ctrl:map_to_midi_range("volume", 0, nil, col))
            -- value 128 -> 127
            assert.are.equal(127, ctrl:map_to_midi_range("volume", 128, nil, col))
        end)

        it("returns 0 when range is 0", function()
            install_renoise()
            local params = {
                volume = {
                    getter = function()
                        return 0
                    end,
                    setter = function()
                    end,
                    is_absent = function()
                        return false
                    end,
                    min_value = function()
                        return 5
                    end,
                    max_value = function()
                        return 5
                    end, -- same as min -> range = 0
                    default_value = function()
                        return 5
                    end,
                },
            }
            local ctrl = build_ctrl({ column_params = params })
            assert.are.equal(0, ctrl:map_to_midi_range("volume", 5, nil, {}))
        end)
    end)

    -- ============================================================
    -- update_controller_for_column()
    -- ============================================================
    describe("update_controller_for_column()", function()
        it("sends midi feedback and color feedback", function()
            install_renoise({ selected_line_index = 1 })
            local fb = make_feedback_spy()
            local ctrl, _, params = build_ctrl({ feedback = fb })
            params.volume._set_stored(64)
            params.volume._set_absent(false)

            ctrl:update_controller_for_column("volume", 1, 10, false, nil)

            assert.is_true(#fb.calls.midi > 0, "Expected at least one midi feedback call")
            assert.are.equal(10, fb.calls.midi[1].cc)
            assert.is_true(#fb.calls.color > 0, "Expected at least one color feedback call")
            assert.are.equal(10, fb.calls.color[1].cc)
        end)
    end)

    -- ============================================================
    -- update_all()
    -- ============================================================
    describe("update_all()", function()
        it("sends feedback for every control in the controls table", function()
            install_renoise({ visible_note_columns = 1, volume_column_visible = true })
            local fb = make_feedback_spy()
            local ctrl, _, params = build_ctrl({
                feedback = fb,
                available_ccs = { 0, 1 },
            })
            params.volume._set_absent(false)
            ctrl:rebuild()
            fb:reset()

            ctrl:update_all()

            -- Should have 2 controls (cursor + volume), so 2 midi + 2 color calls
            assert.are.equal(2, #fb.calls.midi)
            assert.are.equal(2, #fb.calls.color)
        end)
    end)

    -- ============================================================
    -- modify_column_value()
    -- ============================================================
    describe("modify_column_value()", function()
        it("moves cursor line forward and sends feedback", function()
            local env = install_renoise({ selected_line_index = 5, number_of_lines = 64 })
            local fb = make_feedback_spy()
            local ctrl = build_ctrl({ feedback = fb })

            ctrl:modify_column_value("cursor", 0, 10, 1, false, nil)
            assert.are.equal(6, env.song.selected_line_index)
            assert.is_true(#fb.calls.midi > 0)
            assert.are.equal(make_color_config().CURSOR_COLOR, fb.calls.color[1].color)
        end)

        it("moves cursor line backward", function()
            local env = install_renoise({ selected_line_index = 5, number_of_lines = 64 })
            local ctrl = build_ctrl()
            ctrl:modify_column_value("cursor", 0, 10, -1, false, nil)
            assert.are.equal(4, env.song.selected_line_index)
        end)

        it("clamps cursor at line 1", function()
            local env = install_renoise({ selected_line_index = 1, number_of_lines = 64 })
            local ctrl = build_ctrl()
            ctrl:modify_column_value("cursor", 0, 10, -1, false, nil)
            assert.are.equal(1, env.song.selected_line_index)
        end)

        it("clamps cursor at last line", function()
            local env = install_renoise({ selected_line_index = 64, number_of_lines = 64 })
            local ctrl = build_ctrl()
            ctrl:modify_column_value("cursor", 0, 10, 1, false, nil)
            assert.are.equal(64, env.song.selected_line_index)
        end)

        it("does nothing when edit_mode is off (non-cursor)", function()
            install_renoise({ edit_mode = false })
            local fb = make_feedback_spy()
            local ctrl, _, params = build_ctrl({ feedback = fb })
            params.volume._set_stored(64)
            params.volume._set_absent(false)

            ctrl:modify_column_value("volume", 1, 10, 1, false, nil)
            assert.are.equal(0, #fb.calls.midi, "No MIDI feedback expected when edit_mode is off")
        end)

        it("increments value by quantum and sends feedback", function()
            install_renoise({ edit_mode = true })
            local fb = make_feedback_spy()
            local ctrl, _, params = build_ctrl({ feedback = fb })
            params.volume._set_stored(64)
            params.volume._set_absent(false)
            local set_called_with = nil
            local orig_setter = params.volume.setter
            params.volume.setter = function(self, col, v, idx)
                set_called_with = v
            end

            ctrl:modify_column_value("volume", 1, 10, 1, false, nil)
            -- quantum = 1, so new_value = 64 + 1 = 65
            assert.are.equal(65, set_called_with)
        end)

        it("decrements value by quantum", function()
            install_renoise({ edit_mode = true })
            local ctrl, _, params = build_ctrl()
            params.volume._set_stored(64)
            params.volume._set_absent(false)
            local set_called_with = nil
            params.volume.setter = function(self, col, v, idx)
                set_called_with = v
            end

            ctrl:modify_column_value("volume", 1, 10, -1, false, nil)
            assert.are.equal(63, set_called_with)
        end)

        it("clamps increment at max_value", function()
            install_renoise({ edit_mode = true })
            local ctrl, _, params = build_ctrl()
            params.volume._set_stored(128) -- at max
            params.volume._set_absent(false)
            local set_called_with = nil
            params.volume.setter = function(self, col, v, idx)
                set_called_with = v
            end

            ctrl:modify_column_value("volume", 1, 10, 1, false, nil)
            assert.are.equal(128, set_called_with)
        end)

        it("clamps decrement at min_value", function()
            install_renoise({ edit_mode = true })
            local ctrl, _, params = build_ctrl()
            params.volume._set_stored(0) -- at min
            params.volume._set_absent(false)
            local set_called_with = nil
            params.volume.setter = function(self, col, v, idx)
                set_called_with = v
            end

            ctrl:modify_column_value("volume", 1, 10, -1, false, nil)
            assert.are.equal(0, set_called_with)
        end)

        it("does nothing when column_params entry is missing", function()
            install_renoise({ edit_mode = true })
            local fb = make_feedback_spy()
            local ctrl = build_ctrl({ feedback = fb })
            -- "nonexistent" has no params entry -> should return early
            ctrl:modify_column_value("nonexistent", 1, 10, 1, false, nil)
            assert.are.equal(0, #fb.calls.midi)
        end)
    end)

    -- ============================================================
    -- is_ready_to_modify()
    -- ============================================================
    describe("is_ready_to_modify()", function()
        it("returns false when last_control does not exist for the CC", function()
            install_renoise()
            local ctrl = build_ctrl()
            assert.is_false(ctrl:is_ready_to_modify(176, 1, 99, 1))
        end)

        it("returns false when channel does not match control_channel", function()
            install_renoise({ visible_note_columns = 1, volume_column_visible = true })
            local ctrl = build_ctrl({ available_ccs = { 0, 1 }, number_of_steps = 1 })
            ctrl:rebuild()

            -- CC 1 exists, but channel 2 != control_channel 1
            assert.is_false(ctrl:is_ready_to_modify(176, 2, 1, 1))
        end)

        it("returns false when CC has no control mapping", function()
            install_renoise({ visible_note_columns = 0 })
            local ctrl = build_ctrl({ available_ccs = { 0 }, number_of_steps = 1 })
            ctrl:rebuild()

            -- CC 0 = cursor, CC 5 has no mapping
            -- But also no last_controls entry for CC 5 -> already returns false
            assert.is_false(ctrl:is_ready_to_modify(176, 1, 5, 1))
        end)

        it("accumulates count and fires after reaching threshold", function()
            install_renoise({ visible_note_columns = 1, volume_column_visible = true })
            local ctrl = build_ctrl({ available_ccs = { 0, 1 }, number_of_steps = 3 })
            ctrl:rebuild()

            -- CC 1 = volume, steps = 3
            -- Call 1: count goes to 1, not ready
            assert.is_false(ctrl:is_ready_to_modify(176, 1, 1, 1))
            -- Call 2: count goes to 2, not ready
            assert.is_false(ctrl:is_ready_to_modify(176, 1, 1, 1))
            -- Call 3: count goes to 3, ready!
            assert.is_true(ctrl:is_ready_to_modify(176, 1, 1, 1))
        end)

        it("resets count after exceeding threshold", function()
            install_renoise({ visible_note_columns = 1, volume_column_visible = true })
            local ctrl = build_ctrl({ available_ccs = { 0, 1 }, number_of_steps = 2 })
            ctrl:rebuild()

            -- CC 1, steps = 2
            ctrl:is_ready_to_modify(176, 1, 1, 1) -- count=1
            assert.is_true(ctrl:is_ready_to_modify(176, 1, 1, 1))  -- count=2, fires
            -- count=3 > threshold, wraps to 1
            assert.is_false(ctrl:is_ready_to_modify(176, 1, 1, 1)) -- count=1 (wrapped)
            assert.is_true(ctrl:is_ready_to_modify(176, 1, 1, 1))  -- count=2, fires again
        end)

        it("resets count when message differs", function()
            install_renoise({ visible_note_columns = 1, volume_column_visible = true })
            local ctrl = build_ctrl({ available_ccs = { 0, 1 }, number_of_steps = 3 })
            ctrl:rebuild()

            -- Build up count toward threshold with command=176
            ctrl:is_ready_to_modify(176, 1, 1, 1) -- count=1
            ctrl:is_ready_to_modify(176, 1, 1, 1) -- count=2

            -- Different command resets count back to 1
            assert.is_false(ctrl:is_ready_to_modify(192, 1, 1, 1)) -- count=1 (reset)
            assert.is_false(ctrl:is_ready_to_modify(192, 1, 1, 1)) -- count=2
            assert.is_true(ctrl:is_ready_to_modify(192, 1, 1, 1))  -- count=3, fires
        end)

        it("fires immediately when number_of_steps is 1", function()
            install_renoise({ visible_note_columns = 1, volume_column_visible = true })
            local ctrl = build_ctrl({ available_ccs = { 0, 1 }, number_of_steps = 1 })
            ctrl:rebuild()

            assert.is_true(ctrl:is_ready_to_modify(176, 1, 1, 1))
        end)
    end)
end)