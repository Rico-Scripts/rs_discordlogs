RSDiscordLogs = RSDiscordLogs or {}

local oxRegistered = false
local oxHooks = {}

local function text(value)
    if value == nil then
        return '-'
    end

    if type(value) == 'table' then
        return tostring(value.label or value.name or value.id or value.type or 'table')
    end

    return tostring(value)
end

local function inventoryName(value, inventoryType)
    if type(value) == 'table' then
        return tostring(value.label or value.name or value.id or inventoryType or 'inventory')
    end

    if value ~= nil then
        return tostring(value)
    end

    return tostring(inventoryType or 'inventory')
end

local function sendOx(payload)
    payload = type(payload) == 'table' and payload or {}
    payload.type = payload.type or 'info'
    RSDiscordLogs.Send('ox_inventory', payload)
end

local function registerPostHook(eventName, handler)
    -- Nieuwere ox_inventory-versies ondersteunen post-hook events. Daardoor
    -- loggen we pas nadat een actie echt is geslaagd.
    local ok, hookId = pcall(function()
        return exports.ox_inventory:registerHook(eventName, nil, { print = false })
    end)

    if ok and hookId then
        local eventOk = pcall(function()
            AddEventHandler(hookId, function(success, payload)
                if success == false then
                    return
                end

                handler(payload or {})
            end)
        end)

        if eventOk then
            oxHooks[#oxHooks + 1] = hookId
            return true
        end
    end

    -- Compatibiliteit met oudere ox_inventory-versies. De callback verandert
    -- niets aan de inventory en retourneert dus niets/geen false.
    local legacyOk, legacyHookId = pcall(function()
        return exports.ox_inventory:registerHook(eventName, function(payload)
            SetTimeout(0, function()
                handler(payload or {})
            end)
        end, { print = false })
    end)

    if legacyOk and legacyHookId then
        oxHooks[#oxHooks + 1] = legacyHookId
        return true
    end

    return false
end

local function registerOxInventory()
    local adapter = Config.Adapters and Config.Adapters.OxInventory
    if not adapter or adapter.Enabled == false or oxRegistered then
        return
    end

    if GetResourceState('ox_inventory') ~= 'started' then
        return
    end

    local registered = 0

    if adapter.Transfers ~= false then
        if registerPostHook('swapItems', function(payload)
            local action = tostring(payload.action or 'move')
            local fromInventory = inventoryName(payload.fromInventory, payload.fromType)
            local toInventory = inventoryName(payload.toInventory, payload.toType)

            -- Slotverplaatsingen binnen exact dezelfde inventory geven anders
            -- extreem veel ruis. Geven en transfers tussen inventories loggen wel.
            if action ~= 'give'
                and fromInventory == toInventory
                and tostring(payload.fromType or '') == tostring(payload.toType or '')
            then
                return
            end

            local slot = type(payload.fromSlot) == 'table' and payload.fromSlot or {}
            local itemName = slot.label or slot.name or 'Onbekend item'

            sendOx({
                type = action == 'give' and 'info' or 'warning',
                title = action == 'give' and 'Item gegeven' or 'Inventory transfer',
                source = tonumber(payload.source),
                fields = {
                    { name = 'Actie', value = action, inline = true },
                    { name = 'Item', value = text(itemName), inline = true },
                    { name = 'Aantal', value = text(payload.count or slot.count or 1), inline = true },
                    { name = 'Van', value = fromInventory, inline = false },
                    { name = 'Naar', value = toInventory, inline = false }
                }
            })
        end) then
            registered = registered + 1
        end
    end

    if adapter.Purchases ~= false then
        if registerPostHook('buyItem', function(payload)
            sendOx({
                type = 'money',
                title = 'Item gekocht',
                source = tonumber(payload.source),
                fields = {
                    { name = 'Shop', value = text(payload.shopType), inline = true },
                    { name = 'Item', value = text(payload.itemName), inline = true },
                    { name = 'Aantal', value = text(payload.count or 1), inline = true },
                    { name = 'Totaal', value = text(payload.totalPrice or payload.price or 0), inline = true },
                    { name = 'Valuta', value = text(payload.currency or 'money'), inline = true }
                }
            })
        end) then
            registered = registered + 1
        end
    end

    if adapter.Crafting ~= false then
        if registerPostHook('craftItem', function(payload)
            local recipe = type(payload.recipe) == 'table' and payload.recipe or {}

            sendOx({
                type = 'info',
                title = 'Item gecraft',
                source = tonumber(payload.source),
                fields = {
                    { name = 'Item', value = text(recipe.name), inline = true },
                    { name = 'Aantal', value = text(recipe.count or 1), inline = true },
                    { name = 'Werkbank', value = text(payload.benchId), inline = true }
                }
            })
        end) then
            registered = registered + 1
        end
    end

    if adapter.ItemUse == true then
        if registerPostHook('usingItem', function(payload)
            local item = type(payload.item) == 'table' and payload.item or {}

            sendOx({
                type = 'info',
                title = 'Item gebruikt',
                source = tonumber(payload.source),
                fields = {
                    { name = 'Item', value = text(item.label or item.name), inline = true },
                    { name = 'Consume', value = text(payload.consume), inline = true }
                }
            })
        end) then
            registered = registered + 1
        end
    end

    if adapter.OpenInventory == true then
        if registerPostHook('openInventory', function(payload)
            sendOx({
                type = 'info',
                title = 'Inventory geopend',
                source = tonumber(payload.source),
                fields = {
                    { name = 'Type', value = text(payload.inventoryType), inline = true },
                    { name = 'Inventory', value = text(payload.inventoryId), inline = true }
                }
            })
        end) then
            registered = registered + 1
        end
    end

    oxRegistered = registered > 0

    if oxRegistered then
        RSDiscordLogs.Info(('ox_inventory adapter actief (%s hook(s)).'):format(registered))
    else
        RSDiscordLogs.Warn('ox_inventory gevonden, maar hooks konden niet worden geregistreerd.')
    end
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= 'ox_inventory' then
        return
    end

    oxRegistered = false
    SetTimeout(1000, registerOxInventory)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == 'ox_inventory' then
        oxRegistered = false
        oxHooks = {}
    end
end)

CreateThread(function()
    Wait(1500)
    registerOxInventory()
end)
