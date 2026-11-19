# StepWarden Changelog

## V1.0.7 - 2026-11-19 - History dates on the calendar

> Fixes the off-by-one day in the history view and adds a new-version notice. The save file gets a one-off migration; just install over the old version.

### Fixed

- **History dates were a day behind**: settling archived under `char.window`, which is the value recorded when the *previous* cycle began - one whole day earlier than the cycle that just finished. So a settlement run at 22:00 on 11-18 got filed under `2026-11-17`, and the history view always looked one day short. It now archives under the day that just ended
- **Duplicate entries for the same day in `settled`**: the old dedupe only scanned the key being settled and could not clean up records already sitting in the save. Now the whole table is scanned by date after inserting, keeping only the frontmost (newest) entry per day
- **History tabs could lose a slot**: the tab list used to be derived from whichever snapshot dates happened to exist, so a missing cycle meant a missing tab. It now always counts 0/1/2 days back from the current window - three tabs every time, with empty ones shown as empty rather than dropped

### Added

- **New-version notice**: on login the addon broadcasts an extra `V|version` message. If a peer reports something newer, it gets recorded. The bottom line of the panel normally states the ranking policy; once a newer version is seen it switches to the notice and turns gold. One notice per version
- Version comparison pads to four segments (`1.0.7` and `1.0.6.5` differ in segment count, and comparing them naively yields the wrong answer). Only a strictly newer peer triggers the notice, so being on the latest build never gets you nagged by older clients

### Migration

- On first load, existing archive dates are shifted forward one day to line up with the calendar, and duplicate entries are cleaned up in the same pass. Gated by `db.schema = 2`, runs once

### Notes

- The protocol gains a `V` message type, fully separate from the existing `S|steps|trips|kcal|date` and `Q`. Older clients ignore unknown prefixes, so data exchange is unaffected
- Save structure matches V1.0.6.5 plus one `schema` field. Install straight over it; no need to delete SavedVariables from `WTF`

---

## V1.0.6.5 - 2026-11-18 - Peers visible again

> Patch release for V1.0.6. Two fixes that made friends disappear from the board, plus a rewrite of the like-whisper copy. The UI and the save structure are untouched, so you can install straight over the previous version.

### Fixed

- **Replies to a score request carried last cycle's numbers.** When someone asked for scores, the reply preferred `settled[1]` - the most recent settled entry - including its date. The board only accepts the current cycle, so the receiver classified it as a previous-cycle result and dropped it. Asking around produced nothing. Replies now always carry the current cycle's live totals and the current cycle's date. This one is independent of which version the other side runs; V1.0.6 players hit it against each other too.
- **Date-only filtering misjudged people who were online.** The board filter compared `date` strictly and discarded anything that did not match. Older clients can attach the previous cycle's date at settlement and on reply, so a player who was perfectly online vanished from the list. When the date does not match, the filter now falls back to `ts`: a broadcast within the last day still counts, and only anything older than a day is treated as expired. The existing "no activity for two days, off the board" behaviour is preserved.

### Improved

- **Like whispers now answer to your rank**: previously everyone got the same line. Ranks 1, 2 and 3 each get their own - gold, silver, bronze - with the tone following the placement; fourth and below (plus the fallback case) share a general one. The "last cycle" qualifier is gone too, since the board only ever shows the current cycle and mentioning the previous one just made people think they were reading yesterday's results
- Both language packs were rewritten, not translated from one another. The Chinese reads like a friend ribbing you; the English leans on the dry, self-deprecating humour WoW players tend to use

### Notes

- The wire format is unchanged - still `S|steps|trips|kcal|date`, identical across V1.0.1 through V1.0.6. Old and new versions can coexist.
- The save structure is unchanged. Install over the top; there is no need to delete the SavedVariables under `WTF`.
- The board still reflects who checked in during the current cycle. If someone has not settled today and has not run `/step send`, they will not appear.

---

## V1.0.6 - 2026-11-18 - History view

### Added

