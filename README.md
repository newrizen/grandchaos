<div align="center">
  
<p align="center">
  <a href="README.md"><img src="https://img.shields.io/badge/🇺🇸-English-blue"></a>
  <a href="README.pt.md"><img src="https://img.shields.io/badge/🇧🇷-Português-green"></a>
</p>

# **GrandChaos - Phase 1 (Aria Forest)**

  <a href="https://www.minetest.net/">
    <img src="https://img.shields.io/badge/Minetest-5.15+-blue?logo=minetest">
  </a>
  <img src="https://img.shields.io/badge/version-prealpha-red">

  GrandChaos, a Minetest Game (Luanti) mod based on GrandChase

  <img 
    src="https://github.com/newrizen/grandchaos/blob/main/images/screenshot_20260719_112754.png"
    alt="GrandChaos Screenshot"
    width="350">
</div>

<div>
  
>[!IMPORTANT]
>This game is experimental, so expect to encounter many bugs and incomplete features.
  
Mod for **Luanti / Minetest Game** that recreates, in its own way, the first stage of the game GrandChase: a combat corridor on   **rails** (the character only moves forward and backward, without lateral movement), divided into sections closed by   **permanent and indestructible log walls**, with 3 enemy sections and a final boss. The enemies themselves also only move forward/backward, like the player. The mod also includes an experimental 2D visual mode (mt2d), used throughout the stage.
## **Installation**  
1. Copy the entire grandchaos folder to your game/world's mods folder, for example:
- ~/.minetest/mods/grandchaos (global mod), or
- YOUR_WORLD/worldmods/grandchaos (only for a specific world).
1. In the game, go to **Configure** →   **Mods** and activate grandchaos (it only depends on the default mod, which already comes with Minetest Game).
2. Enter the world.
## **How to play**  
Upon entering the world, whoever doesn't yet have a stage in progress sees a fixed hint at the top of the screen explaining the two starting commands:
- Type in chat: /gcstart
  - Builds the stage's corridor **always at the same fixed origin, ** **x=0, y=500, z=0** (does not depend on where the player was standing), activates   **2D mode** (see below) if it isn't already active, gives the   **starting sword (Shinai)** to the player and unlocks   **section 1**.
  - Alternatively, use /gcportal to receive a Portal block: place it anywhere and right-click to start the stage from there (the arena's origin remains always the same, y=500).
- **Rail movement:** while the stage is active, the character's Z axis is locked (it's the only axis the corridor doesn't use) — you only move forward/backward on the X axis (W/S) and jump (spacebar). The camera remains free.
- The stage has **5 sections** in total: the 1st is just a walking corridor (no enemies), sections 2, 3 and 4 have enemy waves, and the 5th is the boss arena. Each section ends in a   **permanent log wall** (grandchaos:trunk_wall) that never disappears — the passage to the next section isn't by destroying or removing the wall, but by a luminous block on the ground, right before it: 
  1. The block starts **off** (glass) while there are living enemies in the section.
  2. It **lights up** (default:meselamp) as soon as all enemies are defeated.
  3. With the block lit, simply **walk to it and crouch (sneak)** to be teleported to the start of the next section. Section 1 has no enemies, so its block is already lit from the start.
- **Going back:** the luminous landing block (start) of an already cleared section can also be used, the same way (crouching on it), to return to the end block of the previous section. On the landing block of section 1, crouching exits the stage entirely (restores the terrain and takes the player back to spawn).
- **Traversable platforms:** while standing on a log platform (grandchaos:trunk_platform) and pressing crouch/down, it becomes passable for an instant and you fall through it; jumping from underneath a platform has the same effect, letting you climb up through it.
- After the 4th section, the **boss** appears in a larger arena at the end of the corridor (in the code he's called either "Guardian Golem" or "Guardian Ent" — both names appear in different messages). He has a lot of health, attacks in melee, delivers an area seismic strike after jumping and sitting, and fires bursts of fruit at range.
- Upon defeating him, he drops coins, the **completion sword (Bokken)** and the   **Aria Forest Trophy** as items on the ground (they aren't given automatically to the inventory); a victory message appears in chat and the movement lock is released.
- **Enemies also on rails:** each enemy is locked to its own Z axis (can't move laterally) — it only advances or retreats along the corridor (X axis) to get close to you. The boss walks its own track, slightly offset from the player's/platforms' track.

**2D Mode (experimental)**
The mod includes a 2D view mode (mt2d.lua and mt2d_entities.lua files), used automatically during Phase 1. It can also be activated outside the stage:
- /join2d — manually enters 2D mode.
- /leave2d — exits 2D mode and returns to normal 3D (requires the leave2d privilege; doesn't work with a grandchaos stage in progress — use /gcreset first).

Other commands:
- /gcreset — cancels the stage in progress, removes remaining monsters, releases movement and restores the original terrain from where the arena was built.
## **Mod structure**  
- mod.conf — mod metadata (depends on default).
- items.lua — hero swords (Shinai/Bokken), log wall and platforms (grandchaos:trunk_wall, grandchaos:trunk_platform and its passable "ghost" variant), floor blocks, portal, coins (copper/silver/gold/ platinum) and the trophy.
- entities.lua — enemies: Slime (melee, with jump lunge) and Archer (ranged, with its own arrow and "sits" after quick consecutive hits), plus the final boss (lots of health, area attack and fruit burst); all locked to their own Z axis.
- init.lua — arena construction (fixed origin at x=0,y=500,z=0), wave system, checkpoints via luminous block + crouch, section progression/return, traversable platforms, boss spawn, terrain restoration, instructions HUD, chat commands and the player's rail movement lock.
- mt2d.lua / mt2d_entities.lua — implementation of the 2D view mode used by the stage (camera, player visual entity, animations, /join2d//leave2d commands).
- models/ — meshes (.glb) of the enemies and boss.
- sounds/ — sound effects of the enemies and boss.
- textures/ — textures of items, enemies, boss, blocks and effects.
## **Technical details of this version**  
- **Fixed arena origin:** in grandchaos.start_phase, the arena is always built from x=0, y=500, z=0, regardless of where the player was or where the Portal was placed — the position used to start the stage doesn't influence the arena's origin.
- **Permanent walls:** unlike a barrier that disappears when the section is cleared, grandchaos:trunk_wall is never removed from the world after being built. Progression happens via teleport, triggered by crouching on the section's end luminous block (once lit).
- **Z-axis rail:** the locked axis (both for the player and enemies) is   **Z**, not X — the corridor advances on the X axis, which is the only horizontal axis that 2D mode (mt2d) actually controls via player input.
- **Traversable platforms:** grandchaos:trunk_platform can temporarily turn into grandchaos:trunk_platform_ghost (non-solid) to let the player descend through it (crouch/down) or climb through it (jump from underneath), automatically becoming solid again after an instant.
- **5 sections, not 3:** NUM_WAVE_SEGMENTS = 4 (the 1st of these has no enemies, just for walking) plus the boss section, totaling TOTAL_SEGMENTS = 5. Only sections 2, 3 and 4 actually have enemy waves.
## **Quick customization**  
At the top of init.lua:

```lua  
local WIDTH = 4               -- corridor width (Z axis, locked/rail)    
local HEIGHT = 15              -- corridor height (Y axis)    
local SEG_LEN = 40             -- length of each section (X axis)    
local WALL_THICKNESS = 3       -- wall thickness    
local LAMP_GAP = 1             -- distance from luminous blocks to nearest wall    
local NUM_WAVE_SEGMENTS = 4    -- wave sections (the 1st has no enemies)    
```  
   
 And in WAVE_COMPOSITION (also in init.lua) you define which and how many enemies (grandchaos:slime and/or grandchaos:archer) appear in each wave section.  
   
 Health, damage and speed of each enemy are in entities.lua, in the initial_properties/fields tables of each core.register_entity.
## External Mod
Modified mod used for this game:
- Minetest 2D (mt2d) - 2D mod for Minetest Game [Game Page]([https://codeberg.org/tenplus1/mobs_redo.git](https://content.luanti.org/packages/AiTechEye/mt2d/))
</div>
