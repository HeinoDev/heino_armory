local cfg = lib.load('config')
local util = lib.load('util.server')
local heino = exports.heino_lib
local locked = {}
local sql_ready = false

lib.locale(cfg.locale)

local function get_character(identifier)
    for _, id in ipairs(GetPlayers()) do
        local player = heino:GetPlayer(tonumber(id))
        if player and player.identifier == identifier then return heino:GetPlayerData(player.source) end
    end

    local row = MySQL.single.await('SELECT job, job_grade FROM users WHERE identifier = ?', { identifier })
    return row and { job = { name = row.job, grade = tonumber(row.job_grade) } }
end

local function job_grade(player)
    local job = player and player.job
    local minimum = job and cfg.allowed_groups[job.name]
    if minimum and job.grade and job.grade >= minimum then return job.grade end
end

local function armory_grade(source, location_id, minimum, identifier)
    local location = type(location_id) == 'number' and cfg.locations[location_id]
    local ped = GetPlayerPed(source)
    if not location or ped == 0 or #(GetEntityCoords(ped) - location.coords) > cfg.target.distance + 1.0 then return end

    local player = heino:GetPlayerData(source)
    local grade = job_grade(player)
    if grade and grade >= minimum and (not identifier or player.identifier == identifier) then
        return grade, player.identifier
    end
end

MySQL.ready(function()
    local ok, err = xpcall(function()
        assert(
            MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS policearmory (
                identifier VARCHAR(60) NOT NULL,
                weapons JSON NOT NULL,
                PRIMARY KEY (identifier)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]]),
            locale('Errors.Schema')
        )

        local length = assert(
            tonumber(MySQL.scalar.await([[
            SELECT CHARACTER_MAXIMUM_LENGTH FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'policearmory' AND COLUMN_NAME = 'identifier'
        ]])),
            locale('Errors.Schema')
        )
        if length < 60 then
            assert(
                MySQL.query.await('ALTER TABLE policearmory MODIFY identifier VARCHAR(60) NOT NULL'),
                locale('Errors.Schema')
            )
        end
    end, debug.traceback)
    sql_ready = ok
    if not ok then lib.print.error(err) end
end)

local function with_stock(identifier, action)
    if not sql_ready then return false, 'Errors.DatabaseUnavailable' end
    if locked[identifier] then return false, 'Errors.StockBusy' end

    locked[identifier] = true
    local ok, result, detail = xpcall(action, debug.traceback)
    locked[identifier] = nil

    if ok then return result, detail end
    lib.print.error(result)
    return false, 'Errors.StockUpdate'
end

