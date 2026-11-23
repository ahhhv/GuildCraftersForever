# Changelog

## 0.4.1

### Fixes
- Cancelling a request now tells the crafter, in chat and on screen (above all if they had accepted it). The same for a board post someone had taken.
- A crafter who was offline when a request was cancelled now learns of it when they log in, instead of keeping it as accepted forever.

## 0.4.0

### New: "there's a new version" notice
- When someone in your guild runs a newer release of the addon, you get a notice in chat and on screen (once per session) telling you to update. Betas never trigger it.
- `/gcraft versions` lists which version each member has.
- Works from this version on: older versions don't share theirs.

### New: your own shortcut
- Pick any combination of Alt, Ctrl and Shift with any mouse button to request an item (Ctrl+right-click, Shift+Alt+click…): Options > **Shortcut to request an item** > Record…, or `/gcraft shortcut`.

### New: materials calculator
- Recipe tooltips (Professions and Requests tabs), the request confirmation and the crafter picker show each material as **you have / needed**.
- For what you're missing: who in the guild crafts it (Bolt of Linen Cloth: the tailors) and who gathers it (herbs, ore, leather, enchanting materials), online first.

### New: guild crafters ranking
- A new section in the Requests tab: requests and board posts each player has crafted, this month and all time. Alts count for their main.

### New: the guild board
- Post what you need to the whole guild instead of one crafter: an item someone can craft, or free text ("looking for 20 Linen Cloth").
- Guildmates who can craft it get a notice; everyone with the addon sees the post in the Requests tab, under **Guild board**. The first to press **Take it** crafts it, and the mailbox helper takes care of the materials and the item as with any request.
- Post from the **Post on the board** button in the Requests tab, from the crafter picker (Alt+click an item), or by Alt+clicking an item nobody with the addon can craft.
- Posts reach members who were offline, and expire after 7 days if nobody takes them.

### New: turn requests off
- Options > **Take recipe requests**: untick it and nobody can send you requests, and board posts don't notify you. You still show as a crafter (marked "no requests") and still see the board.

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
