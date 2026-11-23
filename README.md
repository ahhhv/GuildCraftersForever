# GuildCrafters Forever

**Who in the guild can craft that? Ask them right away.** GuildCrafters Forever turns your guild window into a shared directory of professions, recipes and talents for **WoW: Forever**, and lets you request crafts from your guildmates.

Download it from CurseForge (search for "GuildCrafters Forever", game version Forever).

## Features

### Professions tab
- **Filter by profession**, sorted by skill level.
- **Guild-wide recipe search** by recipe or item name.
- **Collapsible professions** per member, with **reagents on hover**.
- **Shift-click** a recipe to link it in chat; click to whisper the crafter.
- **Profession specializations** (Weaponsmith, Gnomish Engineer, Dragonscale…).

### Recipe requests
- **Request** button on every guildmate's recipe.
- The crafter gets a **pop-up notice**, even if they're offline: the request is relayed by any guildmate with the addon.
- **Requests tab** with a counter: accept, decline, mark as done or cancel; **Clear history**.
- **Mailbox helper**: a ready-written letter, the recipe's materials attached from your bags, and the crafted item sent back in one click.

### "Who crafts it?" tooltips
- Item tooltips show who in your guild can craft the item; recipe items show who already knows them.
- **Alt+click** an item (configurable) to request it from a guildmate.

### Mains and alts
- Each player's characters grouped under their main, automatically (same account) or from the guild note ("alt de Jami").
- `/gcraft main` picks your main; alts can be kept private in the options.

### Specializations & talents tab
- Points per talent tree for **both spec groups**, and a clickable link to each member's build in Blizzard's talent window.

## Commands
| Command | What it does |
|---|---|
| `/gcraft` | Professions tab |
| `/gcraft talents` | Specializations & talents tab |
| `/gcraft requests` | Requests tab |
| `/gcraft main` | Make this character your main |
| `/gcraft options` | Open the options |
| `/gcraft send` | Send your data again |
| `/gcraft prune` | Forget members who left the guild |
| `/gcraft status` | Sync diagnostics (for bug reports) |

## Releasing
Pushing a tag publishes to CurseForge through GitHub Actions ([BigWigs packager](https://github.com/BigWigsMods/packager)):

- `v0.4.0` → Release, `v0.4.0-beta1` → Beta, `v0.4.0-alpha1` → Alpha.
- The game version (WoW: Forever 1.60.x) comes from the `.toc`'s `## Interface: 16xxx`.
- The changelog is `CHANGELOG.md`.
- Needs the repository secret `CF_API_KEY` (a CurseForge API token).

## Credits
- Recipe list derived from **SkillUpForever**'s data (GPL-3.0), itself built from WoW: Forever's client tables.

## License
GNU General Public License v3.0 or later — see [LICENSE](LICENSE). Copyright © 2026 jamiforever.
