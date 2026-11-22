local heino = exports.heino_lib
local util = {}

function util.appearance(preferred)
    for _, resource in ipairs({ 'heino_appearance', 'illenium-appearance', 'fivem-appearance' }) do
        if (preferred == '' or preferred == resource) and GetResourceState(resource) == 'started' then
            local appearance = lib.loadJson('ped')
            if type(appearance) ~= 'table' or not next(appearance) then return end
            for _, field in ipairs({ 'components', 'props' }) do
                if type(appearance[field]) == 'table' and not next(appearance[field]) then appearance[field] = nil end
            end
            return appearance, resource
        end
    end
end

function util.format_price(amount)
    return (heino:GroupDigits(math.floor(amount)):gsub(',', locale('Common.ThousandsSeparator')))
end

return util
