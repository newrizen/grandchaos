<div align="center">

# **GrandChaos - Fase 1 (Floresta de Aria)**

  <a href="https://www.minetest.net/">
    <img src="https://img.shields.io/badge/Minetest-5.15+-blue?logo=minetest">
  </a>
  <img src="https://img.shields.io/badge/version-prealpha-red">

  GrandChaos, a Minetest Game (Luanti) mod based in GrandChase

  <img 
    src="https://github.com/newrizen/grandchaos/blob/main/images/screenshot_20260719_112754.png"
    alt="GrandChaos Screenshot"
    width="350">
</div>

<div>
  
>[!IMPORTANT]
>This game is experimental, so expect to encounter many bugs and incomplete features.
  
Mod para **Luanti / Minetest Game** que recria, à sua maneira, a primeira fase do jogo GrandChase: um corredor de combate em   **trilho** (o personagem só se move para frente e para trás, sem deslocamento lateral), dividido em trechos fechados por   **paredes de tronco permanentes e indestrutíveis**, com 3 trechos de inimigos e um chefe final. Os próprios inimigos também só andam para frente/para trás, como o jogador. O mod inclui ainda um modo visual 2D experimental (mt2d), usado durante toda a fase.
## **Instalação**  
1. Copie a pasta grandchaos inteira para a pasta de mods do seu jogo/mundo, por exemplo:
- ~/.minetest/mods/grandchaos (mod global), ou
- SEU_MUNDO/worldmods/grandchaos (só para um mundo específico).
1. No jogo, vá em **Configurar** →   **Mods** e ative grandchaos (ele depende apenas do mod default, que já vem no Minetest Game).
2. Entre no mundo.
## **Como jogar**  
Ao entrar no mundo, quem ainda não tiver uma fase em andamento vê uma dica fixa no topo da tela explicando os dois comandos de início:
- Digite no chat: /gcstart
  - Constrói o corredor da fase **sempre na mesma origem fixa, ** **x=0, y=500, z=0** (não depende de onde o jogador estava parado), ativa o   **modo 2D** (veja abaixo) caso ainda não esteja ativo, dá a   **espada inicial (Shinai)** ao jogador e libera o   **trecho 1**.
  - Alternativamente, use /gcportal para receber um bloco de Portal: coloque-o em qualquer lugar e clique com o botão direito para iniciar a fase a partir dali (a origem da arena continua sendo sempre a mesma, y=500).
- **Movimento em trilho:** enquanto a fase estiver ativa, o eixo Z do personagem fica travado (é o único eixo que o corredor não usa) — você só anda para frente/para trás no eixo X (W/S) e pula (barra de espaço). A câmera continua livre.
- A fase tem **5 trechos** ao todo: o 1º é só um corredor de caminhada (sem inimigos), os trechos 2, 3 e 4 têm ondas de inimigos, e o 5º é a arena do chefe. Cada trecho termina numa   **parede de tronco permanente** (grandchaos:trunk_wall) que nunca desaparece — a passagem para o próximo trecho não é por destruir ou remover a parede, e sim por um bloco luminoso no chão, logo antes dela: 
  1. O bloco começa **apagado** (vidro) enquanto houver inimigos vivos no trecho.
  2. Ele **acende** (default:meselamp) assim que todos os inimigos forem derrotados.
  3. Com o bloco aceso, basta **caminhar até ele e agachar (sneak)** para ser teleportado ao início do próximo trecho. O trecho 1 não tem inimigos, então o bloco já nasce aceso.
- **Voltar para trás:** o bloco luminoso de pouso (início) de um trecho já limpo também pode ser usado, do mesmo jeito (agachar sobre ele), para retornar ao bloco de fim do trecho anterior. No bloco de pouso do trecho 1, agachar sai da fase por completo (restaura o terreno e leva o jogador de volta ao spawn).
- **Plataformas atravessáveis:** ao ficar em pé sobre uma plataforma de tronco (grandchaos:trunk_platform) e apertar agachar/baixo, ela fica passável por um instante e você cai através dela; pulando por baixo de uma plataforma o efeito é o mesmo, permitindo subir através dela.
- Depois do 4º trecho, o **chefe** aparece em uma arena maior no final do corredor (no código ele é chamado ora de "Golem Guardião", ora de "Ent Guardião" — os dois nomes aparecem em mensagens diferentes). Ele tem bastante vida, ataca corpo a corpo, dá um golpe sísmico em área depois de pular e sentar, e dispara rajadas de frutos à distância.
- Ao derrotá-lo, ele solta moedas, a **espada de conclusão (Bokken)** e o   **Troféu da Floresta de Aria** como itens no chão (não são dados automaticamente ao inventário); uma mensagem de vitória aparece no chat e a trava de movimento é liberada.
- **Inimigos também em trilho:** cada inimigo fica travado no seu próprio eixo Z (não consegue se mover lateralmente) — só avança ou recua ao longo do corredor (eixo X) para chegar perto de você. O chefe anda numa trilha própria, ligeiramente deslocada da trilha do jogador/plataformas.

