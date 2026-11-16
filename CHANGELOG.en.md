# StepWarden Changelog

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
