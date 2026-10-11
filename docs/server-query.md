# Public server query

Ranking sites and monitoring services can query each Open77 dedicated server directly,
without an API key, an Open77 account or a connect ticket. This read-only endpoint
does not change the authentication required to join a game or administer a server.

## Request

```http
GET /query/v1/status
```

```sh
curl --fail-with-body --max-time 5 http://SERVER_IP:11779/query/v1/status
```

The endpoint shares the resource HTTP listener (`resources.download.listenUrl`,
default `http://0.0.0.0:11779`). **11779 is TCP; the game port 11778 is UDP.**
Use the configured port if the operator changed it. It also works when
`resources.download.enabled` or `resources.enabled` is false; disabled download
routes remain unavailable. A reverse proxy can expose it over HTTPS, for example
`https://play.example.net/query/v1/status`. Forward that path to the resource HTTP
listener, not to Warden. `HEAD` returns the same status and headers without a body.

## Response

```json
{
  "schemaVersion": 1,
  "game": "open77",
  "name": "Open//77 Stress Test Server",
  "description": "A public multiplayer server.",
  "status": "online",
  "map": "Night City",
  "gamemode": "Freeroam",
  "numplayers": 18,
  "maxplayers": 64,
  "version": "2.31.21+op77.124",
  "uptimeSeconds": 86400,
  "startedAtUtc": "2026-10-02T10:00:00+00:00",
  "updatedAtUtc": "2026-10-03T10:00:00+00:00",
  "whitelist": false,
  "locale": "en-US",
  "tags": ["freeroam"]
}
```

The values above are examples; `version` is the actual server assembly's informational
version, including release/build metadata. It is not the Cyberpunk game version.

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Integer `1`. Ignore unknown additional fields within this version. |
| `game` | Always `open77`. |
| `name`, `description`, `locale`, `tags` | Public metadata from `identity`. Tags are an array of strings. |
| `status` | `online`, `starting`, `unresponsive` or `stopping`. |
| `map`, `gamemode` | Operator-configured labels. Empty `gamemode` means unspecified. These do not enumerate Lua resources. |
| `numplayers` | Authenticated active sessions, using the same counter as the master directory. Pending handshakes and world NPCs do not count; authenticated bot clients do count as sessions. |
| `maxplayers` | Configured player capacity. Zero online players is a valid online server. |
| `version` | Dedicated-server build string. Treat as opaque. |
| `uptimeSeconds` | Non-negative integer, elapsed server lifetime. Resets on restart; wall-clock corrections do not make it jump. Historical availability must be calculated by the poller. |
| `startedAtUtc`, `updatedAtUtc` | ISO 8601 UTC timestamps: server initialization and response snapshot creation. `updatedAtUtc` alone is not proof of a healthy game loop; check HTTP status and `status`. |
| `whitelist` | Whether the built-in whitelist is currently enabled. False does not guarantee admission: bans, capacity, resource-specific gates and connect-ticket checks still apply. |

No player names, account/provider identifiers, player IPs, tokens, convars, resource
lists, database settings or admin data are included, even if the master roster is enabled.

## Polling and errors

Poll every **30–60 seconds**, with a five-second timeout and backoff after errors.
The server caches JSON internally for at most one second. `Cache-Control: no-store`
prevents intermediaries from presenting an old success after a server outage.

| HTTP status | Interpretation |
| --- | --- |
| `200` | Ready: `status` is `online` and the simulation completed a tick within the last ten seconds. |
| `503` | `starting`, `stopping`, or `unresponsive` (no completed tick for more than ten seconds). `Retry-After: 5`. Counts are last known, not proof that the server is playable. |
| `429` | Global query budget exhausted: 60 requests per one-second window across all callers, including HEAD. `Retry-After: 1`, body `{"schemaVersion":1,"game":"open77","error":"rate_limited"}`. This limit does not affect resource downloads. |
| `404` | Query disabled, older server build, or wrong endpoint/proxy route. |
| `405` | Method other than GET or HEAD. |

A connection failure or timeout means the endpoint is unreachable. Do not treat it
as a successful report of zero players. Mark 429 as rate-limited/unknown and retry
rather than counting it as a game outage. A live HTTP listener with a stalled game
loop returns 503; a crashed process normally cannot answer at all.

## Server configuration

Add this top-level section to `server.jsonc`:

```json
"query": {
  "enabled": true,
  "map": "Night City",
  "gamemode": "Freeroam"
}
```

Omitted or null `enabled` follows `identity.visibility`: enabled for `public`,
disabled for `unlisted` and `private`. Explicit `true` enables it regardless of
visibility; explicit `false` removes the route. An older configuration needs no
changes for a public server. Configuration changes take effect after restart;
changes to the live built-in whitelist are reflected automatically.

`map` defaults to `Night City`; `gamemode` defaults to an empty string. Both accept
at most 96 UTF-8 bytes without control characters. Set an accurate mode label;
the server does not guess the mode from a resource name. Allow inbound TCP access
to the listener or expose the route through an existing HTTPS proxy.

## Integrating a ranking site or GameDig

Top-Serveurs/Top-Games or a similar poller only needs the query URL. Accept a result
as online when the HTTP status is 200, `schemaVersion` is 1, `game` is `open77`
and `status` is `online`; then read `numplayers` and `maxplayers`.

```js
const response = await fetch(queryUrl, { signal: AbortSignal.timeout(5000) });
if (!response.ok) throw new Error(`Open77 query HTTP ${response.status}`);
const server = await response.json();
if (server.schemaVersion !== 1 || server.game !== 'open77' || server.status !== 'online') {
  throw new Error('Unsupported or unavailable Open77 server');
}
console.log(`${server.name}: ${server.numplayers}/${server.maxplayers}`);
```

This is an Open77 HTTP protocol. An official GameDig integration requires a dedicated
adapter/registration; selecting its existing FiveM or Valve/A2S protocol will not
query this endpoint. Suggested GameDig mappings are `name`, `map`, `numplayers`,
`maxplayers`, `version`, with Open77 fields such as `uptimeSeconds` in `raw`.
There is no player-list response and whitelist is not a password field.

See also: [server configuration](../docs/server-configuration-and-master.md),
[authenticated RCON](rcon.md), [Prometheus monitoring](metrics.md).
