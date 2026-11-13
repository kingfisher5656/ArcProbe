# Arcaea Online endpoints ArcProbe uses

Derived from the official website's public JavaScript (observed 2026-10). The site is not a documented API and can change; parsers in `OnlineParser.swift` are defensive and tested with synthetic fixtures only.

- Origin `https://webapi.lowiro.com`, cookie-based. CSRF: cookie `csrf`, header `X-CSRF-TOKEN`.
- `POST /auth/login` with JSON `{email, password}`.
- `GET /webapi/user/me` — current account; `recent_score` holds its newest play. Used for identity checks and for "watch the tracker account itself".
- `GET /webapi/friend/me` — `value.friends[]`, each with `user_id`, `name`, `icon`, `recent_score[]` (`song_id`, `difficulty`, `score`, `time_played` in ms, …). Used for "watch the main account as its friend". Does not need a subscription.
- `GET /webapi/score/song/me/all?difficulty={0..4}&page={n}&sort=date&term=` and `GET /webapi/score/rating_progression/me?duration=5y` — full import; need an Arcaea Online subscription.

`RequestPolicy.validate` allows exactly these URLs and nothing else. A 403, a redirect, or an HTML body is treated as "the site wants a human" (often a Cloudflare page), never as an expired login.
