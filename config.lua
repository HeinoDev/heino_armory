local cfg = {}

cfg.locale = 'da'

cfg.allowed_groups = {
    police = 0,
}

cfg.shop_type = 'heino_armory_equipment'
cfg.shop_name = 'Shop.Name'
cfg.ped_model = 's_m_y_cop_01'
cfg.integrations = {
    appearance = '',
    mdt = '',
}

cfg.target = {
    icon = 'fa-solid fa-shield-halved',
    label = 'Locker.Open',
    equipment_label = 'Shop.Open',
    distance = 2.0,
}

cfg.locations = {
    {
        label = 'Vinewood Police Department',
        scenario = 'WORLD_HUMAN_GUARD_STAND',
        coords = vec3(605.5, 3.47, 86.8),
        heading = 327.6,
    },
    {
        label = 'Vespucci Police Department',
        scenario = 'WORLD_HUMAN_GUARD_STAND',
        coords = vec3(-1034.06, -812.59, 9.95),
        heading = 168.79,
    },
}

cfg.preview = {
    camera_offset = vec3(-0.3, 1.15, 0.12),
    look_at_offset = vec3(-0.2, 0.0, 0.0),
    fov = 38.0,
    transition = 800,
    settle_time = 150,
    weapon_timeout = 2000,
    weapon_height = 0.55,
}

cfg.can_restock = 6
cfg.bypass_restrictions = 7

cfg.weapons = {
    WEAPON_COMBATPISTOL = {
        label = 'Weapons.CombatPistol',
        price = 5000,
        grade = 0,
        preview = {
            camera_offset = vec3(0.52, 0.7, 0.08),
            look_at_offset = vec3(-0.12, 0.0, 0.0),
            fov = 26.0,
        },
        components = {
            { item = 'at_flashlight', label = 'Attachments.Flashlight', default = true, hash = 'COMPONENT_AT_PI_FLSH' },
        },
    },
    WEAPON_PUMPSHOTGUN = {
        label = 'Weapons.PumpShotgun',
        price = 12000,
        grade = 3,
        components = {
            { item = 'at_flashlight', label = 'Attachments.Flashlight', default = true, hash = 'COMPONENT_AT_AR_FLSH' },
        },
    },
    WEAPON_CARBINERIFLE_MK2 = {
        label = 'Weapons.CarbineRifleMk2',
        price = 20000,
        grade = 3,
        components = {
            { item = 'at_flashlight', label = 'Attachments.Flashlight', default = true, hash = 'COMPONENT_AT_AR_FLSH' },
            { item = 'at_grip', label = 'Attachments.Grip', default = true, hash = 'COMPONENT_AT_AR_AFGRIP_02' },
            {
                item = 'at_scope_holo',
                label = 'Attachments.HolographicSight',
                default = false,
                price = 2500,
                hash = 'COMPONENT_AT_SIGHTS',
            },
            {
                item = 'at_suppressor_heavy',
                label = 'Attachments.Suppressor',
                default = false,
                price = 4000,
                hash = 'COMPONENT_AT_AR_SUPP',
            },
        },
    },
}

function cfg.select_components(data, selected)
    local items, extra = {}, 0
    local use_defaults = type(selected) ~= 'table'
    for _, component in ipairs(data.components or {}) do
        if
            (use_defaults and component.default) or (not use_defaults and lib.table.contains(selected, component.item))
        then
            items[#items + 1] = component.item
            if not component.default then extra = extra + (component.price or 0) end
        end
    end
    return items, extra
end

local policeWeapon = {
    registered = 'Københavns Politi',
    serial = 'POL',
}

cfg.equipment = {
    { name = 'handcuffs', price = 500, grade = 0 },
    { name = 'handcuffkey', price = 150, grade = 0 },
    { name = 'armour', price = 1500, grade = 0 },
    { name = 'radio', price = 1000, grade = 0 },
    { name = 'radiocell', price = 100, grade = 0 },
    { name = 'bandage', price = 75, grade = 0 },
    { name = 'firstaid', price = 350, grade = 0 },
    { name = 'binoculars', price = 500, grade = 0 },
    { name = 'WEAPON_PROLASER4', price = 1500, grade = 0 },

    { name = 'evidence_camera', price = 1500, grade = 0 },
    { name = 'fingerprint_scanner', price = 2500, grade = 0 },
    { name = 'dna_swab_kit', price = 150, grade = 0 },
    { name = 'evidence_pouch', price = 100, grade = 0 },
    { name = 'evidence_tweezers', price = 250, grade = 0 },
    { name = 'backit', price = 1000, grade = 0 },
    { name = 'evidence_objects', price = 750, grade = 1 },
    { name = 'accesstool', price = 2500, grade = 2 },

    { name = 'WEAPON_FLASHLIGHT', price = 500, grade = 0 },
    { name = 'WEAPON_NIGHTSTICK', price = 1000, grade = 0 },
    { name = 'WEAPON_STUNGUN', price = 2500, grade = 0, metadata = policeWeapon },
    { name = 'ammo-taser', price = 25, grade = 0 },
    { name = 'pistol_ammo', price = 50, grade = 0 },

    { name = 'spikestrip', price = 3000, grade = 1 },
    { name = 'policecone', price = 250, grade = 1 },
    { name = 'policebarricade', price = 750, grade = 1 },
    { name = 'policeroadsign', price = 500, grade = 1 },
    { name = 'policetent', price = 2000, grade = 1 },

    { name = 'heavyarmor', price = 4000, grade = 2 },
    { name = 'shotgun_ammo', price = 100, grade = 3 },
    { name = 'rifle_ammo', price = 150, grade = 3 },
}

return cfg
