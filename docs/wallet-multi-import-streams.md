# Design: Wallet multi-import + streams-only UX

## Goals
1. Import **many** private keys in one action (hex/WIF/base64, one per line).
2. Separate **watch-only public key** import (`importpubkey`).
3. Dramatically clearer Wallet UI; Chart View interactions without turbo_frames.
4. Turbo **Streams + broadcasts** for progress/results; **never turbo_frames**.
5. Full private-key format conversion; rescan default **OFF** with correct checkboxes.

## Non-goals
- Descriptor wallet import flow
- BIP39/xprv derivation
- Replacing block archive storage

## Key Decisions
1. **Bulk private keys**: textarea; convert each via `PrivateKeyConverter`; sequential `importprivkey` with per-key stream log lines; rescan only on last key if checked.
2. **Public keys**: hex compressed/uncompressed; `importpubkey` with label + rescan checkbox (default off).
3. **No turbo_frames**: full-page renders or `turbo_stream` replace/append; `turbo_stream_from "wallet_user_#{id}"` for live log.
4. **Progress**: `Turbo::StreamsChannel` broadcasts per key result so UI updates during long imports.
5. **UTXO scan** remains primary balance path without wallet rescan.

## Architecture
| Piece | Role |
|-------|------|
| `PrivateKeyConverter.parse_many` | Bulk WIF conversion + line errors |
| `PublicKeyNormalizer.parse_many` | Bulk hex pubkey validation |
| `BitcoinRpc#import_public_key` | Core `importpubkey` |
| `WalletsController#import_keys` / `#import_pubkeys` / `#scan_utxos` | Actions + broadcasts |
| Partials `_flash`, `_log_line`, `_status_panel`, `_addresses_panel`, `_utxo_panel` | Stream targets |
| Stream name | `wallet_user_#{current_user.id}` |

## UI Structure (Wallet)
1. Header + load/refresh (turbo_stream)
2. Alerts (scanning, errors)
3. Live import log (`turbo_stream_from` + append)
4. Section switcher (vanilla JS): Private keys | Public keys | UTXO scan
5. Status panel + address table (broadcast replace)

## Rescan safety
- Hidden field `rescan=0` + checkbox `rescan=1` → default false.
- Multi-import: only the last successful key may pass `rescan: true`.

## Chart / chain_data
- Chart View: full-page forms (`turbo: false` for explorer lookups where desired).
- Chain datum CRUD: `#chain_datum_panel` replaced via turbo_stream — **no** `turbo_frame_tag`.

## PR Plan (executed in-place)
1. Key conversion + RPC methods
2. Controller + routes + stream broadcasts
3. Wallet views UX
4. Purge turbo_frames from chain_data / chart leftovers
