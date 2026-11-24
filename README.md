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
- Use your shortcut on an item (Alt+click by default; record any combination) to request it from a guildmate.

### Guild board
- Post what you need to the whole guild, with an optional reward paid cash on delivery; whoever can craft it gets a notice, and the first to take it crafts it.
- Don't want requests? Turn them off in the options: you still see the board.

### Materials and ranking
- Recipe tooltips show the materials you have and need, and who in the guild crafts or gathers what you're missing.
- A ranking of the guild's crafters: requests and board posts crafted, this month and all time.

### Mains and alts
- Each player's characters grouped under their main, automatically (same account) or from the guild note ("alt de Jami").
- Pick your main in the options; alts can be kept private there too.

### Specializations & talents tab
- Points per talent tree for **both spec groups**, and a clickable link to each member's build in Blizzard's talent window.

## Options
Everything is in Esc > Options > AddOns > **GuildCrafters Forever**: tooltips, your shortcut to request items, sharing alts, taking requests, sound, and buttons for the guided tour, your main, members' versions, sending your data again, forgetting old members and sync diagnostics.

`/gcraft` opens the addon.

## Releasing
Publishing is automatic through GitHub Actions ([BigWigs packager](https://github.com/BigWigsMods/packager)): add a new version heading at the top of `CHANGELOG.md` and push to `main`. The workflow tags the commit and uploads it to CurseForge and GitHub Releases.

- `## 0.4.0` → Release, `## 0.4.0-beta1` → Beta, `## 0.4.0-alpha1` → Alpha.
- Pushing a `v*` tag by hand also publishes.
- The game version (WoW: Forever 1.60.x) comes from the `.toc`'s `## Interface: 16xxx`.
- The changelog is `CHANGELOG.md`.
- Needs the repository secret `CF_API_KEY` (a CurseForge API token).

## Credits
- Recipe list derived from **SkillUpForever**'s data (GPL-3.0), itself built from WoW: Forever's client tables.

## License
GNU General Public License v3.0 or later — see [LICENSE](LICENSE). Copyright © 2026 jamiforever.
