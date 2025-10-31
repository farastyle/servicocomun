local QBCore = exports['qb-core']:GetCoreObject()

---@class ServiceState
---@field source number
---@field citizenid string
---@field officer number
---@field serviceType string
---@field duration number
---@field method string
---@field startedAt number
---@field endsAt number
---@field status string
---@field allowLeaving boolean
---@field arrivalDeadline number|nil
---@field arrivalTimeout number
---@field prison table
---@field blip table
---@field radius number
---@field teleportCoords table
---@field uniform table
---@field allowedActions table
---@field dbId number|nil
---@field monitorActive boolean

local ActiveServices = {}
local ActiveByCitizen = {}
local StoredSentences = {}

local function log(message)
    print(('^2[qb-communitysub]^7 %s'):format(message))
end

local function notifyPlayer(src, message, messageType, length)
    TriggerClientEvent('QBCore:Notify', src, message, messageType or 'primary', length or 5000)
end

local function hasPermission(src)
    if src == 0 then
        return true
    end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return false end

    local jobName = Player.PlayerData.job.name
    for _, job in ipairs(Config.Permissions.Jobs or {}) do
        if job == jobName then
            return true
        end
    end

    local group = Player.PlayerData.group
    for _, role in ipairs(Config.Permissions.Groups or {}) do
        if role == group then
            return true
        end
    end

    return false
end

local function getService(src)
    return ActiveServices[src]
end

local function setService(service)
    ActiveServices[service.source] = service
    if service.citizenid then
        ActiveByCitizen[service.citizenid] = service
    end
end

local function clearService(service)
    ActiveServices[service.source] = nil
    if service.citizenid then
        ActiveByCitizen[service.citizenid] = nil
    end
end

local function serializeVector(vec)
    if type(vec) == 'vector4' or type(vec) == 'vector3' then
        return { x = vec.x, y = vec.y, z = vec.z, w = vec.w }
    elseif type(vec) == 'table' then
        return vec
    end
    return nil
end

local function buildClientPayload(service, serviceTypeConfig)
    return {
        serviceType = service.serviceType,
        label = serviceTypeConfig.label,
        teleportCoords = serializeVector(serviceTypeConfig.teleportCoords),
        radius = serviceTypeConfig.radius,
        uniform = serviceTypeConfig.uniform,
        allowedActions = serviceTypeConfig.allowedActions,
        blip = serviceTypeConfig.blip,
        duration = service.duration,
        method = service.method,
        allowLeaving = serviceTypeConfig.allowLeaving,
        arrivalTimeout = service.arrivalTimeout,
        prison = {
            label = service.prison.label,
            coords = serializeVector(service.prison.coords)
        }
    }
end

local function persistService(service, isActive)
    if not service.citizenid then return end
    if service.dbId then
        MySQL.update('UPDATE community_service SET startedAt = ?, durationMin = ?, method = ?, serviceType = ?, active = ?, playerServerId = ? WHERE id = ?', {
            service.startedAt or 0,
            service.duration,
            service.method,
            service.serviceType,
            isActive and 1 or 0,
            service.source,
            service.dbId
        })
    else
        local insertId = MySQL.insert.await('INSERT INTO community_service (citizenid, playerServerId, serviceType, startedAt, durationMin, method, active) VALUES (?, ?, ?, ?, ?, ?, ?)', {
            service.citizenid,
            service.source,
            service.serviceType,
            service.startedAt or 0,
            service.duration,
            service.method,
            isActive and 1 or 0
        })
        service.dbId = insertId
    end
end

local function completeService(service, notify)
    if not service then return end

    local src = service.source
    clearService(service)
    persistService(service, false)

    if notify then
        notifyPlayer(src, Config.Messages.ServiceCompleted or 'Serviço comunitário concluído.', 'success')
    end

    TriggerClientEvent('qb-communitysub:client:FinishService', src, notify, service)
    log(('Sentença concluída para %s (%s).'):format(service.citizenid or 'N/A', src))
end

