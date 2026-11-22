local cfg = lib.load('config')
local util = lib.load('util.client')
local heino = exports.heino_lib

lib.locale(cfg.locale)

local armory_peds, preview = {}, {}
local opening = false
local open_menu, start_preview, stop_preview

local function notify(key, kind)
    heino:Notify({ description = locale(key), type = kind or 'error' })
end

local function show_menu(id, title, options, on_exit)
    lib.registerContext({ id = id, title = locale(title), options = options, onExit = on_exit, canClose = true })
    lib.showContext(id)
end

local function apply_preview_weapon(weapon, selected)
    local ped = preview.ped
    if not ped or not DoesEntityExist(ped) then return end

    local hash = joaat(weapon)
    local loaded, asset = pcall(lib.requestWeaponAsset, hash, 5000, 31, 31)
    if not loaded or not asset then return end
    if preview.ped ~= ped then
        RemoveWeaponAsset(hash)
        return
    end

    RemoveAllPedWeapons(ped, true)
    GiveWeaponToPed(ped, hash, 250, false, true)

    for _, component in ipairs(cfg.weapons[weapon].components or {}) do
        if lib.table.contains(selected, component.item) then
            GiveWeaponComponentToPed(ped, hash, joaat(component.hash or component.item))
        end
    end

    if not preview.posed then
        ClearPedTasksImmediately(ped)
        SetPedCanPlayAmbientAnims(ped, false)
        SetPedCanPlayGestureAnims(ped, false)
        SetBlockingOfNonTemporaryEvents(ped, true)
        preview.posed = true
    end

    SetCurrentPedWeapon(ped, hash, true)
    SetPedCurrentWeaponVisible(ped, true, true, true, true)

    preview.weapon_asset = hash
    return true
end

local function get_weapon_coords(ped)
    local weapon_obj = GetCurrentPedWeaponEntityIndex(ped)
    if weapon_obj and weapon_obj ~= 0 and DoesEntityExist(weapon_obj) then
        local coords = GetEntityCoords(weapon_obj)
        if coords.x ~= 0.0 or coords.y ~= 0.0 then return coords end
    end
end

local function start_preview_cam(ped, weapon)
    local settings = cfg.weapons[weapon].preview or {}
    local offset = settings.camera_offset or cfg.preview.camera_offset
    local look = settings.look_at_offset or cfg.preview.look_at_offset
    local fov = settings.fov or cfg.preview.fov
    local coords = get_weapon_coords(ped) or (GetEntityCoords(ped) + vec3(0, 0, cfg.preview.weapon_height))
    local forward = GetEntityForwardVector(ped)
    local right = vec3(forward.y, -forward.x, 0.0)
    forward = vec3(forward.x, forward.y, 0.0)
    local cam_coords = coords + right * offset.x + forward * offset.y + vec3(0, 0, offset.z)
    local look_coords = coords + right * look.x + forward * look.y + vec3(0, 0, look.z)
    local cam = CreateCamWithParams(
        'DEFAULT_SCRIPTED_CAMERA',
        cam_coords.x,
        cam_coords.y,
        cam_coords.z,
        0.0,
        0.0,
        0.0,
        fov,
        false,
        0
    )
    PointCamAtCoord(cam, look_coords.x, look_coords.y, look_coords.z)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, cfg.preview.transition, true, false)

    preview.cam = cam

    CreateThread(function()
        while preview.cam == cam do
            SetEntityLocallyInvisible(cache.ped)

            if not lib.getOpenContextMenu() and (IsControlJustReleased(0, 200) or IsControlJustReleased(0, 202)) then
                stop_preview()
                break
            end

            Wait(0)
        end
    end)
end