- **"Last 3 days" history view.** The entry sits in the middle of the leaderboard title row. Opening it swaps the whole page over to archived data, with exactly the same layout as today - same big card, same ranking list, same rank strip - only the data source changes from live to the snapshot frozen at that day's settlement.
- **Three date tabs.** The latest three cycles sit side by side on the right of the title row, newest first, leftmost being the most recent day. Click a tab to switch days; the selected one renders in bright gold while the others stay dim.
- **"Back to today" button.** It takes the same slot as the self-like button once you are in the history view. The two are mutually exclusive and share identical size and colour.
- **Offline settlement.** If you are not online at the settlement hour, the next login finishes the archive using the final figures already saved to disk, so your entry reflects the last recorded numbers of that day. A new `lastSeen` field records the moment you went offline and is stored alongside the archived entry for later diagnosis.

### Changed

- **"Last 3 days" now matches the self-like button.** Solid gold texture, 112x26, 13 px dark text, hover brightening the fill to `0.85/0.68/0.33`. It previously used a dark fill with a gold border and gold text - a completely different visual language.
- **Date tabs share that same skin.** 82x26 solid gold. The selected tab is bright gold with dark text; the others sit at `0.32/0.25/0.11` and brighten one step on hover.
- **Leaderboard filtered by the current period.** Cached friend scores are now checked against the current cycle and excluded if they were broadcast earlier. A character who has not logged in for two days no longer lingers on today's board.
- **Paging arrows hidden when there is less than one page.** They used to stay on the title row and do nothing when the list was short. Now they are removed outright when there is nothing to page through.

### Fixed

- **History view always showed today's data.** `Refresh` called `HistDateLabel(...)` without the `AS.` prefix, so it was invoking a global that does not exist. Every pass threw at that line and aborted. Because that line sits partway through the render chain, the title, the head count, the rank strip and every row after it never ran - the panel kept whatever was drawn last time, which was today's numbers. Calling `AS.HistDateLabel(...)` restores the whole chain.
- **A single-record day was buried under the empty-state message.** The check read `shown <= 1`, and archived days often contain only yourself. That "no friend data yet" line sat across the middle of the list, looking like the tab click did nothing. Changed to `shown == 0`, and the history view now uses its own wording.
- **Date tabs sometimes failed to highlight.** A repaint cache added to reduce per-second redraws skipped the colour update when the selection happened to equal the cached value - exactly the case when returning from today to the history view. The cache is gone; colour is now set from the real state on every pass.
- **History mode state could contradict itself.** It was described by two fields, `histMode` and `selDate`. Whenever the two assignments fell out of sync you got tabs drawn while the data stayed on today. They are now merged into a single `histView`: non-empty means you are viewing that day, empty means today. The contradictory state is structurally impossible now.
- **`c.lastSeen` was dead weight.** It was initialised and then never updated or read by anything. It now refreshes on every tick.

### Notes

- Archives are written at the 22:00 settlement, so the first complete ranking after upgrading appears at the next settlement.
- Only the latest 3 cycles are kept; older ones roll off automatically.
- A snapshot only contains friends who were present at settlement. If only you had data on a given day, the history view for that day shows a single row. That is not a display bug.

---

## V1.0.5 - 2026-11-16 - UI overhaul and rank badges

### Added

- **Gold / silver / bronze badges for the top three.** The leader gets a gold crown, second gets silver, third gets bronze. The gold badge is one size larger while silver and bronze stay equal. Badges are inlined after the character name, so they follow the name length instead of colliding with the step column.
- **Paging arrows on the leaderboard.** Two arrow buttons sit at the right end of the title row for browsing past five friends. The arrow greys out and stops responding on the first or last page.
- **Options footer.** Version and author are shown centred at the bottom of the settings panel. The version is read from `AS.VERSION`, so it stays in sync when the addon version changes.

### Changed

- **Settings and close buttons now use gold-framed icons.** Gear for settings, X for close. The icons carry their own dark stone backing in the same family as the panel, so they sit flush without an extra backing block. Hover now brightens the icon itself.
- **Today card re-laid out to use the available space.** Step number 36 to 46 px. Calorie ring 82 to 148 px, centred in the right half, with the inner number raised from 26 to 46 px and the unit moved inside the ring so it cannot fall out of the card. "Steps today" and the distance line are both 18 px now, with "steps today" in dark gold.
- **The middle three stats are horizontally centred.** Walking, riding and travel now align to the card axis, symmetric with the background light band. A fixed width with centre justification keeps Chinese and English aligned.
- **Leaderboard row height raised from 44 to 49 px.** The vertical space freed by the removed like bar goes back to the list.

