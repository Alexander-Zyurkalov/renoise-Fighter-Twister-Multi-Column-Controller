-- MIDI Monitor Tool for Renoise
-- Shows a window to select MIDI device and display last 3 events
-- Controls instrument number with MIDI Fighter Twister

-- Global variables
local dialog = nil
local midi_device = nil
local midi_events = {}
local MAX_EVENTS = 3

-- MIDI control settings
local CONTROL_CC = 12
local CONTROL_CHANNEL = 1
local INCREASE_VALUE = 65
local DECREASE_VALUE = 63

-- UI elements
local device_popup = nil
local event_text_1 = nil
local event_text_2 = nil
local event_text_3 = nil

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

        -- Calculate new instrument value
        local new_instrument = current_instrument
        if direction > 0 then
            new_instrument = math.min(255, current_instrument + 1)
        else
            new_instrument = math.max(0, current_instrument - 1)
        end

        -- Set new instrument value
        note_column.instrument_value = new_instrument
    end
end

-- MIDI event handler
local function midi_callback(message)
    -- Parse MIDI message
    local status = message[1]
    local data1 = message[2] or 0
    local data2 = message[3] or 0

    -- Determine message type
    local msg_type = "Unknown"
    local channel = (status % 16) + 1
    local command = status - (status % 16)

    -- Check for our control CC message and handle instrument modification
    if command == 176 and channel == CONTROL_CHANNEL and data1 == CONTROL_CC then
        if data2 == INCREASE_VALUE then
            modify_instrument(1)
        elseif data2 == DECREASE_VALUE then
            modify_instrument(-1)
        end
    end

    if command == 128 then
        msg_type = string.format("Note Off Ch%d: Note %d, Vel %d", channel, data1, data2)
    elseif command == 144 then
        if data2 == 0 then
            msg_type = string.format("Note Off Ch%d: Note %d, Vel %d", channel, data1, data2)
        else
            msg_type = string.format("Note On Ch%d: Note %d, Vel %d", channel, data1, data2)
        end
    elseif command == 176 then
        msg_type = string.format("CC Ch%d: CC %d, Val %d", channel, data1, data2)
    elseif command == 192 then
        msg_type = string.format("Program Change Ch%d: %d", channel, data1)
    elseif command == 224 then
        local pitch_value = data1 + (data2 * 128)
        msg_type = string.format("Pitch Bend Ch%d: %d", channel, pitch_value)
    else
        msg_type = string.format("Status: %d, Data1: %d, Data2: %d", status, data1, data2)
    end

    -- Add timestamp
    local timestamp = os.date("%H:%M:%S")
    local event_string = string.format("[%s] %s", timestamp, msg_type)

    -- Add to events list (keep only last 3)
    table.insert(midi_events, 1, event_string)
    if table.getn(midi_events) > MAX_EVENTS then
        table.remove(midi_events, MAX_EVENTS + 1)
    end

    -- Update UI if dialog is open
    if dialog and dialog.visible then
        event_text_1.text = midi_events[1] or ""
        event_text_2.text = midi_events[2] or ""
        event_text_3.text = midi_events[3] or ""
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
    -- Close existing device
    if midi_device then
        midi_device:close()
        midi_device = nil
    end

    -- Clear events
    midi_events = {}
    if dialog and dialog.visible then
        event_text_1.text = ""
        event_text_2.text = ""
        event_text_3.text = ""
    end

    -- Open new device
    local selected_index = device_popup.value
    if selected_index > 1 then
        local available_devices = renoise.Midi.available_input_devices()
        local device_name = available_devices[selected_index - 1]
        midi_device = renoise.Midi.create_input_device(device_name, midi_callback)
    end
end

-- Create the dialog
local function create_dialog()
    local vb = renoise.ViewBuilder()

    -- Get available devices
    local devices = get_midi_devices()

    -- Create UI elements
    device_popup = vb:popup {
        items = devices,
        value = 1,
        notifier = on_device_changed,
        width = 200
    }

    event_text_1 = vb:text {
        text = "",
        font = "mono",
        width = 400
    }

    event_text_2 = vb:text {
        text = "",
        font = "mono",
        width = 400
    }

    event_text_3 = vb:text {
        text = "",
        font = "mono",
        width = 400
    }

    -- Create the main content
    local content = vb:column {
        margin = 10,
        spacing = 5,

        vb:row {
            vb:text { text = "MIDI Device:" },
            device_popup
        },

        vb:space { height = 10 },

        vb:text { text = "Last 3 MIDI Events:", style = "strong" },
        vb:space { height = 5 },

        vb:column {
            spacing = 2,
            event_text_1,
            event_text_2,
            event_text_3
        },

        vb:space { height = 10 },

        vb:text { text = "Control: CC12 Ch1 controls instrument number", style = "italic" },

        vb:button {
            text = "Clear Events",
            notifier = function()
                midi_events = {}
                event_text_1.text = ""
                event_text_2.text = ""
                event_text_3.text = ""
            end
        }
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
                -- Close MIDI device when dialog closes
                if midi_device then
                    midi_device:close()
                    midi_device = nil
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
end)