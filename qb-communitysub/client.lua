local QBCore = exports['qb-core']:GetCoreObject()

local CurrentService, AwaitingService
local OriginalAppearance = {}
local ServiceThreads = {}

local function clearThreads()
    for _, thread in ipairs(ServiceThreads) do
        if thread and thread.kill then
            thread:kill()
        end
    end
    ServiceThreads = {}
end

local function notify(message, messageType, length)
    QBCore.Functions.Notify(message, messageType or 'primary', length or 5000)
end

local function vectorFromTable(tbl)
    if not tbl then return vec3(0.0, 0.0, 0.0) end
    return vec3(tbl.x or 0.0, tbl.y or 0.0, tbl.z or 0.0)
end

local function headingFromTable(tbl)
    if not tbl then return 0.0 end
    return tbl.w or tbl.h or 0.0
end

local function cloneComponents(ped)
    local cache = {}
    for _, comp in ipairs({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }) do
        cache[comp] = {
            drawable = GetPedDrawableVariation(ped, comp),
            texture = GetPedTextureVariation(ped, comp),
            palette = GetPedPaletteVariation(ped, comp)
        }
    end
    return cache
end

local function applyComponents(ped, components)
    if not components then return end
    for _, item in ipairs(components) do
        SetPedComponentVariation(ped, item.component, item.drawable or 0, item.texture or 0, item.palette or 0)
    end
end

local function applyUniform(uniform)
    local ped = PlayerPedId()
    OriginalAppearance.components = cloneComponents(ped)

    if uniform and uniform.model then
        local model = GetHashKey(uniform.model)
        if IsModelInCdimage(model) then
            RequestModel(model)
            while not HasModelLoaded(model) do
                Wait(0)
            end
            SetPlayerModel(PlayerId(), model)
            SetModelAsNoLongerNeeded(model)
            ped = PlayerPedId()
        end
    end

    if uniform and uniform.components then
        applyComponents(ped, uniform.components)
    end
end

local function removeUniform()
    local ped = PlayerPedId()
    if OriginalAppearance.components then
        for comp, data in pairs(OriginalAppearance.components) do
            SetPedComponentVariation(ped, comp, data.drawable, data.texture, data.palette or 0)
        end
    end
end

local function setServiceBlip(data)
    if CurrentService and CurrentService.blipHandle then
        RemoveBlip(CurrentService.blipHandle)
        CurrentService.blipHandle = nil
    end

    if not data.blip then return end

    local coords = vectorFromTable(data.teleportCoords)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, data.blip.sprite or 1)
    SetBlipColour(blip, data.blip.color or 1)
    SetBlipScale(blip, data.blip.scale or 0.8)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(data.blip.text or 'Serviço Comunitário')
    EndTextCommandSetBlipName(blip)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, data.blip.color or 1)

    CurrentService = CurrentService or {}
    CurrentService.blipHandle = blip
end

local function removeServiceBlip()
    if CurrentService and CurrentService.blipHandle then
        RemoveBlip(CurrentService.blipHandle)
        CurrentService.blipHandle = nil
    end
end

