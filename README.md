# ODDBOUT Twitch Cup

Turn Twitch chat into a four-fighter tournament. Viewers pick a fighter with `!join <fighter>`, the host starts the cup, and two semifinals and a final play automatically. The last fighter standing becomes champion.

**[Play the hosted cup](https://oddbout.com/twitch.html)** · **[Project on Devpost](https://devpost.com/software/oddbout-x-twitch-cup)** · **[Watch the video demo](https://youtu.be/Nu2VzDw-ilY)**

This repository is the standalone Twitch Cup client extracted from ODDBOUT: a TypeScript/Vite application with a Phaser battle host. It includes built-in fighters and can load approved creator fighters from the public ODDBOUT service. The creator agent, MCP server, and plugin described in the wider project are separate from this repository.

## Start here

| Goal | Read |
| --- | --- |
| Run a cup locally | [Quick start](#quick-start-without-twitch) |
| Connect a Twitch channel | [Twitch setup](#connect-twitch) |
| Understand the code | [Architecture](docs/architecture.md) |
| Develop with Codex | [AGENTS.md](AGENTS.md) and [development workflow](docs/development.md) |
| Choose tests and verify changes | [Testing guide](docs/testing.md) |
| Investigate first-bout loading | [Performance notes](docs/performance.md) |
| Review fixes and remaining work | [Review record](docs/review-2026-11-02.md) |

The README is in English; the detailed developer and agent guides are in Korean.

## Quick start without Twitch

Use **Node.js 22** and **npm**. Run the following from a terminal:

```sh
git clone https://github.com/jeonghwanko/oddbout-twitch-cup.git
cd oddbout-twitch-cup
npm ci
npm run dev
```

If you already have the repository, start with `npm ci` from its root. An `.env` file, Twitch account, and API key are not required for the local demo.

1. Open [http://localhost:5178/twitch.html?lang=en](http://localhost:5178/twitch.html?lang=en).
2. Expand **Try it solo** and select **Try without Twitch**.
3. Select **Fill all 4 slots**, then **Start cup**.
4. Keep the tab visible while the three matches play. After the champion appears, select **New cup** to reset the lineup and bracket.

There is no `index.html`: open `/twitch.html`, not `/`. Port **5178** is strict; if another process uses it, stop that process or the existing development server before starting a new one. Source edits reload the development page, which resets the current cup.

## Run a tournament

| Mode | Participants | Connection |
| --- | --- | --- |
| Live cup (default) | Four different viewers, each with a different fighter | Broadcaster's Twitch account and own channel |
| Solo rehearsal | The connected broadcaster enters four different fighters | Twitch connection; **Enable solo rehearsal** before registering |
| Local demo | Simulated viewers added through the page | No Twitch connection |

The first and second entrants meet in semifinal 1; the third and fourth meet in semifinal 2. Exactly four entrants are required to start. Winners advance automatically. Registration closes when the cup starts, and repeated or stale results cannot advance the bracket again.

Viewers choose a fighter from **Choose a fighter**, copy its command, and paste it in the broadcaster's chat. A message must contain only the join command, for example:

```text
!join kuma
```

The nine built-in commands are `kuma`, `yume`, `bravow`, `beotim`, `quickcat`, `kungjjak`, `sikeundung`, `duldul`, and `eoridung`. Commands are case-insensitive. Ordinary live registration rejects duplicate viewers and fighters; solo rehearsal relaxes only the viewer restriction for the verified broadcaster.

**Stream view** hides the host controls for a cleaner broadcast layout; **Host view** restores them. Keep the game tab visible during the stream. The cup runs in the browser, and a fresh page load does not restore an earlier tournament. A failed bout exposes **Retry match**, which retains its pairing and seed. **New cup** starts a fresh tournament; disconnecting also clears the old cup.

The Cup and exhibition screens share the Broadcast Studio visual style: cream backgrounds, navy stages, lime highlights, and the existing ODDBOUT portraits. `src/broadcast-theme.css` owns their shared colors and typography; `src/twitch.css` and `src/broadcast.css` own each layout. The Twitch page in `crashbang-heroes/kaito_web` is a separate implementation; changes do not sync between repositories automatically.

## Agent exhibition renderer

`/broadcast.html` is a separate stream view for a locally controlled agent runner. It starts idle and runs actual Phaser battles through the existing same-origin `fighter.html` host. It does not connect Twitch chat, register viewers, or process payments. The ordinary Twitch Cup modes remain unchanged.

The runner calls `window.oddboutBroadcast.runCup({ jobId, leaseToken, seed, fighterIds })`. Protocol version 1 requires a uint32 seed and exactly four unique fighter IDs, for example `kuma`, `yume`, `bravow`, and `beotim`. The first two and last two meet in the semifinals; their winners meet in the final. Bout seeds are `(seed + index) >>> 0` for indices 0–2. Registered fighters use the existing runtime package loader and current approval checks.

The returned promise contains `{ protocolVersion: 1, jobId, leaseToken, seed, winnerId, bouts }`; each bout contains `leftId`, `rightId`, `winnerId`, `seed`, and the engine's `winner`, `how`, `ms`, `hp`, `contacts`, and `digest`. The lease token may be a nonempty string or a positive safe integer fence; its type and value are preserved. `getStatus()` reads progress and `cancel()` stops pending work. Same-job retries with identical arguments reuse the in-memory result; changed arguments or leases conflict, and another active job is rejected. Failed or cancelled jobs stay terminal for that page session. Reloading clears this history: the runner must persist and reconcile jobs externally.

Only validated origin, iframe source/document, attempt ID, pairing, seed, and result messages advance the bracket. An iframe document replacement during a cup rejects the job before replaying a start token. Readiness is not victory; errors/timeouts reject without producing a champion. Job and lease identifiers are not shown on stream. Keep credentials, wallet logic, and paid-job authorization in the runner/backend; this browser API is an exhibition renderer, not an authorization boundary. Keep the browser visible and prevent host sleep during execution.

### YouTube Live (experimental)

[`youtube-live/`](youtube-live/README.md) streams this exhibition page to YouTube Live from a headless Linux host: Xvfb shows the page, a Playwright runner calls `runCup` cup after cup, and OBS or ffmpeg sends the display to YouTube over RTMPS. The stream key comes only from `YOUTUBE_STREAM_KEY`. Run `youtube-live/run.sh --record=170 --cups=1` to rehearse without a key.

## Connect Twitch

1. Create an app in the [Twitch developer console](https://dev.twitch.tv/console/apps).
2. Register `http://localhost:5178/twitch-auth.html` as its OAuth redirect URL.
3. Put the app's **public Client ID** in `VITE_TWITCH_CLIENT_ID`, or enter it under **Connection settings** on the page.
4. Select **Connect Twitch** and sign in as the broadcaster. The app reads that account's own chat channel.
5. Let four viewers join, or open **Try it solo** and enable solo rehearsal to register four different fighters from the broadcaster account.

The client requests `chat:read`. It needs no Twitch client secret and does not post chat commands or announcements. The access token stays in memory; reconnect after a fresh page load. The OAuth callback validates its opener and state, and the main page validates the returned account and scope.

For another host, register that host's exact `/twitch-auth.html` callback URL as well. A different hostname, port, or path is a different redirect URL. The callback page and cup must be served together.

## Configuration

Configuration is optional. Copy the example only when you need Twitch defaults or the creator roster; do not overwrite an existing `.env`.

```sh
cp .env.example .env
```

In PowerShell, use `Copy-Item .env.example .env` instead.

| Variable | Purpose | When absent or empty |
| --- | --- | --- |
| `VITE_TWITCH_CLIENT_ID` | Public Twitch application Client ID | Enter it in Connection settings when connecting |
| `VITE_AI_FIGHTER_API_BASE` | Public fighter service endpoint; the example contains the ODDBOUT endpoint | Built-in fighters only |

Restart the development server after editing environment files. For a production build, set these values **before** `npm run build`; changing the static host's environment does not rewrite built JavaScript. Vite environment variables are public browser configuration. Never put a client secret, access token, service credential, or other private value in `VITE_*` variables.

### Creator fighters

With the fighter service configured, the page fetches the roster once and adds approved fighters while registration is open. A cup already running keeps its existing participants. Packages and art load at runtime and are not checked into this repository.

Use the command shown in **Choose a fighter**. Commands are derived from each fighter's English name by retaining lowercase a–z and 0–9. An empty or conflicting name falls back to `f` plus the first six hexadecimal characters of the fighter's ID, extending the prefix if needed. Reload the page to refresh the roster before starting a new cup.

If the service is missing or unavailable, the nine built-in fighters remain usable. Clear `VITE_AI_FIGHTER_API_BASE` in the active environment to deliberately run without the service. Endpoint validation currently accepts the Supabase `functions/v1/ai-fighter` URL shape implemented in [fighterApiBase.ts](src/platform/fighterApiBase.ts); this is not a generic arbitrary-URL API adapter.

## Development commands

| Command | Effect |
| --- | --- |
| `npm ci` | Install the lockfile's dependency versions |
| `npm run dev` | Development server on strict port 5178 |
| `npm test` | All `test/**/*.test.ts` tests |
| `npm test -- test/twitch-tournament.test.ts` | A focused test file |
| `npm run test:browser -- --seed=123` | Three real local Chrome bouts, champion and New cup; requires a running local server and installed Chrome |
| `npm run lint:types` | TypeScript checking; this is not a formatting linter |
| `npm run build` | Production build in `dist/` |
| `npm run check` | Type checking → all tests → production build |
| `npm run preview` | Serve the last production build on strict port 5178 |
| `npm run analyze:build` | Report chunk sizes and module contributions without changing `dist/` |
| `npm run analyze:build -- bundle-report.json` | Also save the full bundle report to a local JSON file |
| `npm run measure:first-bout -- --ports=5186,5187,5188` | Local no-store/gzip server for first-bout browser measurements; run after building |

Stop `dev` before using `preview`, since both use port 5178. Rebuild after source or environment changes before testing with `preview`. Generated bundle reports are local diagnostic artifacts; avoid committing them unless the task specifically needs a baseline.

[GitHub Actions](.github/workflows/check.yml) runs `npm ci` and `npm run check` on Node 22 for pushes and pull requests. The workflow does not deploy the site. Feature-specific tests and browser checks are documented in [testing.md](docs/testing.md). Automated tests cover tournament rules, authentication/message boundaries, recovery, UI lifecycle, media contracts, and build budgets; they do not replace testing actual Twitch login, live chat, or browser rendering.

## Repository map

| Path | Responsibility |
| --- | --- |
| `twitch.html` → `src/twitch.ts` | Lobby, bracket, roster, Twitch connection, iframe lifecycle |
| `broadcast.html` → `src/broadcast.ts` | Agent exhibition API, stream bracket, validated iframe lifecycle |
| `twitch-auth.html` → `src/twitchAuthCallback.ts` | OAuth callback page |
| `fighter.html` → `src/fighter.ts` | Embedded battle entrypoint |
| `src/app/TwitchTournament.ts` | Pure registration and tournament state transitions |
| `src/app/TwitchArenaBout.ts`, `TwitchBoutRecovery.ts` | Battle message validation, request identities, retry rules |
| `src/platform/` | Twitch authentication/chat, fighter service and browser integrations |
| `src/render/boot/TwitchArenaBoot.ts` | Host startup, loading, battle transitions and results |
| `src/render/`, `src/sim/` | Presentation and seeded combat simulation respectively |
| `src/assets/`, `src/world/`, `contracts/` | Runtime catalogues, world data, fighter format contracts |
| `public/` | Static media and fonts copied into `dist/` |
| `build/`, `scripts/` | Build-time media projection and bundle analysis |
| `test/`, `docs/` | Regression tests and development references |

The parent page owns the bracket. A single iframe normally hosts consecutive matches, receives validated start requests, and returns ready/error/result messages. Only a result matching the expected origin, window, bout ID, fighters, and seed can update the cup. See [architecture.md](docs/architecture.md) before changing these boundaries.

The broadcast host uses Phaser's timer scheduler with unsmoothed elapsed time. This prevents stalled `requestAnimationFrame` delivery from stretching a match until the unchanged 240-second timeout. Ordinary game pages retain their frame policy; combat rules, seeded results, intro and hitstop remain unchanged. A hidden or suspended browser still cannot be relied on to run a stream. The [local browser test](docs/testing.md#로컬-playwright로-세-경기-검증) can reproduce a 1 Hz rAF stall and verify three complete bouts without Twitch credentials.

## First-bout performance

The 2026-11-02 optimization reduced the two largest JavaScript chunks from **2,501,152 to 2,173,799 bytes (13.09%)**, or **8.49%** using the analysis script's gzip settings. This measures those two chunks, not the whole page or elapsed loading time.

The build uses the same Phaser 3.90.0 version's official Arcade distribution, strips unused provenance fields from the runtime media payload while keeping the source records, and excludes a village-only KTX2 catalogue from the arena dependency graph. Battle-module loading overlaps game/font initialization. Seeded combat rules remain unchanged.

In a separate follow-up, three cold-HTTP-cache Chrome runs on local loopback measured **6.94 → 6.01 seconds median** from Start cup to battle-ready. Removing 17 unused front/back/diagonal movement sheets and preloading the same required fonts reduced completed iframe resource bodies from **16.14 → 12.45 MB**. This is a small local sample, not a production or mobile latency guarantee; OS/GPU caches were not reset. A later full-cup smoke run reached ready in 1.34 seconds with no HTTP cache hits, showing substantial run-to-run variability; its observation is also recorded.

Large-chunk warnings still exist. Use the [measurement procedure, sample records, and byte budgets](docs/performance.md) to investigate them; do not suppress warnings or raise budgets without understanding the dependency change. The village screen is not an entrypoint, but some inherited village-related shared code and data remain in the dependency graph.

## Build and host

```sh
npm run check
npm run preview
```

Deploy the complete `dist/` directory to a static HTTP(S) host. Serve production over HTTPS. Keep all three HTML entrypoints, generated scripts/styles, and media together on the same origin. There is no application server or database migration to run in this repository.

The current build expects hosting at the origin root; fonts use `/fonts/...` paths. Subpath hosting requires an explicit asset-path/base configuration review. Point users to `/twitch.html`, or configure a root redirect to it. Do not rewrite the OAuth callback, battle HTML, or asset requests to the lobby page.

Set public environment values before building and add the production callback URL to the Twitch app. Uploading source changes to GitHub and publishing a new static build are separate actions.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| `/` is blank or unavailable | Open `/twitch.html?lang=en`; there is no index entrypoint |
| Server cannot start | Port 5178 may already be used by `dev` or `preview`; do not silently change OAuth ports |
| Twitch sign-in fails | Check the public Client ID, exact redirect URL, popup access, and broadcaster account |
| No one can join | Check that chat is connected and registration is open; use one complete `!join` command from the displayed roster |
| The same account cannot take four slots | Enable solo rehearsal before registering; only the connected broadcaster may use it |
| Creator fighters are missing | Check the public API configuration; built-in-only mode is expected without the service |
| A match fails to load | Keep the tab visible, inspect the error/Activity message, then use Retry match; do not manually alter the bracket |
| Returning to the page shows Retry match | A browser back/forward-cache restore requires a fresh battle attempt with the same pairing and seed; a full reload instead resets the cup |
| Code changes are missing in preview | Run `npm run build` again; preview serves the previous build |
| Build reports large chunks | Consult the performance report and budget tests; a warning alone is not a build failure |

## Scope and credits

This extraction preserves the Twitch URL parameters and iframe messaging protocol. It omits the original site's account sign-in, gold counter, arena selection, weekly tournaments, background music, and ambience. Combat effects, fighter voices, UI sounds, and shared combat/rendering utilities remain. Ranked duel creation is disabled; cup results are local exhibitions.

Some inherited files support systems outside the Cup. A file's presence does not prove it runs in this build; inspect imports and callers before removing it. Do not copy private creator packages, credentials, or unrelated personal documents into the public repository.

See [NOTICE.md](NOTICE.md) for shipped third-party media and font credits. No project license is granted by this repository; the owner decides the license.
