# Changelog

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