function stop_preview()
    if preview.cam then
        RenderScriptCams(false, true, cfg.preview.transition, true, false)
        DestroyCam(preview.cam, false)
        preview.cam = nil
    end

    if preview.ped and DoesEntityExist(preview.ped) then
        ClearPedTasksImmediately(preview.ped)
        RemoveAllPedWeapons(preview.ped, true)

        SetPedCanPlayAmbientAnims(preview.ped, true)
        SetPedCanPlayGestureAnims(preview.ped, true)

        local scenario = preview.scenario
        if scenario then TaskStartScenarioInPlace(preview.ped, scenario, 0, true) end
    end

    if preview.weapon_asset then
        RemoveWeaponAsset(preview.weapon_asset)
        preview.weapon_asset = nil
    end

    preview.ped = nil
    preview.weapon = nil
    preview.scenario = nil
    preview.posed = nil
end

local function open_preview_menu(weapon, stock, grade, selected)
    local wdata = cfg.weapons[weapon]
    local total, options = wdata.price, {}
    for _, component in ipairs(wdata.components or {}) do
        local active = lib.table.contains(selected, component.item)
        local extra = (not component.default) and (component.price or 0) or 0
        if active then total = total + extra end
        local status = locale(active and 'Attachments.Mounted' or 'Attachments.Unmounted')

        options[#options + 1] = {
            title = locale(component.label),
            icon = active and 'square-check' or 'square',
            description = extra > 0 and locale('Attachments.Price', status, util.format_price(extra)) or status,
            onSelect = function()
                local updated = {}
                for _, item in ipairs(selected) do
                    if item ~= component.item then updated[#updated + 1] = item end
                end
                if not active then updated[#updated + 1] = component.item end
                apply_preview_weapon(weapon, updated)
                open_preview_menu(weapon, stock, grade, updated)
            end,
        }
    end

    options[#options + 1] = {
        title = locale('Locker.TakeWeapon'),
        icon = 'hand',
        description = locale('Locker.Price', util.format_price(total)),
        onSelect = function()
            local ok, res, detail =
                pcall(lib.callback.await, 'heino_armory:cb:get_weapon', false, preview.location_id, weapon, selected)
            stop_preview()

            if not ok or not res then
                notify((ok and detail) or 'Errors.Purchase')
                return open_menu(stock, grade)
            end

            open_menu(res, detail)
        end,
    }

    options[#options + 1] = {
        title = locale('Common.Back'),
        icon = 'arrow-left',
        description = locale('Locker.ChooseAnotherWeapon'),
        onSelect = function()
            stop_preview()
            open_menu(stock, grade)
        end,
    }

    show_menu('heino_armory:preview_menu', wdata.label, options, stop_preview)
end

function start_preview(weapon, stock, grade)
    local ped = preview.target_ped
    if not ped or not DoesEntityExist(ped) then return end

    preview.ped = ped
    preview.weapon = weapon
    preview.scenario = preview.target_scenario

    ClearPedTasksImmediately(ped)
    ClearPedSecondaryTask(ped)

    local selected = cfg.select_components(cfg.weapons[weapon])
    if not apply_preview_weapon(weapon, selected) then
        stop_preview()
        notify('Errors.Preview')
        return open_menu(stock, grade)
    end

    pcall(function()
        heino:WaitFor(function()
            return preview.ped ~= ped or get_weapon_coords(ped)
        end, nil, cfg.preview.weapon_timeout)
    end)
    Wait(cfg.preview.settle_time)
    if preview.ped ~= ped or preview.weapon ~= weapon then return end
    start_preview_cam(ped, weapon)
    open_preview_menu(weapon, stock, grade, selected)
end

function open_menu(stock, grade)
    local options = {}
    for weapon, data in pairs(cfg.weapons) do
        local in_stock = lib.table.contains(stock, weapon)
        table.insert(options, {
            title = locale(data.label),
            image = string.format('nui://ox_inventory/web/images/%s.png', weapon),
            disabled = grade < data.grade or not in_stock,
            description = grade < data.grade and locale('Locker.NoAccess')
                or (not in_stock and locale('Locker.OutOfStock') or nil),
            onSelect = function()
                start_preview(weapon, stock, grade)
            end,
        })
    end

    show_menu('heino_armory:armory_menu', 'Locker.Title', options)
end

local function open_armory(ped, scenario, location_id)
    if opening or preview.ped then return end
    opening = true
    local ok, stock, grade = pcall(lib.callback.await, 'heino_armory:cb:get_armory_data', false, location_id)
    opening = false
    if not ok or not stock then return notify((ok and grade) or 'Errors.OpenLocker') end

    preview.target_ped = ped
    preview.target_scenario = scenario
    preview.location_id = location_id

    open_menu(stock, grade)
end

local function restock(data, weapon)
    local ok, result = pcall(lib.callback.await, 'heino_armory:cb:restock', false, data.target_identifier, weapon)
    if ok and result then return notify('Restock.Success', 'success') end
    notify('Errors.Restock')
end

local function open_restock_menu(data)
    local options = {
        {
            title = locale('Restock.All'),
            description = locale('Restock.AllDescription'),
            onSelect = function()
                restock(data)
            end,
        },
    }
    for weapon, wdata in pairs(cfg.weapons) do
        local in_stock = lib.table.contains(data.weapons, weapon)
        table.insert(options, {
            title = locale(wdata.label),
            disabled = data.grade < wdata.grade or in_stock,
            description = data.grade < wdata.grade and locale('Locker.NoAccess')
                or locale(in_stock and 'Restock.AlreadyInStock' or 'Restock.Action'),
            onSelect = function()
                restock(data, weapon)
            end,
        })
    end

    show_menu('heino_armory:restock_armory_menu', 'Restock.Title', options)
end

RegisterNetEvent('heino_armory:cl:open_restock_menu', open_restock_menu)

local function create_armory_ped(location, location_id, appearance, appearance_resource)
    local model = lib.requestModel(appearance and appearance.model or cfg.ped_model)
    if not model then return end

    local ped =
        CreatePed(0, model, location.coords.x, location.coords.y, location.coords.z, location.heading, false, true)
    SetModelAsNoLongerNeeded(model)
    if ped == 0 then return end

    if appearance then exports[appearance_resource]:setPedAppearance(ped, appearance) end

    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)

    if location.scenario then TaskStartScenarioInPlace(ped, location.scenario, 0, true) end

    armory_peds[#armory_peds + 1] = ped

    exports.ox_target:addLocalEntity(ped, {
        {
            name = ('heino_armory_weapons_%s'):format(location_id),
            icon = cfg.target.icon,
            label = locale(cfg.target.label),
            groups = cfg.allowed_groups,
            distance = cfg.target.distance,
            onSelect = function()
                open_armory(ped, location.scenario, location_id)
            end,
        },
        {
            name = ('heino_armory_equipment_%s'):format(location_id),
            icon = 'fa-solid fa-box-open',
            label = locale(cfg.target.equipment_label),
            groups = cfg.allowed_groups,
            distance = cfg.target.distance,
            onSelect = function()
                if preview.ped then return end
                heino:OpenInventory('shop', { type = cfg.shop_type, id = location_id })
            end,
        },
    })
end

CreateThread(function()
    local appearance, appearance_resource = util.appearance(cfg.integrations.appearance)

    for location_id, location in ipairs(cfg.locations) do
        create_armory_ped(location, location_id, appearance, appearance_resource)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    if preview.cam then
        RenderScriptCams(false, false, 0, true, false)
        DestroyCam(preview.cam, false)
        preview.cam = nil
    end

    if preview.weapon_asset then RemoveWeaponAsset(preview.weapon_asset) end

    for i = 1, #armory_peds do
        local ped = armory_peds[i]
        if DoesEntityExist(ped) then
            if GetResourceState('ox_target') == 'started' then exports.ox_target:removeLocalEntity(ped) end
            DeleteEntity(ped)
        end
    end
end)