local function full_rearm(grade)
    local weapons = {}
    for weapon, data in pairs(cfg.weapons) do
        if grade >= data.grade then weapons[#weapons + 1] = weapon end
    end
    return weapons
end

local function load_stock(identifier, grade)
    local row = MySQL.single.await('SELECT weapons FROM policearmory WHERE identifier = ?', { identifier })
    if row then
        local stock = json.decode(row.weapons)
        assert(type(stock) == 'table', locale('Errors.StockInvalid', identifier))
        return stock
    end

    local stock = full_rearm(grade)
    local rows = MySQL.update.await('INSERT INTO policearmory (identifier, weapons) VALUES (?, ?)', {
        identifier,
        json.encode(stock),
    })
    assert(rows == 1, locale('Errors.StockInit', identifier))
    return stock
end

local function save_stock(identifier, stock)
    return MySQL.update.await('UPDATE policearmory SET weapons = ? WHERE identifier = ?', {
        json.encode(stock),
        identifier,
    })
end

lib.callback.register('heino_armory:cb:get_armory_data', function(source, location_id)
    local grade, identifier = armory_grade(source, location_id, 0)
    if not grade then return end

    return with_stock(identifier, function()
        return load_stock(identifier, grade), grade
    end)
end)

lib.callback.register('heino_armory:cb:get_weapon', function(source, location_id, weapon, components)
    local data = type(weapon) == 'string' and cfg.weapons[weapon]
    if not data then return end
    local grade, identifier = armory_grade(source, location_id, data.grade)
    if not grade then return end

    return with_stock(identifier, function()
        local stock = load_stock(identifier, grade)
        if not lib.table.contains(stock, weapon) then return false, 'Errors.OutOfStock' end

        local selected, extra_price = cfg.select_components(data, components)
        for _, item in ipairs(selected) do
            if not heino:ItemExists(item) then return false, 'Errors.AttachmentUnavailable' end
        end
        local price = data.price + extra_price
        local serial = ('%06dPOL%06d'):format(math.random(100000, 999999), math.random(100000, 999999))
        local metadata = { serial = serial, components = selected }
        local remaining = {}
        for _, item in ipairs(stock) do
            if item ~= weapon then remaining[#remaining + 1] = item end
        end

        assert(save_stock(identifier, remaining) == 1, locale('Errors.StockReserve', identifier))

        local paid = {}
        local ok, issued_grade, message = xpcall(function()
            if not armory_grade(source, location_id, data.grade, identifier) then return false end
            if not heino:CanCarryItem(source, weapon, 1, metadata) then return false, 'Errors.CannotCarry' end
            local charged, reason = util.charge(source, price, paid)
            if not charged then return false, reason end
            local current_grade = armory_grade(source, location_id, data.grade, identifier)
            return current_grade and heino:AddItem(source, weapon, 1, metadata) and current_grade
        end, debug.traceback)

        if not ok or not issued_grade then
            if not ok then lib.print.error(issued_grade) end
            util.refund(source, identifier, paid)
            assert(save_stock(identifier, stock) == 1, locale('Errors.StockRestore', identifier))
            return false, ok and message or 'Errors.Purchase'
        end

        util.register_weapon(cfg.integrations.mdt, identifier, data.label, serial)
        return remaining, issued_grade
    end)
end)

local function restock_permission(source, identifier)
    local player = heino:GetPlayerData(source)
    local grade = job_grade(player)
    return grade and grade >= cfg.can_restock and (player.identifier ~= identifier or grade >= cfg.bypass_restrictions)
end

local function restock_player(source, identifier, weapon)
    if type(identifier) ~= 'string' or identifier == '' or not restock_permission(source, identifier) then
        return false
    end
    local data = type(weapon) == 'string' and cfg.weapons[weapon]
    if weapon ~= nil and not data then return false end

    local success = with_stock(identifier, function()
        local grade = job_grade(get_character(identifier))
        if not grade or (data and grade < data.grade) then return false end

        local stock = load_stock(identifier, grade)
        if not restock_permission(source, identifier) then return false end
        if not weapon then return type(save_stock(identifier, full_rearm(grade))) == 'number' end
        if lib.table.contains(stock, weapon) then return true end
        stock[#stock + 1] = weapon
        return save_stock(identifier, stock) == 1
    end)
    return success == true
end

exports('RestockPlayer', restock_player)
lib.callback.register('heino_armory:cb:restock', restock_player)

RegisterCommand('restock', function(source, args)
    if not restock_permission(source) then return end

    local id = tonumber(args[1])
    local online = id and heino:GetPlayerData(id)
    local identifier = online and online.identifier or args[1]
    if not identifier then return heino:Notify(source, { type = 'error', description = locale('Restock.Usage') }) end
    if not restock_permission(source, identifier) then
        return heino:Notify(source, { type = 'error', description = locale('Errors.SelfRestock') })
    end

    local stock, grade = with_stock(identifier, function()
        local target_grade = job_grade(get_character(identifier))
        if not target_grade then return false, 'Errors.OfficerNotFound' end
        return load_stock(identifier, target_grade), target_grade
    end)
    if not stock then
        return heino:Notify(source, { type = 'error', description = locale(grade or 'Errors.OpenLocker') })
    end
    TriggerClientEvent('heino_armory:cl:open_restock_menu', source, {
        target_identifier = identifier,
        weapons = stock,
        grade = grade,
    })
end, false)

local function register_shop()
    if #cfg.locations == 0 then return end
    local locations, targets, equipment = {}, {}, {}
    for id, location in ipairs(cfg.locations) do
        locations[id] = location.coords
        targets[id] = { loc = location.coords, distance = cfg.target.distance + 1.0 }
    end
    for _, item in ipairs(cfg.equipment) do
        if heino:ItemExists(item.name) then
            equipment[#equipment + 1] = item
        else
            lib.print.warn(locale('Errors.EquipmentMissing', item.name))
        end
    end

    heino:RegisterShop(cfg.shop_type, {
        name = locale(cfg.shop_name),
        groups = cfg.allowed_groups,
        inventory = equipment,
        locations = locations,
        targets = targets,
    })
end

CreateThread(register_shop)
AddEventHandler('onServerResourceStart', function(resource)
    if resource == 'ox_inventory' then register_shop() end
end)