local function sendToPrison(service, reason)
    if not service then return end

    local src = service.source
    clearService(service)
    persistService(service, false)

    TriggerClientEvent('qb-communitysub:client:FailService', src, service, reason)
    notifyPlayer(src, Config.Messages.ServiceFailed or 'Você foi enviado para a prisão.', 'error')
    log(('Sentença falhou. Jogador %s (%s) enviado para prisão %s.'):format(service.citizenid or 'N/A', src, service.prison.label))
end

local function startMonitor(service)
    if not service or service.monitorActive then return end
    service.monitorActive = true

    CreateThread(function()
        while true do
            local currentService = ActiveServices[service.source]
            if not currentService or currentService.status ~= 'active' then
                break
            end

            local now = os.time()
            local remaining = (currentService.startedAt + (currentService.duration * 60)) - now
            if remaining <= 0 then
                completeService(currentService, true)
                break
            end

            TriggerClientEvent('qb-communitysub:client:UpdateRemaining', currentService.source, remaining)
            Wait((Config.NoticeInterval or 60) * 1000)
        end
        if service then
            service.monitorActive = false
        end
    end)
end

local function startArrivalMonitor(service)
    if not service then return end
    CreateThread(function()
        while true do
            local currentService = ActiveServices[service.source]
            if not currentService or currentService.status ~= 'awaiting' then
                break
            end

            if currentService.arrivalDeadline and os.time() > currentService.arrivalDeadline then
                sendToPrison(currentService, 'arrival_timeout')
                break
            end
            Wait(1000)
        end
    end)
end

local function beginService(officerSrc, targetSrc, minutes, serviceType, method, prisonKey)
    local officer = officerSrc ~= 0 and QBCore.Functions.GetPlayer(officerSrc) or nil
    local target = QBCore.Functions.GetPlayer(targetSrc)

    if officerSrc ~= 0 and not officer then
        return false, 'Oficial inválido.'
    end

    if not target then
        return false, Config.Messages.InvalidTarget
    end

    if ActiveServices[targetSrc] then
        return false, Config.Messages.AlreadyServing
    end

    local metadata = target.PlayerData.metadata or {}
    if metadata.injail and metadata.injail > 0 then
        return false, 'O jogador já está cumprindo pena na prisão.'
    end

    local serviceConfig = Config.ServiceTypes[serviceType]
    if not serviceConfig then
        return false, 'Tipo de serviço inválido.'
    end

    method = method or serviceConfig.method or Config.DefaultMethod
    if method ~= 'teleport' and method ~= 'go_to' then
        method = Config.DefaultMethod
    end

    local prison = Config.PrisonLocations[prisonKey] or Config.PrisonLocations.boilingbroke
    local arrivalTimeout = serviceConfig.arrivalTimeoutSeconds or Config.ArrivalTimeoutSeconds or 180

    local service = {
        source = targetSrc,
        citizenid = target.PlayerData.citizenid,
        officer = officerSrc,
        serviceType = serviceType,
        duration = minutes,
        method = method,
        startedAt = 0,
        endsAt = 0,
        status = method == 'go_to' and 'awaiting' or 'active',
        allowLeaving = serviceConfig.allowLeaving,
        arrivalDeadline = nil,
        arrivalTimeout = arrivalTimeout,
        prison = prison,
        radius = serviceConfig.radius,
        teleportCoords = serializeVector(serviceConfig.teleportCoords),
        uniform = serviceConfig.uniform,
        allowedActions = serviceConfig.allowedActions,
        blip = serviceConfig.blip
    }

    if service.status == 'awaiting' then
        service.arrivalDeadline = os.time() + arrivalTimeout
    else
        service.startedAt = os.time()
        service.endsAt = service.startedAt + (minutes * 60)
    end

    setService(service)
    persistService(service, true)

    local payload = buildClientPayload(service, serviceConfig)
    payload.officer = officerSrc

    if service.status == 'awaiting' then
        TriggerClientEvent('qb-communitysub:client:AwaitServiceLocation', targetSrc, payload)
        startArrivalMonitor(service)
    else
        TriggerClientEvent('qb-communitysub:client:StartService', targetSrc, payload)
        startMonitor(service)
    end

    if officerSrc ~= 0 then
        notifyPlayer(officerSrc, Config.Messages.ServiceApplied or 'Serviço aplicado.', 'success')
    end
    notifyPlayer(targetSrc, Config.Messages.ServiceReceived or 'Você recebeu serviço comunitário.', 'primary')
    local officerIdentifier = officer and officer.PlayerData.citizenid or 'console'
    log(('Oficial %s aplicou serviço %s para %s por %s minutos (método: %s, prisão: %s).'):format(officerIdentifier, serviceType, target.PlayerData.citizenid, minutes, method, prison.label))

    return true