### Removed

- **The "like the leader" bar below the ranking.** Every row already has its own like button, so this bar was redundant and consumed vertical space. Liking still works normally.

### Fixed

- **Leaderboard snapping back to rank 1.** The refresh function wrote back the scroll position, and refresh is called very frequently by step changes and timers, so any moment with a shorter list pushed the view back to the start. Refresh now only computes a display position and never writes state.
- **The "environment diagnostics recorded" message spamming chat on login.** Diagnostics are still written to saved variables, just no longer printed to chat. Read the saved variables when you need to debug.

---

## V1.0.4 - 2026-11-16 - Battle.net friend channel

### Added

- **Battle.net friend channel.** The addon now reads the character each Battle.net friend is currently playing, so sync covers friends across factions, across guilds and across realms. Until now only the guild channel and the regular friend list worked, and anyone outside those two never appeared.
  - This client has no `BNGetFriendInfo`. The real data lives in `gameAccountInfo` on `C_BattleNet.GetFriendAccountInfo`, and the new code reads it there.
  - Friends with several game accounts are read one by one, so none are skipped.
- `/step send`: broadcasts the current score immediately and prints how many targets were attempted, how many succeeded and how many failed, so you can tell whether messages actually leave the client.
- `/step bn`: lists every Battle.net interface the client exposes, for troubleshooting.
- The environment diagnostic is now recorded silently into the saved variables on login, so no commands are needed when something goes wrong.

### Fixed

- **The send interface's return value was ignored.** The old code only checked that the call did not error out and never looked at the `false` the interface returns, so a rejected message still counted as sent. The return value is now read and successes and failures are counted separately.

### Notes

- The Battle.net channel only answers *who to send to*. **The other player also needs the same addon installed** before anything comes back. A large friend list does not mean a large ranking.
- Character names come back with an empty realm field because this client does not return one. On this server everyone shares a single cluster, so delivery is unaffected.
- The saved-variable layout is unchanged, so installing over the top is safe.

---

## V1.0.3 - 2026-11-16 - Friend sync and name fix

### Fixed

- **The ranking counted you twice.** The self-filter compared the full name from the chat message against the truncated name the client reports, so the two could never match. You ended up cached as your own friend, appearing twice in the ranking and making the friend count look low. Both name forms are now compared.
- **6+6 character names only showed the first half.** On this client `UnitName("player")` returns only the first segment of the name (for example the equivalent of just the first five characters), and the second segment is simply not in it - so no amount of parsing could produce the full name. The addon now recovers your own full name from the friend cache and uses it for the ranking and like targets.
- **Friend list entries lacked the realm suffix.** Online friends were resolved by plain name only, so cross-realm friends never received a sync message because the target was incomplete. The full name with realm is now preferred.
- **A circular dependency during initialisation.** Cleaning your own stale entry out of the cache called a name helper that itself read the cache, so the result was unreliable at init time and could delete a friend's record along with yours. The check now uses only the local half-name.

### Added

- `/step name` diagnostic: prints every name-related value the client actually returns, useful for telling whether it hands over a half name or a full one.
- `/step comm` diagnostic: prints guild status, total friends, the online friend list, cache entries, time since the last request, and whether the message prefix registered successfully.

### Notes

- Friend sync uses two channels: the guild channel for guildmates, whispers for friends. **Whether a cross-guild friend can sync at all depends on whether the client allows addon whispers** - the addon cannot decide that.
- The saved-variable layout is unchanged, so installing over the top is safe.

---

## V1.0.2 - 2026-11-16 - Name parsing fix

### Fixed

