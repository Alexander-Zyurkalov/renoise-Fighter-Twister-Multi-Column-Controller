-- MIDI Fighter Twister Multi-Column Controller for Renoise
-- Controls volume, pan, delay, FX number/amount columns, effect number/amount columns, and ALL AUTOMATIONS with feedback
-- Dynamically assigns CCs to control ALL visible note columns, effect columns, and all existing automations
-- Sends color feedback: Green if value exists, Blue if empty, Red for fx/effects, Purple for automation

-- Observer state
local observers_attached = false
local column_observers_attached = false
local automation_observers_attached = false
local position_timer = nil

-- Configuration constants
local NUMBER_OF_STEPS_TO_CHANGE_VALUE = 6

-- Color values for MIDI Fighter Twister
local COLOR_CONFIG = {
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

-- Available CC numbers pool (modify this list as needed)
local AVAILABLE_CCS = { 12, 13, 14, 15, 8, 9, 10, 11, 4, 5, 6, 7, 0, 1, 2, 3, 28, 29, 30, 31, 24, 25, 26, 27, 20, 21, 22, 23, 16, 17, 18, 19, 44, 45, 46, 47 }

local function search_backwards(song, is_effect_column, current_line_index, column_index, params)
    local track_index = song.selected_track_index
    local pattern_sequence = song.sequencer.pattern_sequence

    for seq_index = song.selected_sequence_index, 1, -1 do
        local pattern = song:pattern(pattern_sequence[seq_index])
        local track = pattern.tracks[track_index]
        local from_line = (seq_index == song.selected_sequence_index)
                and (current_line_index - 1)
                or pattern.number_of_lines

        if track then
            for line_index = from_line, 1, -1 do
                local line = track:line(line_index)
                if line then
                    local columns = is_effect_column and line.effect_columns or line.note_columns
                    if columns and column_index <= #columns then
                        local col = columns[column_index]
                        local prev_value = params:getter(col)
                        if not params:is_absent(col) then
                            return prev_value
                        end
                    end
                end
            end
        end
    end

    return params:default_value(nil)
end

-- Column parameter modules
local SimpleColumnParam = require("simple_column_param")
local NumberByteParam = require("number_byte_param")
local AmountNibbleParam = require("amount_nibble_param")
local AutomationValueParam = require("automation_value_param")
local AutomationScalingParam = require("automation_scaling_param")
local AutomationPrevScalingParam = require("automation_prev_scaling_param")

-- Column parameter configuration hash-map
local COLUMN_PARAMS = {
    note = SimpleColumnParam.new({ property = "note_value", max = 120, absent_sentinel = 121, default = 0 }),
    volume = SimpleColumnParam.new({ property = "volume_value", max = 0x80, absent_sentinel = 0xFF, default = 0 }),
    pan = SimpleColumnParam.new({ property = "panning_value", max = 0x80, absent_sentinel = 0xFF, default = 0x40 }),
    delay = SimpleColumnParam.new({ property = "delay_value", max = 0xFF, absent_sentinel = 0, default = 0 }),

    fx_number_xx = NumberByteParam.new({ value_property = "effect_number_value", is_high_byte = true }),
    fx_number_yy = NumberByteParam.new({ value_property = "effect_number_value", is_high_byte = false }),

    fx_amount_x = AmountNibbleParam.new({
        number_property = "effect_number_value",
        amount_property = "effect_amount_value",
        is_high_nibble = true,
    }),
    fx_amount_y = AmountNibbleParam.new({
        number_property = "effect_number_value",
        amount_property = "effect_amount_value",
        is_high_nibble = false,
    }),

    effect_number_xx = NumberByteParam.new({ value_property = "number_value", is_high_byte = true }),
    effect_number_yy = NumberByteParam.new({ value_property = "number_value", is_high_byte = false }),

    effect_amount_x = AmountNibbleParam.new({
        number_property = "number_value",
        amount_property = "amount_value",
        is_high_nibble = true,
    }),
    effect_amount_y = AmountNibbleParam.new({
        number_property = "number_value",
        amount_property = "amount_value",
        is_high_nibble = false,
    }),

    automation = AutomationValueParam.new(),
    automation_scaling = AutomationScalingParam.new(),
    automation_prev_scaling = AutomationPrevScalingParam.new(),
}

-- Create MIDI controller
local MidiController = require("midi_controller")
local midi_ctrl = MidiController.new({
    device_name = "Midi Fighter Twister",
    control_channel = 1,
    colour_channel = 2,
    increase_value = 65,
    decrease_value = 63,
    number_of_steps = NUMBER_OF_STEPS_TO_CHANGE_VALUE,
})

-- Create column controls, wired to MIDI controller for feedback
local ColumnControls = require("column_controls")
local column_ctrl = ColumnControls.new({
    available_ccs = AVAILABLE_CCS,
    number_of_steps = NUMBER_OF_STEPS_TO_CHANGE_VALUE,
    column_params = COLUMN_PARAMS,
    color_config = COLOR_CONFIG,
    send_midi_feedback = function(cc, value) midi_ctrl:send_feedback(cc, value) end,
    send_color_feedback = function(cc, color) midi_ctrl:send_color(cc, color) end,
    search_backwards = search_backwards,
})

-- Connect MIDI controller to column controls (bidirectional wiring)
midi_ctrl:set_column_controls(column_ctrl)

-- Wrapper functions for use as notifier callbacks (notifiers cannot receive 'self')
local function rebuild_column_controls()
    column_ctrl:rebuild()
end

local function update_all_controllers()
    column_ctrl:update_all()
end

-- Function to start position monitoring
local function start_position_timer()
    if renoise.tool():has_timer(update_all_controllers) then
        return
    end

    -- Check position every 1000ms
    position_timer = renoise.tool():add_timer(update_all_controllers, 1000)
end

-- Function to stop position monitoring
local function stop_position_timer()
    if renoise.tool():has_timer(update_all_controllers) then
        renoise.tool():remove_timer(update_all_controllers)
        position_timer = nil
    end
end

-- Function to attach automation observers
local function attach_automation_observers()
    if automation_observers_attached then
        return
    end

    local song = renoise.song()
    local pattern_track = song.selected_pattern_track

    if pattern_track and pattern_track.automation_observable then
        if pattern_track.automation_observable:has_notifier(rebuild_column_controls) == false then
            pattern_track.automation_observable:add_notifier(rebuild_column_controls)
        end
    end

    automation_observers_attached = true
end

-- Function to detach automation observers
local function detach_automation_observers()
    if not automation_observers_attached then
        return
    end

    local song = renoise.song()
    local pattern_track = song.selected_pattern_track

    if pattern_track and pattern_track.automation_observable then
        if pattern_track.automation_observable:has_notifier(rebuild_column_controls) then
            pattern_track.automation_observable:remove_notifier(rebuild_column_controls)
        end
    end

    automation_observers_attached = false
end

-- Function to attach column visibility observers
local function attach_column_observers()
    if column_observers_attached then
        return
    end

    local song = renoise.song()
    local track = song.selected_track

    if track.volume_column_visible_observable:has_notifier(rebuild_column_controls) == false then
        track.volume_column_visible_observable:add_notifier(rebuild_column_controls)
    end

    if track.panning_column_visible_observable:has_notifier(rebuild_column_controls) == false then
        track.panning_column_visible_observable:add_notifier(rebuild_column_controls)
    end

    if track.delay_column_visible_observable:has_notifier(rebuild_column_controls) == false then
        track.delay_column_visible_observable:add_notifier(rebuild_column_controls)
    end

    if track.sample_effects_column_visible_observable:has_notifier(rebuild_column_controls) == false then
        track.sample_effects_column_visible_observable:add_notifier(rebuild_column_controls)
    end

    if track.visible_note_columns_observable:has_notifier(rebuild_column_controls) == false then
        track.visible_note_columns_observable:add_notifier(rebuild_column_controls)
    end

    if track.visible_effect_columns_observable:has_notifier(rebuild_column_controls) == false then
        track.visible_effect_columns_observable:add_notifier(rebuild_column_controls)
    end

    column_observers_attached = true
end

-- Function to detach column visibility observers
local function detach_column_observers()
    if not column_observers_attached then
        return
    end

    local song = renoise.song()
    local track = song.selected_track

    if track.volume_column_visible_observable:has_notifier(rebuild_column_controls) then
        track.volume_column_visible_observable:remove_notifier(rebuild_column_controls)
    end

    if track.panning_column_visible_observable:has_notifier(rebuild_column_controls) then
        track.panning_column_visible_observable:remove_notifier(rebuild_column_controls)
    end

    if track.delay_column_visible_observable:has_notifier(rebuild_column_controls) then
        track.delay_column_visible_observable:remove_notifier(rebuild_column_controls)
    end

    if track.sample_effects_column_visible_observable:has_notifier(rebuild_column_controls) then
        track.sample_effects_column_visible_observable:remove_notifier(rebuild_column_controls)
    end

    if track.visible_note_columns_observable:has_notifier(rebuild_column_controls) then
        track.visible_note_columns_observable:remove_notifier(rebuild_column_controls)
    end

    if track.visible_effect_columns_observable:has_notifier(rebuild_column_controls) then
        track.visible_effect_columns_observable:remove_notifier(rebuild_column_controls)
    end

    column_observers_attached = false
end

-- Function to handle track changes (need to reattach column observers)
local function on_track_changed()
    detach_column_observers()
    detach_automation_observers()
    rebuild_column_controls()
    attach_column_observers()
    attach_automation_observers()
    update_all_controllers()
end

-- Function to attach selection observers
local function attach_observers()
    if observers_attached then
        return
    end

    local song = renoise.song()

    if song.selected_track_index_observable:has_notifier(on_track_changed) == false then
        song.selected_track_index_observable:add_notifier(on_track_changed)
    end

    if song.selected_pattern_index_observable:has_notifier(update_all_controllers) == false then
        song.selected_pattern_index_observable:add_notifier(update_all_controllers)
    end

    start_position_timer()

    observers_attached = true
end

-- Function to detach selection observers
local function detach_observers()
    if not observers_attached then
        return
    end

    local song = renoise.song()

    if song.selected_track_index_observable:has_notifier(on_track_changed) then
        song.selected_track_index_observable:remove_notifier(on_track_changed)
    end

    if song.selected_pattern_index_observable:has_notifier(update_all_controllers) then
        song.selected_pattern_index_observable:remove_notifier(update_all_controllers)
    end

    detach_column_observers()
    detach_automation_observers()

    stop_position_timer()

    observers_attached = false
end

-- Function to initialize MIDI devices and observers
local function initialize()
    detach_observers()
    midi_ctrl:close()

    if midi_ctrl:open() then
        rebuild_column_controls()
        attach_observers()
        attach_column_observers()
        attach_automation_observers()
        update_all_controllers()
    end
end

-- Add menu entry to reconnect if needed
renoise.tool():add_menu_entry {
    name = "Main Menu:Tools:Reconnect MIDI Fighter Twister",
    invoke = initialize
}

-- Cleanup when tool is unloaded
renoise.tool().app_release_document_observable:add_notifier(function()
    detach_observers()
    midi_ctrl:close()
end)

renoise.tool().app_new_document_observable:add_notifier(function()
    initialize()
end)