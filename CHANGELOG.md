# Changelog

## 0.4.0-beta1

### New: "Who crafts it?" on item tooltips
- Item tooltips (bags, chat links, auction house…) show who in your guild can craft the item, online players first, and whether you can craft it too.
- Recipe items (Patterns, Plans, Formulas…) show who in your guild already knows the recipe.
- **Request it from the tooltip**: Alt+click the item to choose a guildmate and send them a request. The shortcut can be changed (Ctrl+Alt, Shift+Alt) or turned off in the options.

### New: mains and alts
- Characters of the same player are grouped under their main in the Professions and Talents lists ("Jami (+2 alts)"), with a button to show or hide the alts.
- Characters with the addon on the same account are grouped automatically; for everyone else, a guild note like "alt de Jami" or "Jami alt" is enough.
- `/gcraft main` makes the current character your main (otherwise it's your highest-level one).
- A collapsed player shows the professions of all their characters.

### New: options
- Esc > Options > AddOns > **GuildCrafters Forever** (or `/gcraft options`): tooltip lines, request shortcut, **share my alts** (on by default; untick it to keep your alts private) and notice sound.

## 0.3.1

### New: recipe requests
- **Request** button on every guildmate's recipe: ask them to craft it for you.
- New **Requests** tab in the guild window (J), with a counter for requests waiting for your answer.
- Requests reach the crafter even if they're offline, relayed by any guildmate with the addon; unanswered requests expire after 7 days.
- Pop-up notice with sound when someone asks you or answers you, and a summary when you log in.
- Accept, decline, mark as done or cancel requests; right-click to whisper the other player.
- Collapsible "Asked of you" and "Your requests" sections, and a **Clear history** button for finished requests.
- **Mailbox helper** (open the Send Mail tab): a ready-written letter for the crafter, the recipe's materials attached from your bags, and the crafted item sent back in one click (marks the request as done).

### Fixes
- Fixed a Lua error (`SpellStopCasting` blocked) when pressing Escape after using the addon.
- "View talent tree" now posts a clickable talent link in chat that opens Blizzard's talent window.
- Notices and `/gcraft` commands no longer open the guild window by themselves: press J and it opens on the right tab.

## 0.2.0 — First public release
- Professions tab: filter by profession, guild-wide recipe search, collapsible professions with reagents, Shift-click to link, click to whisper.
- Specializations & talents tab: points per talent tree for both spec groups, and each member's talent build.
- Known recipes detected automatically, offline members remembered, efficient sync.
- English and Spanish localization.
