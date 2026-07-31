# Account Data Migrations

This fork stores a few things in Matrix [account data](https://spec.matrix.org/latest/client-server-api/#client-config), which is per-account state that syncs to every device you sign in on. This document records what we write, why the keys are named the way they are, and what it takes to move one.

### Why the names matter

Account data is a flat key–value store shared by **every client signed into the account**. If two clients write the same key with different content, the second one wins and the first one's data is gone. Namespacing the key is what stops that happening.

The spec suggests reverse-DNS (`io.element.*`, `im.ponies.*`) using a domain you control. That's a *convention*, not a requirement — homeservers accept any string. What actually matters is that nobody else plausibly picks the same key.

Two rules this fork follows:

- **Never write under another project's namespace.** Writing `io.element.something` that Element doesn't define means Element is free to define it later, differently, and clobber us.
- **Don't invent a type where the spec already has one.** If an MSC covers it, use the MSC's event type and namespace only the fields we add on top.

### What the fork writes

| Event type | Source | Our custom fields |
|---|---|---|
| `im.ponies.user_emotes` | [MSC2545](https://github.com/matrix-org/matrix-spec-proposals/pull/2545) | `user.sticker.sha256`, `user.sticker.added_at` |
| `user.saved_messages` | This fork | whole event |

---

## Whole-document replace

The single most important thing to know before changing any key.

`setAccountData` replaces the **entire event content**. It is not a patch. [`StickerService.save`](ElementX/Sources/Services/Stickers/StickerService.swift) encodes the whole `UserStickerPack` and sends it, so whatever the struct doesn't encode is not written back.

Two consequences:

**Migrations clean up after themselves.** Read the old key, write the new one, and the old key is gone from the server after a single save. There's no separate delete step.

**Unknown keys are dropped.** `UserStickerPack.Image` encodes only the keys in its `CodingKeys`, so any field another client added to our pack is silently discarded the next time we save. This is pre-existing behaviour, not something a migration introduced, but it's worth knowing before assuming the server copy is a superset of ours.

---

## Sticker fields out of `io.element.*` (in progress)

**Status:** fallback in place, safe to remove after one write.

The pack itself is MSC2545's `im.ponies.user_emotes` and did not move. The two fields we add on top of it did:

| Was | Is | Used for |
|---|---|---|
| `io.element.sha256` | `user.sticker.sha256` | Content hash, so re-adding an image you already have is detected as a duplicate |
| `io.element.added_at` | `user.sticker.added_at` | Timestamp, so the picker can order newest first |

These shipped on `main` before the rename, so existing packs carry the old keys. [`UserStickerPack.Image.init(from:)`](ElementX/Sources/Services/Stickers/UserStickerPack.swift) reads the new key and falls back to the old one. Encoding is left synthesised, so only the new keys are ever written.

The initialiser lives in an **extension** deliberately. Declaring an initialiser in the struct body would suppress the memberwise init that `StickerService` depends on.

### Removing the fallback

The old keys disappear from an account the first time its pack is saved — adding, collecting or removing any sticker. Once every account you care about has been through one write, delete `LegacyCodingKeys` and the whole custom `init(from:)`; the synthesised one is then correct.

For a personal fork that's "after you've added a sticker". For anything with real users, the window is however long you're willing to wait for the slowest device to sync and write, and the cost of guessing wrong is silently losing dedup and ordering on their pack.

### `added_at` was inert until now

Worth knowing if you're comparing behaviour before and after this branch. `UserStickerPack.stickers` sorted by `addedAt` and then re-sorted alphabetically by shortcode at the end of the chain, which discarded the first sort — so the picker was always alphabetical and "show new stickers first" never took effect, from the day it was added.

The trailing sort is now gone and the ordering works as documented. A pack that has never been written since the timestamp was introduced has no `added_at` on its older entries, so those stay alphabetical below anything dated, which is the intended fallback rather than a leftover of the bug.

---

## Saved Messages (`user.saved_messages`)

**Status:** no migration needed, nothing shipped under a previous name.

A pointer to the room backing Saved Messages, so a second device finds the same room instead of creating its own:

```json
{
  "room_id": "!abc:example.com",
  "created_at": 1785000000000,
  "version": 1
}
```

`version` is ours to bump if the shape ever changes; it exists so a future client can recognise an event it may not fully understand.

This was briefly written as `io.element.saved_messages` during development and changed before release, so there is nothing to migrate. `version` stays at `1`.

### Reading it safely

The room ID is only trustworthy once the first sync has landed. Account data is read from the **local store**, so asking too early reports no room and creates a duplicate. [`SavedMessagesService`](ElementX/Sources/Services/SavedMessages/SavedMessagesService.swift) waits for the room summary provider to load before deciding an account has no room.

The mirror case is handled too: if the room is created but the account data write fails, the room stays usable and the write is retried, rather than being orphaned and recreated on next launch.

---

## Moving a key

1. Add a `LegacyCodingKeys` enum holding the old names.
2. Write a custom `init(from:)` **in an extension** — in the struct body it suppresses the memberwise init. Read the new key, `??` the old one.
3. Leave `encode(to:)` synthesised so only new keys are written.
4. Keep an existing test fixture in the old format and comment it as deliberate, so nobody "tidies" it and deletes the coverage. Add one test asserting a save produces no trace of the old namespace.
5. Once accounts have been through a write, delete steps 1–2 in a follow-up commit.

Don't bump a `version` field for a key rename that the fallback handles transparently. Version is for shape changes a reader has to branch on.
