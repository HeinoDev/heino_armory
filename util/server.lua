local heino = exports.heino_lib
local accounts = { 'bank', 'money' }
local util = {}

function util.charge(source, price, paid)
    if price == 0 then return true end

    local charged, account = heino:Charge(source, price, accounts)
    if charged then
        paid[account] = price
        return true
    end

    local player = heino:GetPlayer(source)
    if not player then return false, 'Errors.Payment' end
    local bank = math.max(0, (player.getAccount('bank') or {}).money or 0)
    local cash = math.max(0, (player.getAccount('money') or {}).money or 0)
    if bank + cash < price then return false, 'Errors.InsufficientFunds' end
    if bank >= price or cash >= price then return false, 'Errors.Payment' end

    local remainder = price - bank
    if not heino:RemoveMoney(source, 'bank', bank) then return false, 'Errors.Payment' end
    paid.bank = bank
    if not heino:RemoveMoney(source, 'money', remainder) then return false, 'Errors.Payment' end
    paid.money = remainder
    return true
end

function util.refund(source, identifier, paid)
    for account, amount in pairs(paid) do
        local ok, refunded = pcall(function()
            local player = heino:GetPlayer(source)
            return player
                and player.identifier == identifier
                and heino:AddMoney(source, account, amount, locale('Common.Refund'))
        end)
        if not ok or not refunded then lib.print.error(locale('Errors.Refund', identifier, amount, account)) end
    end
end

function util.register_weapon(resource, identifier, label, serial)
    if resource ~= 'ps-mdt' or GetResourceState(resource) ~= 'started' then return end
    local ok, err = pcall(function()
        exports[resource]:registerWeapon(identifier, locale(label), serial)
    end)
    if not ok then lib.print.error(err) end
end

return util