local function createThread(fn)
    local thread = {}
    thread.alive = true
    thread.kill = function()
        thread.alive = false
    end
    CreateThread(function()
        fn(thread)
    end)
    ServiceThreads[#ServiceThreads + 1] = thread
    return thread
end

local function startAreaWatcher(data)
    createThread(function(thread)
        local coords = vectorFromTable(data.teleportCoords)
        local radius = data.radius or 10.0
        while thread.alive and CurrentService do
            local ped = PlayerPedId()
            local pCoords = GetEntityCoords(ped)
            local dist = #(pCoords - coords)
            if dist > radius then
                if not data.allowLeaving then
                    notify('Você deixou a área do serviço!', 'error')
                    TriggerServerEvent('qb-communitysub:server:PlayerLeftArea')
                    thread.alive = false
                    break
                else
                    notify('Retorne imediatamente ao local do serviço.', 'error')
                end
            end
            Wait(2000)
        end
    end)
end

local function startCountdown(data)
    createThread(function(thread)
        local endTime = GetGameTimer() + (data.duration * 60000)
        CurrentService.endTime = endTime
        while thread.alive and CurrentService do
            local remaining = math.ceil((endTime - GetGameTimer()) / 1000)
            if remaining <= 0 then
                TriggerServerEvent('qb-communitysub:server:FinishService')
                thread.alive = false
                break
            end
            Wait((Config.NoticeInterval or 60) * 1000)
            if CurrentService then
                notify(('Tempo restante de serviço: %s segundos.'):format(remaining), 'primary', 4000)
            end
        end
    end)
end

local function startDistanceDisplay(data)
    createThread(function(thread)
        local coords = vectorFromTable(data.teleportCoords)
        while thread.alive and CurrentService do
            local ped = PlayerPedId()
            local dist = #(GetEntityCoords(ped) - coords)
            local text = ('Serviço: %s | Distância: %.1fm'):format(data.label or 'Comunitário', dist)
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName(text)
            EndTextCommandDisplayHelp(0, false, true, -1)
            Wait(0)
        end
    end)
end

local function performProgress(duration, scenario)
    local ped = PlayerPedId()
    if scenario then
        TaskStartScenarioInPlace(ped, scenario, 0, true)
    end
    Wait(duration)
    ClearPedTasks(ped)
end

local function isActionAllowed(action)
    if not CurrentService or not CurrentService.allowedActions then return false end
    for _, allowed in ipairs(CurrentService.allowedActions) do
        if allowed == action then
            return true
        end
    end
    return false
end

local function performHeal()
    if not isActionAllowed('curar') then
        notify('Ação indisponível para este serviço.', 'error')
        return
    end

    local closestPlayer, closestDistance = QBCore.Functions.GetClosestPlayer()
    if closestPlayer ~= -1 and closestDistance <= 3.0 then
        notify('Atendendo paciente...', 'primary')
        performProgress(5000, 'CODE_HUMAN_MEDIC_TEND_TO_DEAD')
        local targetPed = GetPlayerPed(closestPlayer)
        local newHealth = math.min(200, GetEntityHealth(targetPed) + 40)
        SetEntityHealth(targetPed, newHealth)
        notify('Paciente estabilizado com sucesso.', 'success')
    else
        notify('Nenhum paciente próximo para atendimento.', 'error')
    end
end

local function performRepair()
    if not isActionAllowed('consertar') then
        notify('Ação indisponível para este serviço.', 'error')
        return
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local vehicle = QBCore.Functions.GetClosestVehicle(coords)
    if vehicle and vehicle ~= 0 then
        if #(GetEntityCoords(vehicle) - coords) <= 5.0 then
            notify('Iniciando reparo do veículo...', 'primary')
            performProgress(7000, 'WORLD_HUMAN_WELDING')
            SetVehicleFixed(vehicle)
            SetVehicleDirtLevel(vehicle, 0.0)
            notify('Veículo reparado.', 'success')
        else
            notify('Aproxime-se mais do veículo.', 'error')
        end
    else
        notify('Nenhum veículo próximo para reparo.', 'error')
    end
end

local function performSweep()
    if not isActionAllowed('varrer') then
        notify('Ação indisponível para este serviço.', 'error')
        return
    end

    notify('Realizando limpeza da área...', 'primary')
    performProgress(6000, 'WORLD_HUMAN_MAID_CLEAN')
    notify('Área limpa!', 'success')
end

RegisterCommand('cs_curar', performHeal)
RegisterCommand('cs_consertar', performRepair)
RegisterCommand('cs_varrer', performSweep)

local function cleanupService()
    clearThreads()
    removeServiceBlip()
    if AwaitingService and AwaitingService.blip then
        RemoveBlip(AwaitingService.blip)
    end
    AwaitingService = nil
    if CurrentService then
        removeUniform()
    end
    CurrentService = nil
end

local function startService(data)
    cleanupService()
    CurrentService = data

    if data.method == 'teleport' and data.teleportCoords then
        local coords = vectorFromTable(data.teleportCoords)
        SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z)
        SetEntityHeading(PlayerPedId(), headingFromTable(data.teleportCoords))
    end

    Wait(1000)
    applyUniform(data.uniform)
    setServiceBlip(data)
    notify('Cumprindo serviço comunitário. Permaneça na área e execute as ações atribuídas.', 'success')

    local instructions = {
        curar = 'Use /cs_curar próximo a um paciente para prestar primeiros socorros.',
        consertar = 'Use /cs_consertar próximo a um veículo para repará-lo.',
        varrer = 'Use /cs_varrer para limpar a área designada.'
    }

    if data.allowedActions then
        for _, action in ipairs(data.allowedActions) do
            if instructions[action] then
                notify(instructions[action], 'primary', 7000)
            end
        end
    end

    startAreaWatcher(data)
    startCountdown(data)
    startDistanceDisplay(data)