- **Character names truncated in the ranking.** WoW Forever allows character names of up to 12 characters, split into two segments separated by a space (for example `全境守护者 弥林女王`) - the whole string is the character's name. The old logic treated the space as the end of the name and kept only the part before it, so the ranking showed just the first segment. Name parsing now strips only a trailing `-Realm` suffix and preserves spaces inside the name.
- **Likes sent no whisper.** The whisper target was hit by the same truncation. It now uses the full character key, and a failure message is shown when the whisper cannot be delivered.

### Notes

- Only the display layer and message targets changed. Statistics logic, saved-variable layout and the peer cache format are untouched.
- Players on V1.0.1 can install straight over the top; the `AzerothStepsDB` save is unaffected.

---

## V1.0.1 - 2026-11-16 - First public release

### Renamed

- Addon renamed from `AzerothSteps` to **`StepWarden`**, because the original name was already taken on the addon platforms.
- Folder name, TOC filename, `## Title` and the global frame names (`StepWardenMini` / `StepWardenOptions` / `StepWardenFrame`) changed accordingly.
- **The saved variable `AzerothStepsDB` was deliberately left unchanged**, so existing step counts, trip counts and friend caches are not lost.
- The addon-message prefix `AZSteps` was deliberately left unchanged, so the addon still interoperates with guild members running the old version.
- Slash commands `/step`, `/azs` and `/azerothsteps` are all kept - nothing new to memorise.

### Added

- **Bilingual interface.** The options panel switches between Chinese and English, taking effect immediately without a UI reload.
- Selected-state marker on the language buttons: a vertical gold bar, gold fill and near-white text on the active option, so the current language is obvious at a glance.
- A like button on every ranking row, with a separate toggle for "whisper when liking".
- A dedicated backdrop and gold border for the options panel, visually consistent with the main panel.
- Adjustable panel background opacity, 10% to 100%.
- An always-on on-screen widget: today's step count stays visible without opening a command. Draggable and hideable.
- **Mounted step counting.** Running on a ground mount now counts toward steps, converted by the stride length of each species.
- `/step lang zh|en` command for quick language switching.

### Changed

- Step rate lowered to 0.42 steps per yard with a 3.2 steps/sec cap - roughly 176 steps per minute while running, so the numbers no longer go absurd.
- All fonts enlarged by one step; every text shadow removed.
- Gear icon 15 to 13 px, close cross 16 to 15 px, so the two are visually the same height; the hit areas stay 22x22.
- Long English labels shortened (`Background opacity` to `Opacity`, and so on) so they no longer overlap the controls on the right.
- Ground mounts converted by per-race mount stride: 176 steps/min on foot, 143 to 185 steps/min mounted.
- Flight-point travel now accumulates distance only and no steps; distance tracking now covers all four paths - walking, mounted, flight point and boat.
- The options panel keeps only one button at the bottom, "Clear today", centred across the full row; "Clear friends" and "Clear all" were removed.

### Fixed

- On-screen widget not appearing: an error inside `BuildMini` skipped the entire build; now wrapped in pcall.
- The ranking counted the player as two people: message handling did not filter out the sender, and character names carried a realm suffix.
- Options panel opacity value not refreshing while dragging: a local declared in the wrong order was reading a global nil.
- Static labels not following a language switch: `Relocalize()` now resets all 22 panel elements on the spot.
- Chinese characters left behind after switching to English (the language button label and the TOC notes).
- With many friends, `Q` / `S` messages were silently dropped by addon-message throttling; they are now sent in batches of two every 0.5 seconds.
- Answering a `Q` request re-broadcast to the whole guild, so N players replying to each other produced N times N traffic; replies now go only to the requester, by whisper.
- A `Q` request was re-sent on every zone change and instance entry; a 30-second cooldown was added.
- Distance not accumulated at all while mounted or travelling by flight point: only the walking branch was adding to `yards`.

### Compatibility

- One set of files serves both Retail 12.1.5 (Interface `120105`) and WoW Forever 1.60.1 (Interface `16001`).
- The TOC declares `## Interface: 16001, 120105`.
- No third-party libraries; native API only.

### Installation notes

- **After a first install, or after renaming the addon folder, fully exit the client and restart.** `/reload` alone does not make the game rescan the AddOns folder; the symptom is the addon simply not appearing in the addon list.
