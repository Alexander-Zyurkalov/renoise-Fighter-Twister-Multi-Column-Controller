-- MIDI Monitor Tool for Renoise
-- Shows a window to select MIDI device and display last 3 events
-- Controls instrument number with MIDI Fighter Twister and sends feedback

-- Global variables
local dialog = nil
local midi_device = nil
local midi_output_device = nil

-- MIDI control settings
local CONTROL_CC = 12
local CONTROL_CHANNEL = 1
local INCREASE_VALUE = 65
local DECREASE_VALUE = 63

-- UI elements
local device_popup = nil

-- Function to send MIDI feedback
local function send_midi_feedback(value)
    if midi_output_device then
        local status_byte = 176 + (CONTROL_CHANNEL - 1)
        local clamped_value = math.min(127, value)
        local message = {status_byte, CONTROL_CC, clamped_value}
        midi_output_device:send(message)
    end
end

-- Function to modify instrument number
local function modify_instrument(direction)
    local song = renoise.song()
    local current_line = song.selected_line

    if not current_line then
        return
    end

    local note_columns = current_line.note_columns
    local selected_column = song.selected_note_column_index

    if selected_column > 0 and selected_column <= table.getn(note_columns) then
        local note_column = note_columns[selected_column]
        local current_instrument = note_column.instrument_value

        local new_instrument = current_instrument
        if direction > 0 then
            new_instrument = math.min(254, current_instrument + 1)
        else
            new_instrument = math.max(0, current_instrument - 1)
        end

        note_column.instrument_value = new_instrument
        send_midi_feedback(new_instrument)
    end
end

-- MIDI event handler
local function midi_callback(message)
    local status = message[1]
    local data1 = message[2] or 0
    local data2 = message[3] or 0

    local msg_type = "Unknown"
    local channel = (status % 16) + 1
    local command = status - (status % 16)

    if command == 176 and channel == CONTROL_CHANNEL and data1 == CONTROL_CC then
        if data2 == INCREASE_VALUE then
            modify_instrument(1)
        elseif data2 == DECREASE_VALUE then
            modify_instrument(-1)
        end
    end
end

-- Get available MIDI devices
local function get_midi_devices()
    local devices = {"None"}
    local available_devices = renoise.Midi.available_input_devices()
    for i = 1, table.getn(available_devices) do
        table.insert(devices, available_devices[i])
    end
    return devices
end

-- Device selection handler
local function on_device_changed()
    if midi_device then
        midi_device:close()
        midi_device = nil
    end
    if midi_output_device then
        midi_output_device:close()
        midi_output_device = nil
    end


    local selected_index = device_popup.value
    if selected_index > 1 then
        local available_devices = renoise.Midi.available_input_devices()
        local device_name = available_devices[selected_index - 1]
        midi_device = renoise.Midi.create_input_device(device_name, midi_callback)

        local available_output_devices = renoise.Midi.available_output_devices()
        for i = 1, table.getn(available_output_devices) do
            if available_output_devices[i] == device_name then
                midi_output_device = renoise.Midi.create_output_device(device_name)
                break
            end
        end
    end
end

-- Create the dialog
local function create_dialog()
    local vb = renoise.ViewBuilder()

    local devices = get_midi_devices()

    device_popup = vb:popup {
        items = devices,
        value = 1,
        notifier = on_device_changed,
        width = 200
    }

    local content = vb:column {
        margin = 10,
        spacing = 5,

        vb:row {
            vb:text { text = "MIDI Device:" },
            device_popup
        },

        vb:space { height = 10 },
    }

    return vb:column { content }
end

-- Show the dialog
local function show_dialog()
    if dialog and dialog.visible then
        dialog:show()
        return
    end

    dialog = renoise.app():show_custom_dialog(
            "MIDI Monitor",
            create_dialog(),
            function()
                if midi_device then
                    midi_device:close()
                    midi_device = nil
                end
                if midi_output_device then
                    midi_output_device:close()
                    midi_output_device = nil
                end
            end
    )
end

-- Add menu entry
renoise.tool():add_menu_entry {
    name = "Main Menu:Tools:MIDI Monitor...",
    invoke = show_dialog
}

-- Cleanup when tool is unloaded
renoise.tool().app_release_document_observable:add_notifier(function()
    if midi_device then
        midi_device:close()
        midi_device = nil
    end
    if midi_output_device then
        midi_output_device:close()
        midi_output_device = nil
    end
end)