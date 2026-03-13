-- Phrase Adapter
-- Adapts renoise.song() phrase-editing API for use by ColumnControls
-- Uses __index metatable pattern for OOP

local PhraseAdapter = {}
PhraseAdapter.__index = PhraseAdapter

function PhraseAdapter.new()
    return setmetatable({}, PhraseAdapter)
end

--- Returns the selected phrase (has same visibility fields as a track)
function PhraseAdapter:get_track()
    return renoise.song().selected_phrase
end

function PhraseAdapter:get_selected_line()
    return renoise.song().selected_phrase_line
end

function PhraseAdapter:get_selected_line_index()
    return renoise.song().selected_phrase_line_index
end

function PhraseAdapter:set_selected_line_index(idx)
    renoise.song().selected_phrase_line_index = idx
end

function PhraseAdapter:get_number_of_lines()
    local phrase = renoise.song().selected_phrase
    if phrase then
        return phrase.number_of_lines
    end
    return 0
end

function PhraseAdapter:is_edit_mode()
    return renoise.song().transport.edit_mode
end

function PhraseAdapter:set_note_column_index(idx)
    renoise.song().selected_phrase_note_column_index = idx
end

function PhraseAdapter:set_effect_column_index(idx)
    renoise.song().selected_phrase_effect_column_index = idx
end

function PhraseAdapter:set_selection(line_index, column_index)
    renoise.song().selection_in_phrase = {
        start_line = line_index,
        end_line = line_index,
        start_column = column_index,
        end_column = column_index,
    }
end

function PhraseAdapter:supports_automation()
    return false
end

function PhraseAdapter:enter_automation_view(_param)
    -- no-op for phrases
end

function PhraseAdapter:get_all_automations()
    return {}
end

function PhraseAdapter:get_automation_and_prev_point(_param)
    return nil, nil
end

return PhraseAdapter