end

local function handleArrivalSuccess(src)
    local service = getService(src)
    if not service or service.status ~= 'awaiting' then
        return
    end

    service.status = 'active'
    service.startedAt = os.time()
    service.endsAt = service.startedAt + (service.duration * 60)
    persistService(service, true)

    local payload = buildClientPayload(service, Config.ServiceTypes[service.serviceType])
    payload.officer = service.officer

    TriggerClientEvent('qb-communitysub:client:StartService', src, payload)
    startMonitor(service)
end

local function handleArrivalTimeout(src)
    local service = getService(src)
    if not service then return end
    sendToPrison(service, 'arrival_timeout')
end

local function handleLeftArea(src)
    local service = getService(src)
    if not service then return end
    sendToPrison(service, 'left_area')
end

local function handleOfficerEnd(officerSrc, targetSrc, action)
    if not hasPermission(officerSrc) then
        notifyPlayer(officerSrc, Config.Messages.NoPermission, 'error')
        return
    end

    local service = getService(targetSrc)
    if not service then
        notifyPlayer(officerSrc, 'O jogador não possui serviço ativo.', 'error')
        return
    end

    if action == 'prender' then
        sendToPrison(service, 'officer_cancelled')
    else
        completeService(service, false)
        TriggerClientEvent('qb-communitysub:client:OfficerEnded', targetSrc)
        notifyPlayer(targetSrc, Config.Messages.OfficerCancelled or 'Serviço encerrado.', 'error')
    end

    if officerSrc ~= 0 then
        notifyPlayer(officerSrc, 'Serviço encerrado.', 'success')
    end
end

--- Exports e callbacks
QBCore.Functions.CreateCallback('qb-communitysub:server:CanOpenMenu', function(source, cb)
    cb(hasPermission(source))
end)

