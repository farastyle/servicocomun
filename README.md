# qb-communitysub

Sistema de serviço comunitário para servidores FiveM utilizando **QBCore**.

## Instalação
1. Copie a pasta `qb-communitysub` para a pasta de recursos do seu servidor.
2. Instale e configure as dependências:
   - [qb-core](https://github.com/qbcore-framework/qb-core)
   - [oxmysql](https://github.com/overextended/oxmysql)
   - Opcional: [qb-input](https://github.com/qbcore-framework/qb-input), [qb-clothing](https://github.com/qbcore-framework/qb-clothing), [qb-progressbar](https://github.com/qbcore-framework/qb-progressbar)
3. Importe o arquivo `qb-communitysub/sql/CommunityService.sql` no seu banco de dados.
4. Adicione ao seu `server.cfg`:
   ```cfg
   ensure qb-communitysub
   ```
5. Ajuste o arquivo `config.lua` conforme necessário (tipos de serviço, permissões, prisões, etc.).

## Uso
- Comando `/comum` (policiais/admins): abre menu para aplicar o serviço comunitário.
- Comando `/endcomum`: encerra o serviço antecipadamente (liberar ou prender).
- Comandos do condenado durante o serviço (dependem do tipo): `/cs_curar`, `/cs_consertar`, `/cs_varrer`.

O serviço é persistido no banco de dados para evitar perda em reinícios ou quedas de conexão.
