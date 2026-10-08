# Website contract evidence — 2026-10-07

Public script observed in the user's current friends-page DOM: `https://arcaea.lowiro.com/assets/index-gOl1WKik.js`, downloaded read-only into ignored `.cache/website/site.js`.
Its imported friends component is `https://arcaea.lowiro.com/assets/PageFriends-d1438VyM.js`, cached as `friends.js`.

## Confirmed from current official JavaScript

- API origin `https://webapi.lowiro.com`; credentials included. Axios uses cookie name `csrf` and header `X-CSRF-TOKEN`.
- Login is `POST /auth/login` with JSON `{email, password}`. Follow-up current account is `GET /webapi/user/me`. `/auth/me` also exists but its contract differs and is not needed initially.
- Friends read is `GET /webapi/friend/me`. Envelope `value` contains `friends`. Each friend has `user_id`, `name`, `rating`, `icon`, `is_mutual`, `recent_score` array. The UI reads first recent score with `time_played` (epoch milliseconds), `difficulty`, `difficulty_alias`, `score`, and localized `title`.
- UI friend list does not carry `needsSubscription` route metadata; score and potential pages do. This is evidence about UI gating, not proof of unsubscribed backend permission.
- Main account score routes remain `/webapi/score/song/me/all?difficulty={0..4}&page={n}&sort=date&term=`, `/webapi/score/rating/me`, `/webapi/score/rating_progression/me?duration=5y`.
- Main profile script confirms own-account recent data comes from `user/me` (see below). Full authenticated raw payloads remain unverified. Optional judgment/gauge fields may be absent.

## Live-session check

Existing browser tab initially displayed friends with recent chart/grade/time summaries. Refresh redirected to official login: the old session had expired. The user subsequently signed in again, and the profile showed an active subscription. No cookies or credentials were extracted. Public source is sufficient to implement defensive parsers with synthetic test fixtures, but not to claim a live authenticated app end-to-end pass.

## Current implementation decisions

Keep login roles `main` and `recent`/`burner` isolated even when they temporarily use the same account. Recent configuration should offer explicit **Own account (testing)** versus **Friend account** source; never silently fall back to main-session credentials. No friend additions/deletions or account-setting changes are authorized or needed.

The current `PageProfile-4IP530NI.js` reads `authUser.recent_score[0].difficulty`; authUser is populated from `/webapi/user/me`. This establishes the own-account test source from public code.

User signed in again and the profile visibly showed active subscription. Direct navigation to the API origin was blocked by the browser client. No workaround or cookie extraction attempted. The current app implementation will therefore be tested with source-grounded synthetic responses, with real authenticated app integration explicitly pending device login.
