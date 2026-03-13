-- NumberByteParam: high or low byte of a 16-bit column property.
-- Covers: fx_number_xx, fx_number_yy, effect_number_xx, effect_number_yy.
--
-- Config:
--   value_property  (string)   the 16-bit property, e.g. "effect_number_value" or "number_value"
--   is_high_byte    (boolean)  true = xx (bits 15-8), false = yy (bits 7-0)

local NumberByteParam = {}

function NumberByteParam.new(config)
    local prop    = config.value_property
    local is_high = config.is_high_byte

    local getter, setter, is_absent

    if is_high then
        getter = function(col)
            return math.floor(col[prop] / 256)
        end

        setter = function(col, value, _)
            local low = col[prop] % 256
            col[prop] = value * 256 + low
        end

        is_absent = function(col)
            return math.floor(col[prop] / 256) == 0
        end
    else
        getter = function(col)
            return col[prop] % 256
        end

        setter = function(col, value, _)
            local high = math.floor(col[prop] / 256)
            col[prop] = high * 256 + value
        end

        is_absent = function(col)
            return col[prop] % 256 == 0
        end
    end

    return {
        getter        = getter,
        setter        = setter,
        min_value     = function(_) return 0  end,
        max_value     = function(_) return 35 end,
        is_absent     = is_absent,
        default_value = function(_) return 0  end,
    }
end

return NumberByteParam
