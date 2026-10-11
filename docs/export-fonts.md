# Best 50 export typography

The user approved close open-source matches to the supplied official B50.jpg. The public Arcaea Online page loads Exo, Exo 2, Titillium Web and Open Sans. Its CardMainUser CSS explicitly uses Exo bold with a 22 px main number and 16 px fractional digits. ArcProbe applies that 16/22 ratio to the entire fractional portion, including the dot, as requested. The server-generated JPG’s precise source fonts/settings are not exposed.

Observed 2026-10-11:
- https://arcaea.lowiro.com/ko/profile/friends (public HTML font stylesheet declarations)
- https://arcaea.lowiro.com/assets/CardMainUser-DeU5uOl7.css (potential typography)
- https://arcaea.lowiro.com/assets/PageScoreData-BeCA6wVH.css (Titillium Web score/title styles)

## Bundled files and roles

| Family | Export use | Upstream |
|---|---|---|
| Exo | Mixed-size header potential | https://github.com/google/fonts/tree/main/ofl/exo |
| Exo 2 | Score, rating, rank, difficulty/clear letters, player name and ArcProbe wordmark | https://github.com/google/fonts/tree/main/ofl/exo2 |
| Titillium Web | Song titles and small potential labels | https://github.com/google/fonts/tree/main/ofl/titilliumweb |
| Open Sans | Generated date and its label | https://github.com/google/fonts/tree/main/ofl/opensans |

Original font binaries are bundled unmodified (shortened filenames for variable fonts). Variable weight axes select regular/medium/semibold/bold/light appearances. Titillium Web uses the original Regular, SemiBold and Bold files. The original SIL Open Font License notices are included beside the fonts in ArcaeaOffline/Resources/Fonts and in the built app. Fonts are registered locally with CoreText for rendering; there is no runtime font download and no change to the application’s general UI fonts. System fallback handles scripts outside the Latin fonts’ coverage.