QBCore.Functions.CreateCallback('qb-communitysub:server:ListServiceTypes', function(_, cb)
    local options = {}
    for key, data in pairs(Config.ServiceTypes) do
        options[#options + 1] = { value = key, text = data.label }
    end
    cb(options)
end)

QBCore.Functions.CreateCallback('qb-communitysub:server:ListPrisons', function(_, cb)
    local options = {}
    for key, data in pairs(Config.PrisonLocations) do
        options[#options + 1] = { value = key, text = data.label }
    end
    cb(options)
end)

RegisterNetEvent('qb-communitysub:server:ApplyService', function(data)
    local src = source
    if not hasPermission(src) then
        notifyPlayer(src, Config.Messages.NoPermission, 'error')
        return
    end

    if not data or not data.target or not data.minutes or not data.serviceType then
        notifyPlayer(src, 'Dados inválidos enviados.', 'error')
        return
    end

    local minutes = tonumber(data.minutes)
    if not minutes or minutes <= 0 then
        notifyPlayer(src, 'Tempo inválido.', 'error')
        return
    end

    local target = tonumber(data.target)
    if not target then
        notifyPlayer(src, Config.Messages.InvalidTarget, 'error')
        return
    end

    local method = data.method
    if method == 'default' or method == '' then
        method = nil
    end

    local ok, err = beginService(src, target, minutes, data.serviceType, method, data.prison)
    if not ok and err then
        notifyPlayer(src, err, 'error')
    end
end)

RegisterNetEvent('qb-communitysub:server:ArrivalSuccess', function()
    handleArrivalSuccess(source)
end)

RegisterNetEvent('qb-communitysub:server:ArrivalTimeout', function()
    handleArrivalTimeout(source)
end)

RegisterNetEvent('qb-communitysub:server:PlayerLeftArea', function()
    handleLeftArea(source)
end)

RegisterNetEvent('qb-communitysub:server:FinishService', function()
    local service = getService(source)
    if service then
        completeService(service, true)
    end
end)

RegisterNetEvent('qb-communitysub:server:OfficerEndService', function(targetSrc, action)
    handleOfficerEnd(source, targetSrc, action)
end)

-- Eventos expostos publicamente
RegisterNetEvent('qb-communitysub:server:StartService', function(targetSrc, minutes, serviceType, method, prison)
    local src = source
    if src ~= 0 and not hasPermission(src) then
        notifyPlayer(src, Config.Messages.NoPermission, 'error')
        return
    end
    local ok, err = beginService(src, targetSrc, minutes, serviceType, method, prison)
    if src ~= 0 and not ok and err then
        notifyPlayer(src, err, 'error')
    end
end)

RegisterNetEvent('qb-communitysub:server:EndService', function(targetSrc, action)
    local src = source
    if src ~= 0 and not hasPermission(src) then
        notifyPlayer(src, Config.Messages.NoPermission, 'error')
        return
    end
    handleOfficerEnd(src, targetSrc, action)
end)

exports('IsPlayerInService', function(sourceId)
    return ActiveServices[sourceId] ~= nil
end)

exports('GetPlayerService', function(sourceId)
    return ActiveServices[sourceId]
end)

local function restoreFromDatabase(player, row)
    local src = player.PlayerData.source
    local serviceConfig = Config.ServiceTypes[row.serviceType]
    if not serviceConfig then
        MySQL.update('UPDATE community_service SET active = 0 WHERE id = ?', { row.id })
        return
    end

    local now = os.time()
    local startedAt = row.startedAt or now
    local duration = row.durationMin or 0
    local endsAt = startedAt + (duration * 60)
    local remaining = endsAt - now

    if remaining <= 0 then
        MySQL.update('UPDATE community_service SET active = 0 WHERE id = ?', { row.id })
        return
    end

    local service = {
        source = src,
        citizenid = player.PlayerData.citizenid,
        officer = 0,
        serviceType = row.serviceType,
        duration = duration,
        method = row.method or serviceConfig.method or Config.DefaultMethod,
        startedAt = startedAt,
        endsAt = endsAt,
        status = 'active',
        allowLeaving = serviceConfig.allowLeaving,
        arrivalTimeout = serviceConfig.arrivalTimeoutSeconds or Config.ArrivalTimeoutSeconds,
        prison = Config.PrisonLocations.boilingbroke,
        radius = serviceConfig.radius,
        teleportCoords = serializeVector(serviceConfig.teleportCoords),
        uniform = serviceConfig.uniform,
        allowedActions = serviceConfig.allowedActions,
        blip = serviceConfig.blip,
        dbId = row.id
    }

    setService(service)
    persistService(service, true)

    local payload = buildClientPayload(service, serviceConfig)
    TriggerClientEvent('qb-communitysub:client:StartService', src, payload)
    startMonitor(service)
    notifyPlayer(src, 'Você retornou ao serviço comunitário pendente.', 'primary')
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local citizenid = player.PlayerData.citizenid
    if not citizenid then return end

    local row = StoredSentences[citizenid]
    if row then
        StoredSentences[citizenid] = nil
        restoreFromDatabase(player, row)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local service = getService(src)
    if service then
        clearService(service)
        service.monitorActive = false
        persistService(service, true)
        service.source = 0
        if service.citizenid and service.dbId then
            StoredSentences[service.citizenid] = {
                id = service.dbId,
                citizenid = service.citizenid,
                serviceType = service.serviceType,
                startedAt = service.startedAt,
                durationMin = service.duration,
                method = service.method
            }
        end
    end
end)

local function loadActiveSentences()
    local results = MySQL.query.await('SELECT * FROM community_service WHERE active = 1', {}) or {}
    for _, row in ipairs(results) do
        StoredSentences[row.citizenid] = row
    end
    if #results > 0 then
        log(('Carregadas %s sentenças ativas do banco de dados.'):format(#results))
    end
end

CreateThread(function()
    Wait(1000)
    loadActiveSentences()
end)
