-- MIDI Controller module
-- Manages MIDI device connections, message sending, and callback dispatch
-- Uses __index metatable pattern for OOP

local MidiController = {}
MidiController.__index = MidiController

--- Create a new MidiController instance
-- @param config table with:
--   device_name       - MIDI device name string
--   control_channel   - channel for value feedback (1-based)
--   colour_channel    - channel for color feedback (1-based)
--   increase_value    - CC value that means "increase" (e.g. 65)
--   decrease_value    - CC value that means "decrease" (e.g. 63)
--   number_of_steps   - default steps before value change triggers
function MidiController.new(config)
    local self = setmetatable({}, MidiController)

    -- Configuration
    self.device_name = config.device_name
    self.control_channel = config.control_channel
    self.colour_channel = config.colour_channel
    self.increase_value = config.increase_value
    self.decrease_value = config.decrease_value
    self.number_of_steps = config.number_of_steps

    -- Device state
    self.input_device = nil
    self.output_device = nil

    -- Will be set via set_column_controls after construction
    self.column_ctrl = nil

    return self
end

--- Set the ColumnControls instance used for dispatching MIDI messages
function MidiController:set_column_controls(column_ctrl)
    self.column_ctrl = column_ctrl
end

--- Check if the output device is open
function MidiController:is_open()
    return self.output_device ~= nil
end

--- Send MIDI value feedback for a specific CC
function MidiController:send_feedback(cc, value)
    if self.output_device then
        local status_byte = 176 + (self.control_channel - 1)
        local clamped_value = math.min(127, value)
        local message = { status_byte, cc, clamped_value }
        self.output_device:send(message)
    end
end

--- Send MIDI color feedback for a specific CC
function MidiController:send_color(cc, color_value)
    if self.output_device then
        local status_byte = 176 + (self.colour_channel - 1)
        local clamped_value = math.min(127, color_value)
        local message = { status_byte, cc, clamped_value }
        self.output_device:send(message)
    end
end

--- MIDI message callback — parses incoming CC and dispatches to column_ctrl
function MidiController:on_midi_message(message)
    local column_ctrl = self.column_ctrl
    if not column_ctrl then
        return
    end

    local status = message[1]
    local control_cc = message[2] or 0
    local value_cc = message[3] or 0

    local channel = (status % 16) + 1
    local command = status - (status % 16)

    if command == 176 and value_cc == 127 or value_cc == 0 then
        if value_cc == 127 then
            -- Button press: set steps to 1 for fast response
            if column_ctrl.last_controls[control_cc] then
                column_ctrl.last_controls[control_cc].number_of_steps_to_change_value = 1
            end
        elseif value_cc == 0 then
            -- Button release: set selection and reset steps
            local control_info = column_ctrl.controls[control_cc]
            if control_info then
                local is_effect_column = (control_info.effect_column_index ~= nil)
                local column_index = control_info.note_column_index or control_info.effect_column_index or 0
                local automation_parameter = control_info.automation_parameter
                column_ctrl:set_selection(control_info.type, column_index, is_effect_column, automation_parameter)
                if column_ctrl.last_controls[control_cc] then
                    column_ctrl.last_controls[control_cc].number_of_steps_to_change_value = self.number_of_steps
                end
            end
        end
    elseif command == 176 and column_ctrl:is_ready_to_modify(command, channel, control_cc, self.control_channel) then
        -- Encoder rotation: modify the column value
        local control_info = column_ctrl.controls[control_cc]
        if control_info then
            local is_effect_column = (control_info.effect_column_index ~= nil)
            local column_index = control_info.note_column_index or control_info.effect_column_index or 0
            local automation_parameter = control_info.automation_parameter

            if value_cc == self.increase_value then
                column_ctrl:modify_column_value(control_info.type, column_index, control_cc, 1, is_effect_column, automation_parameter)
            elseif value_cc == self.decrease_value then
                column_ctrl:modify_column_value(control_info.type, column_index, control_cc, -1, is_effect_column, automation_parameter)
            end
        end
    end
end

--- Open MIDI input and output devices
-- Returns true if at least the output device was opened
function MidiController:open()
    self:close()

    local available_input_devices = renoise.Midi.available_input_devices()
    local available_output_devices = renoise.Midi.available_output_devices()

    -- Capture self for the closure
    local self_ref = self

    -- Open input device
    for i = 1, table.getn(available_input_devices) do
        if available_input_devices[i] == self.device_name then
            self.input_device = renoise.Midi.create_input_device(
                self.device_name,
                function(message) self_ref:on_midi_message(message) end
            )
            break
        end
    end

    -- Open output device
    for i = 1, table.getn(available_output_devices) do
        if available_output_devices[i] == self.device_name then
            self.output_device = renoise.Midi.create_output_device(self.device_name)
            break
        end
    end

    return self:is_open()
end

--- Close MIDI devices
function MidiController:close()
    if self.input_device then
        self.input_device:close()
        self.input_device = nil
    end
    if self.output_device then
        self.output_device:close()
        self.output_device = nil
    end
end

return MidiController
