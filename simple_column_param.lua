-- SimpleColumnParam: for columns backed by a single property on the column object.
-- Covers: note, volume, pan, delay.
--
-- Config:
--   property        (string)  column property name, e.g. "note_value"
--   max             (number)  maximum value
--   absent_sentinel (number)  the raw value that means "empty"
--   default         (number)  default value when nothing found  (optional, 0)

local SimpleColumnParam = {}

function SimpleColumnParam.new(config)
    local property        = config.property
    local min             = config.min or 0
    local max             = config.max
    local absent_sentinel = config.absent_sentinel
    local default         = config.default or 0

    return {
        getter = function(col)
            return col[property]
        end,

        setter = function(col, value, _)
            col[property] = value
        end,

        min_value = function(_)
            return min
        end,

        max_value = function(_)
            return max
        end,

        is_absent = function(col)
            return col[property] == absent_sentinel
        end,

        default_value = function(_)
            return default
        end,
    }
end

return SimpleColumnParam