end

local function startAwaiting(data)
    cleanupService()
    AwaitingService = {
        data = data,
        deadline = GetGameTimer() + (data.arrivalTimeout or (Config.ArrivalTimeoutSeconds or 180)) * 1000
    }

    if data.teleportCoords then
        local coords = vectorFromTable(data.teleportCoords)
        SetNewWaypoint(coords.x, coords.y)
        notify(('Dirija-se até o local designado (%s). Você possui %s segundos.'):format(data.label or 'Serviço', data.arrivalTimeout), 'primary', 6000)
        removeServiceBlip()
        local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(blip, data.blip and data.blip.sprite or 1)
        SetBlipColour(blip, data.blip and data.blip.color or 1)
        SetBlipRoute(blip, true)
        SetBlipRouteColour(blip, data.blip and data.blip.color or 1)
        AwaitingService.blip = blip
    end

    createThread(function(thread)
        while thread.alive and AwaitingService do
            local now = GetGameTimer()
            if now > AwaitingService.deadline then
                notify('Você não chegou ao local a tempo.', 'error')
                if AwaitingService.blip then
                    RemoveBlip(AwaitingService.blip)
                end
                TriggerServerEvent('qb-communitysub:server:ArrivalTimeout')
                AwaitingService = nil
                break
            end

            local ped = PlayerPedId()
            local coords = vectorFromTable(data.teleportCoords)
            if #(GetEntityCoords(ped) - coords) <= (data.radius or 10.0) then
                if AwaitingService.blip then
                    RemoveBlip(AwaitingService.blip)
                end
                notify('Você chegou ao local do serviço. Aguarde instruções.', 'success')
                TriggerServerEvent('qb-communitysub:server:ArrivalSuccess')
                AwaitingService = nil
                break
            end
            Wait(1000)
        end
    end)
end

RegisterNetEvent('qb-communitysub:client:AwaitServiceLocation', function(data)
    startAwaiting(data)
end)

RegisterNetEvent('qb-communitysub:client:StartService', function(data)
    startService(data)
end)

RegisterNetEvent('qb-communitysub:client:FinishService', function(success, data)
    if success then
        notify(Config.Messages.ServiceCompleted or 'Serviço concluído.', 'success')
    end
    cleanupService()
end)

RegisterNetEvent('qb-communitysub:client:FailService', function(data)
    notify(Config.Messages.ServiceFailed or 'Você foi enviado para a prisão.', 'error')
    cleanupService()
    if data and data.prison and data.prison.coords then
        local coords = vectorFromTable(data.prison.coords)
        SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z)
        SetEntityHeading(PlayerPedId(), headingFromTable(data.prison.coords))
    end
end)

