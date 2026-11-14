# C concept alignment review — 2026-11-12

Reference: artifacts/ui-concepts-20261112/C-lavender.png.
Native review: artifacts/c-style-preview/detail-review.html.

Compare page content at equal 390px width, excluding Android system bars. Reference panel crops start at (20 + 412 * page, 166), size 394 x 760. Native captures are 1080 x 2340 with content y=136..2208. Full screenshots remain available separately.

Corrections from direct comparison:
- Profile name 20/600; menu labels 16/400. They were previously reversed in emphasis.
- Profile block moved up 20px and card internal spacing reduced 8px.
- Main pages use one rounded 1.65px outline icon family, including navigation, creation, bell and profile actions.
- Home: independent header and card margins, closer companion portraits, recommendation tags, two-line introduction.
- Community: search control constrained to 36px instead of Material suffix's implicit 48px; compact category/author/relation/intro/tag spacing and underlined selected sort.
- Companion portraits use a closer crop only in main-page lists; unknown community uploads preserve their original framing.
- Chat user bubble and online colors stay unchanged. All navigation and data are native widgets, not image screenshots.

Validation: full 301 tests passed before final spacing-only pass; latest 20 relevant tests passed; Flutter analyze clean. Local preview package only; no backend/public deployment or commit.

Reference text/people are generated sample content. Native review uses actual Bingo fixture data, including a user's initials avatar when no photo has been set; no fake account photos are injected to improve a comparison.

## Bottom navigation review

Reviewed separately at equal width in `artifacts/c-style-preview/navigation.html`.
- 64dp app navigation with 24dp upper corner radius, pearl gradient, fine lavender border.
- Five equal cells within 8dp horizontal insets; 24dp rounded icons with 1.65dp strokes.
- 40dp central gradient disc, fine rim and round-ended 18dp white plus.
- 12dp labels, weight 600 (selected 700), 4dp icon-label gap.
- Rounded house/door, rounded bubble/tail, single compass leaf and curved profile shoulders replace approximate glyphs.
- Native clickable semantics retained for the central create button; keyboard/user scaling remain supported.

Latest navigation check: static analysis clean, 10 page/navigation tests passed; Android preview reinstalled. No commit/push/deployment.