**Modo 2D (experimental)**
O mod inclui um modo de visão 2D (arquivos mt2d.lua e mt2d_entities.lua), usado automaticamente durante a Fase 1. Ele também pode ser ativado fora da fase:
- /join2d — entra manualmente no modo 2D.
- /leave2d — sai do modo 2D e volta ao 3D normal (exige o privilégio leave2d; não funciona com uma fase do grandchaos em andamento — use /gcreset antes).

Outros comandos:
- /gcreset — cancela a fase em andamento, remove os monstros restantes, libera o movimento e restaura o terreno original de onde a arena foi construída.
## **Estrutura do mod**  
- mod.conf — metadados do mod (depende de default).
- items.lua — espadas do herói (Shinai/Bokken), parede e plataformas de tronco (grandchaos:trunk_wall, grandchaos:trunk_platform e sua variante "fantasma" passável), blocos de piso, portal, moedas (cobre/prata/ouro/ platina) e o troféu.
- entities.lua — inimigos: Slime (corpo a corpo, com investida em salto) e Arqueiro (à distância, com flecha própria e "senta" após golpes rápidos seguidos), além do chefe final (muita vida, ataque em área e rajada de frutos); todos travados no próprio eixo Z.
- init.lua — construção da arena (origem fixa em x=0,y=500,z=0), sistema de ondas, checkpoints por bloco luminoso + agachar, progressão/retorno de trechos, plataformas atravessáveis, spawn do chefe, restauração do terreno, HUD de instruções, comandos de chat e a trava de movimento em trilho do jogador.
- mt2d.lua / mt2d_entities.lua — implementação do modo de visão 2D usado pela fase (câmera, entidade visual do jogador, animações, comandos /join2d//leave2d).
- models/ — meshes (.glb) dos inimigos e do chefe.
- sounds/ — efeitos sonoros dos inimigos e do chefe.
- textures/ — texturas de itens, inimigos, chefe, blocos e efeitos.
## **Detalhes técnicos desta versão**  
- **Origem fixa da arena:** em grandchaos.start_phase, a arena é sempre construída a partir de x=0, y=500, z=0, independentemente de onde o jogador estava ou de onde o Portal foi colocado — a posição usada para iniciar a fase não influencia a origem da arena.
- **Paredes permanentes:** diferente de uma barreira que desaparece ao limpar o trecho, grandchaos:trunk_wall nunca é removida do mundo depois de construída. A progressão acontece por teleporte, disparado ao agachar sobre o bloco luminoso de fim de trecho (uma vez aceso).
- **Trilho no eixo Z:** o eixo travado (tanto do jogador quanto dos inimigos) é o   **Z**, não o X — o corredor avança no eixo X, que é o único eixo horizontal que o modo 2D (mt2d) realmente controla via input do jogador.
- **Plataformas atravessáveis:** grandchaos:trunk_platform pode virar temporariamente grandchaos:trunk_platform_ghost (não sólida) para deixar o jogador descer através dela (agachar/baixo) ou subir através dela (pulo por baixo), voltando a ser sólida automaticamente depois de um instante.
- **5 trechos, não 3:** NUM_WAVE_SEGMENTS = 4 (o 1º desses fica vazio de inimigos, só para caminhar) mais o trecho do chefe, totalizando TOTAL_SEGMENTS = 5. Só os trechos 2, 3 e 4 têm ondas de inimigos de fato.
## **Personalização rápida**  
No topo de init.lua:

```lua  
local WIDTH = 4               -- largura do corredor (eixo Z, travado/trilho)    
local HEIGHT = 15              -- altura do corredor (eixo Y)    
local SEG_LEN = 40             -- comprimento de cada trecho (eixo X)    
local WALL_THICKNESS = 3       -- espessura das paredes    
local LAMP_GAP = 1             -- distância dos blocos luminosos até a parede mais próxima    
local NUM_WAVE_SEGMENTS = 4    -- trechos de onda (o 1º fica vazio de inimigos)    
```  
   
 E em WAVE_COMPOSITION (também em init.lua) você define quais e quantos inimigos (grandchaos:slime e/ou grandchaos:archer) aparecem em cada trecho de onda.  
   
 Vida, dano e velocidade de cada inimigo estão em entities.lua, nas tabelas initial_properties/campos de cada core.register_entity.
## External Mod
Modified mod used to this game:
- Minetest 2D (mt2d) - 2D mod for Minetest Game [Game Page]([https://codeberg.org/tenplus1/mobs_redo.git](https://content.luanti.org/packages/AiTechEye/mt2d/))
</div>
