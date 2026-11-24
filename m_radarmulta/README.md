# m_radarmulta

Radar de velocidade + app **Multas** no celular (sd-phone) para o servidor **Atitude RP** (Qbox).

## O que faz
- **Radares** criados e editados dentro do jogo pelo painel do admin (mri_Qadmin > Plugins > Radares, ou `/radares`): círculo ou área desenhada, limite de velocidade, sentido e isenções por emprego.
- Passou acima do limite: a multa vai para o **dono do veículo** (pela placa), com valor por faixa de excesso (Média, Grave, Gravíssima).
- As multas aparecem no app **Multas** do celular, com as abas Início, Histórico e Multas. O jogador paga pelo app com o saldo do **banco**, e o dinheiro vai para a conta da polícia no ps-banking.
- O export `Multar(citizenid, descricao, valor, extra)` deixa outros scripts (ex.: MDT) lançarem multas no app.

## Dependências
`ox_lib`, `oxmysql`, `qbx_core`, `qbx_vehicles`, `ps-banking`, `sd-phone`, `mri_Qadmin` (para o painel).

## Instalação
1. Coloque a pasta em `resources/[magrao]/m_radarmulta`.
2. Adicione `ensure m_radarmulta` no `server.cfg`, depois do sd-phone e do ps-banking.
3. As tabelas do banco são criadas sozinhas na primeira vez que o script liga.
4. Ajuste o `config.lua`: conta que recebe as multas, tolerância, faixas de valor e opções do app.
