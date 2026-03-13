-- column_controls_spec.lua
-- Unit tests for the ColumnControls module using busted
--
-- Run: busted --lua=lua5.1 column_controls_spec.lua

--------------------------------------------------------------------
-- Stubs & helpers
--------------------------------------------------------------------

-- Stub automation_helpers (only needed by PatternAdapter, not by ColumnControls itself now)
package.loaded["automation_helpers"] = {}

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
        -- test helpers
        _set_stored = function(v)
            stored_value = v
        end,
        _set_absent = function(v)
            absent = v
        end,
    }
end

-- Build stub adapter (replaces the old install_renoise approach)
local function make_adapter_stub(opts)
    opts = opts or {}

    local note_col_stub = { volume_value = 64, panning_value = 64, delay_value = 0,
                            effect_number_value = 0, effect_amount_value = 0, note_value = 48 }
    local effect_col_stub = { number_value = 0, amount_value = 0 }

    local default_line = {
        note_columns = opts.note_columns or { note_col_stub },
        effect_columns = opts.effect_columns or { effect_col_stub },
    }

    local default_track = {
        visible_note_columns = opts.visible_note_columns or 1,
        visible_effect_columns = opts.visible_effect_columns or 0,
        volume_column_visible = opts.volume_column_visible or false,
        panning_column_visible = opts.panning_column_visible or false,
        delay_column_visible = opts.delay_column_visible or false,
        sample_effects_column_visible = opts.sample_effects_column_visible or false,
    }

    -- Mutable state for test assertions
    local state = {
        line_index = opts.line_index or 1,
        note_column_index = 0,
        effect_column_index = 0,
        selection = nil,
        automation_view_param = nil,
    }

    local track_ref = opts.track or default_track

    local has_line = not opts.no_selected_line
    local edit_mode_val = true
    if opts.edit_mode ~= nil then
        edit_mode_val = opts.edit_mode
    end

    local adapter = { state = state }

    function adapter:get_track()
        return track_ref
    end

    function adapter:get_selected_line()
        if has_line then
            return default_line
        end
        return nil
    end

    function adapter:get_selected_line_index()
        return state.line_index
    end

    function adapter:set_selected_line_index(idx)
        state.line_index = idx
    end

    function adapter:get_number_of_lines()
        return opts.number_of_lines or 64
    end

    function adapter:is_edit_mode()
        return edit_mode_val
    end

    function adapter:set_note_column_index(idx)
        state.note_column_index = idx
    end

    function adapter:set_effect_column_index(idx)
        state.effect_column_index = idx
    end

    function adapter:set_selection(line_index, column_index)
        state.selection = { line = line_index, column = column_index }
    end

    function adapter:supports_automation()
        if opts.supports_automation == nil then
            return false
        end
        return opts.supports_automation
    end

    function adapter:enter_automation_view(param)
        state.automation_view_param = param
    end

    function adapter:get_all_automations()
        return opts.automations or {}
    end

    function adapter:get_automation_and_prev_point(param)
        if opts.get_automation_and_prev_point then
            return opts.get_automation_and_prev_point(param)
        end
        return nil, nil
    end

    return adapter
end

