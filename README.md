# Entourage

Companion drones for Factorio 2.1.

![Entourage](thumbnail.png)

Every player receives one companion automatically. It stays close, travels with its owner between planets, survives character death, and cannot be mined or killed. Companions park on the previous planet while their owners are on space platforms. There are no drone or companion equipment crafting recipes, fuel requirements, or charging delays.

## Drones

- **Six task managers per companion.** Each manager receives up to 32 nearby tasks and exactly the materials those tasks need. Managers build, upgrade, repair and deconstruct with cyan beams. They return leftovers and salvage before disappearing; full return inventories keep cargo safe in the manager until space becomes available.
- **Six crafters per companion to start.** Independent crafters reserve ingredients, land, and show the active recipe, upcoming recipe queue, counts and progress overhead. They stay at their landing positions while the owner moves. Nearby matching ghosts share batches of up to eight items, including intermediate recipes. The player's handcrafting queue is never used.
- **Custom combat escorts.** A companion launches a squad of up to four small drones from the companion. They use red combat lasers and defend the owner while the crew keeps working. Military 2, 3 and 4 strengthen the squad. Laser damage and firing-speed research continue to increase its power without adding more escorts.

The crew checks for nearby enemies first, skips work without materials or placement space, and favors urgent repairs and recent player actions. Nearby crews share task reservations, incoming recipe surplus and companion cargo. Materials come from any chest covered by poles in the owner's nearest connected electrical network, their logistics network, the player, or their vehicle. Exact reservations prevent taking an entire stack for one task. Chests marked for removal are excluded from supply and storage.

The work radius defaults to **48 tiles**, configurable from 12 to 96. The main companion normally stays within 12 tiles and recalls within two seconds, or immediately beyond 24. Managers keep their assignments while targets remain within the work radius. Landed crafters finish their reserved queue when the owner walks away, then return with the output. Cargo is preserved when return inventories are full.

![Floating intermediate crafting queue](https://raw.githubusercontent.com/luan/companion-drones-luan/main/docs/screenshots/crafting-queue-4.1.0.png)

![Parallel crafting and combat in multiplayer](https://raw.githubusercontent.com/luan/companion-drones-luan/main/docs/screenshots/crafting-and-combat.png)

![Task managers building in multiplayer](https://raw.githubusercontent.com/luan/companion-drones-luan/main/docs/screenshots/construction.png)

## Research and settings

Each non-Nauvis planet, including modded planets, receives an expensive companion development technology: 2,000 research units at 60 seconds each. It keeps the discovery research ingredients and adds planet and core science packs when a lab accepts the combination. Each completed planet improves movement, equipment and crafting, and adds one parallel crafter. Every **two planets grant another permanent companion**. Infinite promethium research grants additional companions.

The main companion is half its previous size. Mini drones use lower base flight speeds with the existing half-speed default. Change **Mini drone movement speed** in runtime mod settings (0.1 to 2×); it applies immediately to escorts, managers and flying crafters without slowing crafting or task execution.

Crafting starts at **2× recipe speed**, configurable. Infinite crafting research adds 50% of the configured starting speed and one crafter per completed level; planet development adds 25% of starting speed. Bonuses apply to work already in progress.

Normal mode starts with full equipment. Challenge mode retains ordinary research upgrades for speed, combat and equipment. Legacy modes 2 and 3 now behave as normal and challenge, respectively; obsolete forgiving recipes are gone. The old challenge checkbox remains hidden as a compatibility alias. Construction and combat can be toggled separately through shortcuts and configurable hotkeys. Chatter is optional. Each player can choose **Deadpan factory coworker**, **Unhinged gremlin**, **Roast my engineering**, **Stand-up & sitcoms**, or **Sci-fi & dungeon crawlers** under **Mod settings → Per player → Companion humor style**. Changes apply to future idle quips without a restart.

## Current limits

Autocrafting supports enabled player-craftable recipes with normal-quality ingredients and one deterministic item output. Fluids, machine-only recipes and probabilistic products require a factory.

## Credits and license

Based on Companion Drones by Klonan, kubiix, MrJakobLaich and Maoman, and Gadgetroch's Factorio 2.1 fork. Maintained by Luan. GNU LGPLv3; see COPYING.LESSER and COPYING. The original release history is retained in changelog.txt.

Drone models and animations were made in Blender. Editable sources are in `art/entourage/astra/`. The cover was generated with Imagegen; its prompt is in `art/entourage/logo-prompt.txt`. Art sources are excluded from the game ZIP.

Source: https://github.com/luan/companion-drones-luan
