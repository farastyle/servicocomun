Config = {}

-- Permissões padrão para aplicar serviço comunitário
Config.Permissions = {
    Jobs = { 'police' },
    Groups = { 'admin' }
}

-- Método padrão caso o tipo de serviço não defina um explicitamente
Config.DefaultMethod = 'teleport'

-- Tempo máximo para chegada quando o método for "go_to"
Config.ArrivalTimeoutSeconds = 180

-- Lista de prisões disponíveis para fallback quando o serviço falhar
Config.PrisonLocations = {
    boilingbroke = {
        label = 'Boiling Broke',
        coords = vec4(1776.07, 2560.84, 45.67, 270.0)
    },
    mrpd = {
        label = 'Cela MRPD',
        coords = vec4(1690.19, 2565.14, 45.56, 182.18)
    }
}

-- Tipos de serviço disponíveis para seleção
Config.ServiceTypes = {
    medico = {
        label = 'Apoio Médico',
        method = 'teleport',
        teleportCoords = vec4(-450.21, -340.50, 34.50, 87.69),
        radius = 18.0,
        uniform = {
            model = nil,
            components = {
                { component = 11, drawable = 13, texture = 3 }, -- Jaqueta
                { component = 3, drawable = 1, texture = 0 }, -- Mãos
                { component = 8, drawable = 11, texture = 0 }, -- Camisa
                { component = 4, drawable = 10, texture = 1 } -- Calça
            }
        },
        allowedActions = { 'curar' },
        blip = {
            sprite = 153,
            color = 2,
            scale = 0.8,
            text = 'Serviço Médico'
        },
        allowLeaving = false,
        arrivalTimeoutSeconds = 240
    },
    mecanico = {
        label = 'Apoio Mecânico',
        method = 'teleport',
        teleportCoords = vec4(-211.94, -1323.77, 30.89, 90.47),
        radius = 20.0,
        uniform = {
            model = nil,
            components = {
                { component = 11, drawable = 67, texture = 2 },
                { component = 3, drawable = 1, texture = 0 },
                { component = 4, drawable = 39, texture = 0 }
            }
        },
        allowedActions = { 'consertar' },
        blip = {
            sprite = 446,
            color = 47,
            scale = 0.8,
            text = 'Serviço Mecânico'
        },
        allowLeaving = false,
        arrivalTimeoutSeconds = 180
    },
    limpeza = {
        label = 'Limpeza Urbana',
        method = 'go_to',
        teleportCoords = vec4(-1107.22, -1621.81, 4.36, 126.0),
        radius = 25.0,
        uniform = {
            model = nil,
            components = {
                { component = 11, drawable = 200, texture = 0 },
                { component = 3, drawable = 0, texture = 0 },
                { component = 8, drawable = 59, texture = 0 },
                { component = 4, drawable = 36, texture = 0 }
            }
        },
        allowedActions = { 'varrer' },
        blip = {
            sprite = 318,
            color = 5,
            scale = 0.75,
            text = 'Limpeza Comunitária'
        },
        allowLeaving = true,
        arrivalTimeoutSeconds = 300
    }
}

-- Notificações padrões
Config.Messages = {
    NoPermission = 'Você não tem permissão para usar este comando.',
    InvalidTarget = 'Jogador alvo inválido ou offline.',
    AlreadyServing = 'O jogador já possui serviço comunitário ativo.',
    ServiceApplied = 'Serviço comunitário aplicado com sucesso.',
    ServiceReceived = 'Você recebeu uma sentença de serviço comunitário. Siga as instruções!',
    ServiceCompleted = 'Sentença de serviço comunitário concluída. Obrigado pela colaboração.',
    ServiceFailed = 'Você falhou em cumprir o serviço comunitário e foi enviado para a prisão.',
    OfficerCancelled = 'Serviço comunitário encerrado pelo oficial.'
}

-- Sugestão de tempo para notificações periódicas (em segundos)
Config.NoticeInterval = 60

-- Delay para reaplicar uniforme pós respawn (ms)
Config.RespawnDelay = 5000
