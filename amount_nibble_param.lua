-- AmountNibbleParam: high or low nibble of an effect amount value.
-- For xy-type effects the byte is split into two 4-bit nibbles.
-- For xx-type effects the high nibble controls the full byte and the low nibble is disabled (max 0).
-- Covers: fx_amount_x, fx_amount_y, effect_amount_x, effect_amount_y.
--
-- Config:
--   number_property     (string)    property holding the 16-bit command id, e.g. "effect_number_value" or "number_value"
--   amount_property     (string)    property holding the amount byte, e.g. "effect_amount_value" or "amount_value"
--   is_high_nibble      (boolean)   true = x (bits 7-4), false = y (bits 3-0)
--   get_effect_command   (function)  lookup function(number_value) -> command table or nil

local AmountNibbleParam = {}

function AmountNibbleParam.new(config)
    local num_prop  = config.number_property
    local amt_prop  = config.amount_property
    local is_high   = config.is_high_nibble
    local get_cmd   = config.get_effect_command

    local getter, setter, max_value

    if is_high then
        getter = function(col)
            local cmd = get_cmd(col[num_prop])
            if cmd and cmd.is_xy then
                return math.floor(col[amt_prop] / 16)
            else
                return col[amt_prop]
            end
        end

        setter = function(col, value, _)
            local cmd = get_cmd(col[num_prop])
            if cmd and cmd.is_xy then
                local low = col[amt_prop] % 16
                col[amt_prop] = value * 16 + low
            else
                col[amt_prop] = value
            end
        end

        max_value = function(col)
            if col then
                local cmd = get_cmd(col[num_prop])
                if cmd then
                    if cmd.is_xy then
                        return cmd.x_max
                    end
                    return cmd.max
                end
            end
            return 255
        end
    else
        getter = function(col)
            local cmd = get_cmd(col[num_prop])
            if cmd and cmd.is_xy then
                return col[amt_prop] % 16
            end
            return 0
        end

        setter = function(col, value, _)
            local cmd = get_cmd(col[num_prop])
            if cmd and cmd.is_xy then
                local high = math.floor(col[amt_prop] / 16)
                col[amt_prop] = high * 16 + value
            end
        end

        max_value = function(col)
            if col then
                local cmd = get_cmd(col[num_prop])
                if cmd and cmd.is_xy then
                    return cmd.y_max
                end
            end
            return 0
        end
    end

    -- Absent when the command itself is empty (number property == 0)
    local is_absent = function(col)
        return col[num_prop] == 0
    end

    return {
        getter        = getter,
        setter        = setter,
        min_value     = function(_) return 0 end,
        max_value     = max_value,
        is_absent     = is_absent,
        default_value = function(_) return 0 end,
    }
end

return AmountNibbleParam