-- Feedback recorder
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
    local adapter = overrides.adapter or make_adapter_stub(overrides)
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
        adapter = adapter,
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

    return ctrl, fb, params, adapter
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
            local ctrl = build_ctrl()
            assert.is_table(ctrl.controls)
            assert.is_table(ctrl.last_controls)
        end)

        it("stores config fields on the instance", function()
            local ctrl = build_ctrl({ number_of_steps = 7, available_ccs = { 1, 2, 3 } })
            assert.are.equal(7, ctrl.number_of_steps)
            assert.are.same({ 1, 2, 3 }, ctrl.available_ccs)
        end)

        it("stores adapter reference", function()
            local adapter = make_adapter_stub()
            local ctrl = build_ctrl({ adapter = adapter })
            assert.are.equal(adapter, ctrl.adapter)
        end)
    end)

    -- ============================================================
    -- get_column_color()
    -- ============================================================
    describe("get_column_color()", function()
        local ctrl, C

        before_each(function()
            ctrl = build_ctrl()
            C = make_color_config()
        end)

        it("returns CURSOR_COLOR for cursor type", function()
            assert.are.equal(C.CURSOR_COLOR, ctrl:get_column_color("cursor", true, nil))
            assert.are.equal(C.CURSOR_COLOR, ctrl:get_column_color("cursor", false, nil))
        end)

        it("returns AUTOMATION_COLOR when automated", function()
            assert.are.equal(C.AUTOMATION_COLOR, ctrl:get_column_color("automation", true, { is_automated = true }))
        end)

        it("returns EMPTY_AUTOMATION_COLOR when not automated", function()
            assert.are.equal(C.EMPTY_AUTOMATION_COLOR, ctrl:get_column_color("automation", true, { is_automated = false }))
        end)

        it("returns EMPTY_AUTOMATION_COLOR when automation_parameter is nil", function()
            assert.are.equal(C.EMPTY_AUTOMATION_COLOR, ctrl:get_column_color("automation", false, nil))
        end)

        it("returns AUTOMATION_SCALING_COLOR when automated", function()
            assert.are.equal(C.AUTOMATION_SCALING_COLOR, ctrl:get_column_color("automation_scaling", true, { is_automated = true }))
        end)

        it("returns EMPTY_AUTOMATION_COLOR for automation_scaling when not automated", function()
            assert.are.equal(C.EMPTY_AUTOMATION_COLOR, ctrl:get_column_color("automation_scaling", true, { is_automated = false }))
        end)

        it("returns AUTOMATION_PREV_SCALING_COLOR when prev_point exists", function()
            local adapter = make_adapter_stub({
                get_automation_and_prev_point = function()
                    return {}, { time = 1, value = 0.5 }
                end,
            })
            ctrl = build_ctrl({ adapter = adapter })
            assert.are.equal(C.AUTOMATION_PREV_SCALING_COLOR,
                    ctrl:get_column_color("automation_prev_scaling", true, { is_automated = true }))
        end)

        it("returns EMPTY_AUTOMATION_COLOR for automation_prev_scaling when no prev_point", function()
            local adapter = make_adapter_stub({
                get_automation_and_prev_point = function()
                    return {}, nil
                end,
            })
            ctrl = build_ctrl({ adapter = adapter })
            assert.are.equal(C.EMPTY_AUTOMATION_COLOR,
                    ctrl:get_column_color("automation_prev_scaling", true, { is_automated = true }))
        end)

        it("returns EMPTY_AUTOMATION_COLOR for automation_prev_scaling when not automated", function()
            assert.are.equal(C.EMPTY_AUTOMATION_COLOR,
                    ctrl:get_column_color("automation_prev_scaling", true, { is_automated = false }))
        end)

        it("returns NOTE_COLOR when note has value", function()
            assert.are.equal(C.NOTE_COLOR, ctrl:get_column_color("note", true, nil))
        end)

        it("returns EMPTY_NOTE_COLOR when note is empty", function()
            assert.are.equal(C.EMPTY_NOTE_COLOR, ctrl:get_column_color("note", false, nil))
        end)

        for _, fx_type in ipairs({ "fx_number_xx", "fx_number_yy", "fx_amount_x", "fx_amount_y" }) do
            it("returns FX_COLOR for " .. fx_type .. " with value", function()
                assert.are.equal(C.FX_COLOR, ctrl:get_column_color(fx_type, true, nil))
            end)
            it("returns EMPTY_FX_COLOR for " .. fx_type .. " without value", function()
                assert.are.equal(C.EMPTY_FX_COLOR, ctrl:get_column_color(fx_type, false, nil))
            end)
        end

        for _, eff_type in ipairs({ "effect_number_xx", "effect_number_yy", "effect_amount_x", "effect_amount_y" }) do
            it("returns EFFECT_COLOR for " .. eff_type .. " with value", function()
                assert.are.equal(C.EFFECT_COLOR, ctrl:get_column_color(eff_type, true, nil))
            end)
            it("returns EMPTY_EFFECT_COLOR for " .. eff_type .. " without value", function()
                assert.are.equal(C.EMPTY_EFFECT_COLOR, ctrl:get_column_color(eff_type, false, nil))
            end)
        end

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
            local ctrl = build_ctrl({
                available_ccs = { 10, 11, 12 },
                visible_note_columns = 0,
                visible_effect_columns = 0,
            })
            ctrl:rebuild()
            assert.is_not_nil(ctrl.controls[10])
            assert.are.equal("cursor", ctrl.controls[10].type)
        end)

        it("assigns volume CCs for each visible note column", function()
            local ctrl = build_ctrl({
                available_ccs = { 10, 11, 12, 13, 14 },
                visible_note_columns = 2,
                visible_effect_columns = 0,
                volume_column_visible = true,
            })
            ctrl:rebuild()
            assert.are.equal("cursor", ctrl.controls[10].type)
            assert.are.equal("volume", ctrl.controls[11].type)
            assert.are.equal(1, ctrl.controls[11].note_column_index)
            assert.are.equal("volume", ctrl.controls[12].type)
            assert.are.equal(2, ctrl.controls[12].note_column_index)
        end)

        it("assigns multiple param types per note column", function()
            local ctrl = build_ctrl({
                available_ccs = { 10, 11, 12, 13 },
                visible_note_columns = 1,
                visible_effect_columns = 0,
                volume_column_visible = true,
                panning_column_visible = true,
            })
            ctrl:rebuild()
            assert.are.equal("volume", ctrl.controls[11].type)
            assert.are.equal("pan", ctrl.controls[12].type)
        end)

        it("assigns sample_effects columns (4 CCs per note column)", function()
            local ctrl = build_ctrl({
                available_ccs = { 0, 1, 2, 3, 4, 5 },
                visible_note_columns = 1,
                visible_effect_columns = 0,
                sample_effects_column_visible = true,
            })
            ctrl:rebuild()
            assert.are.equal("fx_number_xx", ctrl.controls[1].type)
            assert.are.equal("fx_number_yy", ctrl.controls[2].type)
            assert.are.equal("fx_amount_x", ctrl.controls[3].type)
            assert.are.equal("fx_amount_y", ctrl.controls[4].type)
        end)

        it("assigns effect column CCs", function()
            local ctrl = build_ctrl({
                available_ccs = { 0, 1, 2, 3, 4, 5 },
                visible_note_columns = 0,
                visible_effect_columns = 1,
            })
            ctrl:rebuild()
            assert.are.equal("effect_number_xx", ctrl.controls[1].type)
            assert.are.equal(1, ctrl.controls[1].effect_column_index)
        end)

        it("assigns automation CCs when adapter provides automations", function()
            local auto_param = { name = "Cutoff", is_automated = true,
                                 value_quantum = 0.01, value_max = 1.0, value_min = 0.0 }
            local adapter = make_adapter_stub({
                visible_note_columns = 0,
                visible_effect_columns = 0,
                automations = { auto_param },
            })
            local ctrl = build_ctrl({ adapter = adapter, available_ccs = { 0, 1, 2, 3, 4 } })
            ctrl:rebuild()
            assert.are.equal("automation_prev_scaling", ctrl.controls[1].type)
            assert.are.equal(auto_param, ctrl.controls[1].automation_parameter)
            assert.are.equal("automation", ctrl.controls[2].type)
            assert.are.equal("automation_scaling", ctrl.controls[3].type)
        end)

        it("produces empty controls when adapter:get_track() returns nil", function()
            local adapter = make_adapter_stub()
            -- Override get_track to return nil (simulates no phrase selected)
            function adapter:get_track()
                return nil
            end

            local ctrl = build_ctrl({ adapter = adapter, available_ccs = { 0, 1, 2 } })
            ctrl:rebuild()

            local count = 0
            for _ in pairs(ctrl.controls) do
                count = count + 1
            end
            assert.are.equal(0, count)
        end)

        it("stops assigning when CCs are exhausted", function()
            local ctrl = build_ctrl({
                available_ccs = { 0, 1, 2 },
                visible_note_columns = 1,
                visible_effect_columns = 0,
                volume_column_visible = true,
                panning_column_visible = true,
                delay_column_visible = true,
            })
            ctrl:rebuild()
            local count = 0
            for _ in pairs(ctrl.controls) do
                count = count + 1
            end
            assert.are.equal(3, count)
        end)

        it("resets disabled CCs from previous rebuild", function()
            local adapter = make_adapter_stub({
                visible_note_columns = 1,
                visible_effect_columns = 0,
                volume_column_visible = true,
            })
            local fb = make_feedback_spy()
            local ctrl = build_ctrl({ adapter = adapter, available_ccs = { 0, 1, 2, 3 }, feedback = fb })
            ctrl:rebuild()
            fb:reset()

            -- Now hide volume — CC 1 (was volume) should be reset
            adapter:get_track().volume_column_visible = false
            ctrl:rebuild()

            local found_midi_reset = false
            for _, call in ipairs(fb.calls.midi) do
                if call.cc == 1 and call.value == 0 then
                    found_midi_reset = true
                end
            end
            assert.is_true(found_midi_reset)
        end)

        it("initializes last_controls for every assigned CC", function()
            local ctrl = build_ctrl({
                available_ccs = { 5, 6, 7 },
                visible_note_columns = 1,
                volume_column_visible = true,
                number_of_steps = 4,
            })
            ctrl:rebuild()
            for cc, _ in pairs(ctrl.controls) do
                local lc = ctrl.last_controls[cc]
                assert.is_not_nil(lc)
                assert.are.equal(0, lc.command)
                assert.are.equal(4, lc.number_of_steps_to_change_value)
            end
        end)
    end)

    -- ============================================================
    -- search_backwards_for_value()
    -- ============================================================
    describe("search_backwards_for_value()", function()
        it("delegates to search_backwards with correct args", function()
            local captured = {}
            local ctrl = build_ctrl({
                search_backwards = function(is_eff, line_idx, col_idx, params)
                    captured = { is_eff = is_eff, line_idx = line_idx, col_idx = col_idx, params = params }
                    return 42
                end,
            })
            local result = ctrl:search_backwards_for_value("volume", 3, 10, true)
            assert.are.equal(42, result)
            assert.is_true(captured.is_eff)
            assert.are.equal(10, captured.line_idx)
            assert.are.equal(3, captured.col_idx)
        end)

        it("returns 0 for unknown column_type", function()
            local ctrl = build_ctrl()
            assert.are.equal(0, ctrl:search_backwards_for_value("nonexistent", 1, 1, false))
        end)
    end)

    -- ============================================================
    -- has_value_at_current_position()
    -- ============================================================
    describe("has_value_at_current_position()", function()
        it("returns true for cursor type always", function()
            local ctrl = build_ctrl()
            assert.is_true(ctrl:has_value_at_current_position("cursor", 1, false, nil))
        end)

        it("returns true for automation when parameter is present", function()
            local ctrl = build_ctrl()
            assert.is_true(ctrl:has_value_at_current_position("automation", 0, false, { is_automated = true }))
        end)

        it("returns false for automation when parameter is nil", function()
            local ctrl = build_ctrl()
            assert.is_false(ctrl:has_value_at_current_position("automation", 0, false, nil))
        end)

        it("returns true for automation_scaling when parameter is present", function()
            local ctrl = build_ctrl()
            assert.is_true(ctrl:has_value_at_current_position("automation_scaling", 0, false, {}))
        end)

        it("checks prev_point for automation_prev_scaling", function()
            local adapter = make_adapter_stub({
                get_automation_and_prev_point = function()
                    return {}, { time = 1 }
                end,
            })
            local ctrl = build_ctrl({ adapter = adapter })
            assert.is_true(ctrl:has_value_at_current_position("automation_prev_scaling", 0, false, { is_automated = true }))

            -- Now change to no prev_point
            function adapter:get_automation_and_prev_point()
                return {}, nil
            end
            assert.is_false(ctrl:has_value_at_current_position("automation_prev_scaling", 0, false, { is_automated = true }))
        end)

        it("returns false for automation_prev_scaling when parameter is nil", function()
            local ctrl = build_ctrl()
            assert.is_false(ctrl:has_value_at_current_position("automation_prev_scaling", 0, false, nil))
        end)

        it("returns false when selected_line is nil", function()
            local ctrl = build_ctrl({ no_selected_line = true })
            assert.is_false(ctrl:has_value_at_current_position("volume", 1, false, nil))
        end)

        it("returns true when param is not absent for note column", function()
            local ctrl, _, params = build_ctrl()
            params.volume._set_absent(false)
            assert.is_true(ctrl:has_value_at_current_position("volume", 1, false, nil))
        end)

        it("returns false when param is absent for note column", function()
            local ctrl, _, params = build_ctrl()
            params.volume._set_absent(true)
            assert.is_false(ctrl:has_value_at_current_position("volume", 1, false, nil))
        end)

        it("reads effect_columns when is_effect_column is true", function()
            local ctrl, _, params = build_ctrl()
            params.effect_number_xx._set_absent(false)
            assert.is_true(ctrl:has_value_at_current_position("effect_number_xx", 1, true, nil))
        end)

        it("returns false when column_index is out of range", function()
            local ctrl = build_ctrl()
            assert.is_false(ctrl:has_value_at_current_position("volume", 5, false, nil))
        end)

        it("returns false when column_index is 0", function()
            local ctrl = build_ctrl()
            assert.is_false(ctrl:has_value_at_current_position("volume", 0, false, nil))
        end)
    end)

    -- ============================================================
    -- get_current_column_value()
    -- ============================================================
    describe("get_current_column_value()", function()
        it("returns selected_line_index for cursor type", function()
            local ctrl = build_ctrl({ line_index = 17 })
            local val, col, q = ctrl:get_current_column_value("cursor", 0, false, nil)
            assert.are.equal(17, val)
            assert.is_nil(col)
            assert.are.equal(1, q)
        end)

        it("returns automation getter value and computed quantum", function()
            local ctrl, _, params = build_ctrl()
            params.automation._set_stored(64)
            local auto_param = { value_quantum = 0.01, value_max = 1.0, value_min = 0.0 }
            local val, col, q = ctrl:get_current_column_value("automation", 0, false, auto_param)
            assert.are.equal(64, val)
            assert.are.equal(auto_param, col)
            assert.are.equal(2, q)
        end)

        it("returns value_quantum of 1 when computed quantum is 0", function()
            local ctrl, _, params = build_ctrl()
            params.automation._set_stored(64)
            local auto_param = { value_quantum = 0.0, value_max = 1.0, value_min = 0.0 }
            local _, _, q = ctrl:get_current_column_value("automation", 0, false, auto_param)
            assert.are.equal(1, q)
        end)

        it("returns 0 when selected_line is nil", function()
            local ctrl = build_ctrl({ no_selected_line = true })
            local val, col = ctrl:get_current_column_value("volume", 1, false, nil)
            assert.are.equal(0, val)
            assert.is_nil(col)
        end)

        it("returns stored value for a note column param", function()
            local ctrl, _, params = build_ctrl()
            params.volume._set_stored(100)
            params.volume._set_absent(false)
            local val, _, q = ctrl:get_current_column_value("volume", 1, false, nil)
            assert.are.equal(100, val)
            assert.are.equal(1, q)
        end)

        it("calls search_backwards when value is absent", function()
            local searched = false
            local ctrl, _, params = build_ctrl({
                line_index = 5,
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
            local ctrl = build_ctrl()
            local val, col = ctrl:get_current_column_value("volume", 99, false, nil)
            assert.are.equal(0, val)
            assert.is_nil(col)
        end)

        it("returns 0 when column_params entry is missing", function()
            local ctrl = build_ctrl()
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
            local ctrl, _, _, adapter = build_ctrl()
            ctrl:set_selection("cursor", 1, false, nil)
            assert.are.equal(0, adapter.state.note_column_index)
        end)

        it("calls enter_automation_view for automation type", function()
            local ctrl, _, _, adapter = build_ctrl()
            local param = { name = "Volume" }
            ctrl:set_selection("automation", 0, false, param)
            assert.are.equal(param, adapter.state.automation_view_param)
        end)

        it("calls enter_automation_view for automation_scaling", function()
            local ctrl, _, _, adapter = build_ctrl()
            ctrl:set_selection("automation_scaling", 0, false, { name = "X" })
            assert.is_not_nil(adapter.state.automation_view_param)
        end)

        it("calls enter_automation_view for automation_prev_scaling", function()
            local ctrl, _, _, adapter = build_ctrl()
            ctrl:set_selection("automation_prev_scaling", 0, false, { name = "Y" })
            assert.is_not_nil(adapter.state.automation_view_param)
        end)

        it("does not set automation_view_param when param is nil", function()
            local ctrl, _, _, adapter = build_ctrl()
            ctrl:set_selection("automation", 0, false, nil)
            assert.is_nil(adapter.state.automation_view_param)
        end)

        it("sets note column index for non-effect column", function()
            local ctrl, _, _, adapter = build_ctrl()
            ctrl:set_selection("volume", 2, false, nil)
            assert.are.equal(2, adapter.state.note_column_index)
        end)

        it("sets effect column index and computes offset for effect column", function()
            local adapter = make_adapter_stub({ visible_note_columns = 3 })
            local ctrl = build_ctrl({ adapter = adapter })
            ctrl:set_selection("effect_number_xx", 1, true, nil)
            assert.are.equal(1, adapter.state.effect_column_index)
            -- select_column = visible_note_columns + effect_col = 3 + 1 = 4
            assert.are.equal(4, adapter.state.selection.column)
        end)

        it("does nothing when selected_line is nil", function()
            local ctrl, _, _, adapter = build_ctrl({ no_selected_line = true })
            ctrl:set_selection("volume", 1, false, nil)
            assert.are.equal(0, adapter.state.note_column_index)
        end)
    end)

    -- ============================================================
    -- map_to_midi_range()
    -- ============================================================
    describe("map_to_midi_range()", function()
        it("maps cursor value based on pattern/phrase length", function()
            local ctrl = build_ctrl({ number_of_lines = 64 })
            assert.are.equal(0, ctrl:map_to_midi_range("cursor", 1, nil, nil))
            assert.are.equal(127, ctrl:map_to_midi_range("cursor", 64, nil, nil))
            assert.are.equal(62, ctrl:map_to_midi_range("cursor", 32, nil, nil))
        end)

        it("returns 0 for cursor when only 1 line", function()
            local ctrl = build_ctrl({ number_of_lines = 1 })
            assert.are.equal(0, ctrl:map_to_midi_range("cursor", 1, nil, nil))
        end)

        it("passes through automation values unchanged", function()
            local ctrl = build_ctrl()
            assert.are.equal(99, ctrl:map_to_midi_range("automation", 99, nil, nil))
            assert.are.equal(42, ctrl:map_to_midi_range("automation_scaling", 42, nil, nil))
            assert.are.equal(5, ctrl:map_to_midi_range("automation_prev_scaling", 5, nil, nil))
        end)

        it("returns 0 for unknown column_type", function()
            local ctrl = build_ctrl()
            assert.are.equal(0, ctrl:map_to_midi_range("nonexistent", 50, nil, nil))
        end)

        it("maps regular column value to 0-127 range", function()
            local ctrl = build_ctrl()
            local col = {}
            assert.are.equal(64, ctrl:map_to_midi_range("volume", 64, nil, col))
            assert.are.equal(0, ctrl:map_to_midi_range("volume", 0, nil, col))
            assert.are.equal(127, ctrl:map_to_midi_range("volume", 128, nil, col))
        end)

        it("returns 0 when range is 0", function()
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
                    end,
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
            local fb = make_feedback_spy()
            local ctrl, _, params = build_ctrl({ feedback = fb, line_index = 1 })
            params.volume._set_stored(64)
            params.volume._set_absent(false)

            ctrl:update_controller_for_column("volume", 1, 10, false, nil)

            assert.is_true(#fb.calls.midi > 0)
            assert.are.equal(10, fb.calls.midi[1].cc)
            assert.is_true(#fb.calls.color > 0)
            assert.are.equal(10, fb.calls.color[1].cc)
        end)
    end)

    -- ============================================================
    -- update_all()
    -- ============================================================
    describe("update_all()", function()
        it("sends feedback for every control", function()
            local fb = make_feedback_spy()
            local ctrl, _, params = build_ctrl({
                feedback = fb,
                available_ccs = { 0, 1 },
                visible_note_columns = 1,
                volume_column_visible = true,
            })
            params.volume._set_absent(false)
            ctrl:rebuild()
            fb:reset()

            ctrl:update_all()
            assert.are.equal(2, #fb.calls.midi)
            assert.are.equal(2, #fb.calls.color)
        end)
    end)

    -- ============================================================
    -- modify_column_value()
    -- ============================================================
    describe("modify_column_value()", function()
        it("moves cursor line forward and sends feedback", function()
            local fb = make_feedback_spy()
            local ctrl, _, _, adapter = build_ctrl({ feedback = fb, line_index = 5, number_of_lines = 64 })

            ctrl:modify_column_value("cursor", 0, 10, 1, false, nil)
            assert.are.equal(6, adapter.state.line_index)
            assert.is_true(#fb.calls.midi > 0)
            assert.are.equal(make_color_config().CURSOR_COLOR, fb.calls.color[1].color)
        end)

        it("moves cursor line backward", function()
            local ctrl, _, _, adapter = build_ctrl({ line_index = 5, number_of_lines = 64 })
            ctrl:modify_column_value("cursor", 0, 10, -1, false, nil)
            assert.are.equal(4, adapter.state.line_index)
        end)

        it("clamps cursor at line 1", function()
            local ctrl, _, _, adapter = build_ctrl({ line_index = 1, number_of_lines = 64 })
            ctrl:modify_column_value("cursor", 0, 10, -1, false, nil)
            assert.are.equal(1, adapter.state.line_index)
        end)

        it("clamps cursor at last line", function()
            local ctrl, _, _, adapter = build_ctrl({ line_index = 64, number_of_lines = 64 })
            ctrl:modify_column_value("cursor", 0, 10, 1, false, nil)
            assert.are.equal(64, adapter.state.line_index)
        end)

        it("does nothing when edit_mode is off (non-cursor)", function()
            local fb = make_feedback_spy()
            local ctrl, _, params = build_ctrl({ feedback = fb, edit_mode = false })
            params.volume._set_stored(64)
            params.volume._set_absent(false)

            ctrl:modify_column_value("volume", 1, 10, 1, false, nil)
            assert.are.equal(0, #fb.calls.midi)
        end)

        it("increments value by quantum and sends feedback", function()
            local fb = make_feedback_spy()
            local ctrl, _, params = build_ctrl({ feedback = fb, edit_mode = true })
            params.volume._set_stored(64)
            params.volume._set_absent(false)
            local set_called_with = nil
            params.volume.setter = function(self, col, v, idx)
                set_called_with = v
            end

            ctrl:modify_column_value("volume", 1, 10, 1, false, nil)
            assert.are.equal(65, set_called_with)
        end)

        it("decrements value by quantum", function()
            local ctrl, _, params = build_ctrl({ edit_mode = true })
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
            local ctrl, _, params = build_ctrl({ edit_mode = true })
            params.volume._set_stored(128)
            params.volume._set_absent(false)
            local set_called_with = nil
            params.volume.setter = function(self, col, v, idx)
                set_called_with = v
            end

            ctrl:modify_column_value("volume", 1, 10, 1, false, nil)
            assert.are.equal(128, set_called_with)
        end)

        it("clamps decrement at min_value", function()
            local ctrl, _, params = build_ctrl({ edit_mode = true })
            params.volume._set_stored(0)
            params.volume._set_absent(false)
            local set_called_with = nil
            params.volume.setter = function(self, col, v, idx)
                set_called_with = v
            end

            ctrl:modify_column_value("volume", 1, 10, -1, false, nil)
            assert.are.equal(0, set_called_with)
        end)

        it("does nothing when column_params entry is missing", function()
            local fb = make_feedback_spy()
            local ctrl = build_ctrl({ feedback = fb, edit_mode = true })
            ctrl:modify_column_value("nonexistent", 1, 10, 1, false, nil)
            assert.are.equal(0, #fb.calls.midi)
        end)
    end)

    -- ============================================================
    -- is_ready_to_modify()
    -- ============================================================
    describe("is_ready_to_modify()", function()
        it("returns false when last_control does not exist for the CC", function()
            local ctrl = build_ctrl()
            assert.is_false(ctrl:is_ready_to_modify(176, 1, 99, 1))
        end)

        it("returns false when channel does not match control_channel", function()
            local ctrl = build_ctrl({
                available_ccs = { 0, 1 },
                visible_note_columns = 1,
                volume_column_visible = true,
                number_of_steps = 1,
            })
            ctrl:rebuild()
            assert.is_false(ctrl:is_ready_to_modify(176, 2, 1, 1))
        end)

        it("returns false when CC has no control mapping", function()
            local ctrl = build_ctrl({
                available_ccs = { 0 },
                visible_note_columns = 0,
                number_of_steps = 1,
            })
            ctrl:rebuild()
            assert.is_false(ctrl:is_ready_to_modify(176, 1, 5, 1))
        end)

        it("accumulates count and fires after reaching threshold", function()
            local ctrl = build_ctrl({
                available_ccs = { 0, 1 },
                visible_note_columns = 1,
                volume_column_visible = true,
                number_of_steps = 3,
            })
            ctrl:rebuild()

            assert.is_false(ctrl:is_ready_to_modify(176, 1, 1, 1))
            assert.is_false(ctrl:is_ready_to_modify(176, 1, 1, 1))
            assert.is_true(ctrl:is_ready_to_modify(176, 1, 1, 1))
        end)

        it("resets count after exceeding threshold", function()
            local ctrl = build_ctrl({
                available_ccs = { 0, 1 },
                visible_note_columns = 1,
                volume_column_visible = true,
                number_of_steps = 2,
            })
            ctrl:rebuild()

            ctrl:is_ready_to_modify(176, 1, 1, 1)
            assert.is_true(ctrl:is_ready_to_modify(176, 1, 1, 1))
            assert.is_false(ctrl:is_ready_to_modify(176, 1, 1, 1))
            assert.is_true(ctrl:is_ready_to_modify(176, 1, 1, 1))
        end)

        it("resets count when message differs", function()
            local ctrl = build_ctrl({
                available_ccs = { 0, 1 },
                visible_note_columns = 1,
                volume_column_visible = true,
                number_of_steps = 3,
            })
            ctrl:rebuild()

            ctrl:is_ready_to_modify(176, 1, 1, 1)
            ctrl:is_ready_to_modify(176, 1, 1, 1)
            -- Different command resets count
            assert.is_false(ctrl:is_ready_to_modify(192, 1, 1, 1))
            assert.is_false(ctrl:is_ready_to_modify(192, 1, 1, 1))
            assert.is_true(ctrl:is_ready_to_modify(192, 1, 1, 1))
        end)

        it("fires immediately when number_of_steps is 1", function()
            local ctrl = build_ctrl({
                available_ccs = { 0, 1 },
                visible_note_columns = 1,
                volume_column_visible = true,
                number_of_steps = 1,
            })
            ctrl:rebuild()
            assert.is_true(ctrl:is_ready_to_modify(176, 1, 1, 1))
        end)
    end)
end)