RegisterNetEvent('qb-communitysub:client:OfficerEnded', function()
    cleanupService()
end)

RegisterNetEvent('qb-communitysub:client:UpdateRemaining', function(remaining)
    if CurrentService then
        notify(('Tempo restante de serviço: %s segundos.'):format(math.max(0, remaining)), 'primary', 4000)
    end
end)

local function openApplyMenu()
    QBCore.Functions.TriggerCallback('qb-communitysub:server:CanOpenMenu', function(can)
        if not can then
            notify(Config.Messages.NoPermission or 'Sem permissão.', 'error')
            return
        end

        local success, result = pcall(function()
            local serviceOptions = {}
            for key, data in pairs(Config.ServiceTypes) do
                serviceOptions[#serviceOptions + 1] = { value = key, text = data.label }
            end

            local prisonOptions = {}
            for key, data in pairs(Config.PrisonLocations) do
                prisonOptions[#prisonOptions + 1] = { value = key, text = data.label }
            end

            return exports['qb-input']:ShowInput({
                header = 'Aplicar Serviço Comunitário',
                submitText = 'Aplicar',
                inputs = {
                    { type = 'number', name = 'target', text = 'ID do Jogador (server id)', isRequired = true },
                    { type = 'number', name = 'minutes', text = 'Tempo em minutos', isRequired = true },
                    { type = 'select', name = 'serviceType', text = 'Tipo de Serviço', options = serviceOptions, isRequired = true },
                    { type = 'select', name = 'method', text = 'Método (opcional)', options = {
                        { value = 'default', text = 'Padrão do serviço' },
                        { value = 'teleport', text = 'Teleportar' },
                        { value = 'go_to', text = 'Ir até o local' }
                    } },
                    { type = 'select', name = 'prison', text = 'Prisão para descumprimento', options = prisonOptions, isRequired = true }
                }
            })
        end)

        if success and result then
            if result.method == 'default' then
                result.method = nil
            end
            TriggerServerEvent('qb-communitysub:server:ApplyService', result)
        else
            notify('Utilize: /comum <id> <tempo> <servico> [metodo] [prisao]', 'error')
        end
    end)
end

local function openEndMenu()
    QBCore.Functions.TriggerCallback('qb-communitysub:server:CanOpenMenu', function(can)
        if not can then
            notify(Config.Messages.NoPermission or 'Sem permissão.', 'error')
            return
        end

        local success, result = pcall(function()
            return exports['qb-input']:ShowInput({
                header = 'Encerrar Serviço Comunitário',
                submitText = 'Encerrar',
                inputs = {
                    { type = 'number', name = 'target', text = 'ID do Jogador', isRequired = true },
                    { type = 'select', name = 'action', text = 'Ação', options = {
                        { value = 'liberar', text = 'Liberar (sem prisão)' },
                        { value = 'prender', text = 'Prender imediatamente' }
                    }, isRequired = true }
                }
            })
        end)

        if success and result then
            TriggerServerEvent('qb-communitysub:server:OfficerEndService', tonumber(result.target), result.action)
        else
            notify('Utilize: /endcomum <id> [prender/liberar]', 'error')
        end
    end)
end

RegisterCommand('comum', function(source, args)
    if args and #args >= 3 then
        TriggerServerEvent('qb-communitysub:server:ApplyService', {
            target = args[1],
            minutes = args[2],
            serviceType = args[3],
            method = args[4],
            prison = args[5]
        })
    else
        openApplyMenu()
    end
end)

RegisterCommand('endcomum', function(source, args)
    if args and args[1] and args[2] then
        TriggerServerEvent('qb-communitysub:server:OfficerEndService', tonumber(args[1]), args[2])
    else
        openEndMenu()
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    if CurrentService and CurrentService.uniform then
        Wait(Config.RespawnDelay or 5000)
        applyUniform(CurrentService.uniform)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        cleanupService()
    end
end)
