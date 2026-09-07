# Time saved in Clipp

Settings → Time saved shows activity on this Mac for today, the last 7 or 30 calendar days, or all recorded time. Totals start with version 2.7; old clipboard history is not converted into invented past usage.

| Metric | Definition | Status |
| --- | --- | --- |
| Clipboard reuses | Explicit history selections whose primary payload differs from the current clipboard | Counted activity |
| Typed expansions | Automatic replacements whose inserted text is confirmed through Accessibility | Counted activity |
| Characters avoided | Sum of `max(0, expansion length − abbreviation length)` | Counted characters |
| Estimated time saved | Modeled typing time plus assumed retrieval savings | Estimate, not a stopwatch |
| Average per active day | Estimated total divided by days with a counted reuse or expansion | Modeled average; inactive days excluded |

Characters include spaces and punctuation and use Swift’s user-perceived character count, not physical key presses. The preserved Space delimiter adds no net saving. Previews, skipped/failed expansions, manual snippet selections, background capture, and ordinary Command-V presses do not add expansion statistics. Selecting the current clipboard item earns no retrieval saving. A history selection counts as retrieval even when the user pastes it later.

## Typing calculation

`seconds = characters avoided × 60 ÷ (5 × words per minute)`

The default is **50 WPM**, adjustable from 10 to 200. At 50 WPM, 250 avoided characters represent one minute. `;em` → `username@domain.com` avoids 16 characters, about 3.8 seconds.

[TextExpander’s official method](https://textexpander.com/learn/accounts/statistics/textexpander-statistics-calculated) subtracts the abbreviation from expanded characters, treats a word as five characters, and defaults to 50 WPM. Clipp uses the same dimensional conversion. This models typing effort, without measuring composition, proofreading, correction, or app latency.

The [Aalto/Cambridge CHI 2018 study](https://userinterfaces.aalto.fi/136Mkeystrokes/) collected data from 168,000 volunteers. [Aalto’s report](https://www.aalto.fi/en/news/the-traits-of-fast-typists-discovered-by-analysing-136-million-keystrokes) gives a mean of 52 WPM. Participants transcribed randomized sentences and were self-selected, predominantly young and interested in typing. This supports 50 as a rounded starting assumption, not a measurement of every office worker or Clipp user.

## Clipboard calculation

`seconds = clipboard reuses × assumed seconds saved per reuse`

The default is **5 seconds**, adjustable from 0 to 30; 0 excludes it. This is Clipp’s illustrative assumption, **not an empirical copy/paste average**. The comparison is finding an older item’s source, copying it again, and returning, versus retrieving it with Clipp. It does not assume the whole text would have been retyped.

The [Keystroke-Level Model, Card, Moran & Newell, 1980](https://doi.org/10.1145/358886.358895) predicts routine expert interactions from component actions. Example timings include 1.35 seconds for mental preparation, 1.1 for pointing, 0.4 for moving a hand between devices, and 0.2 per key for an average skilled typist. A hypothetical additional two mental preparations, one point, two hand movements, and two key presses total five seconds. This is an illustrative inference, not a validated modern clipboard workflow or a claim that every reuse removes those actions. A controlled study of actual workflows would be needed to establish a reliable empirical default.

Users can adjust their net saving after timing comparable manual and Clipp retrievals. Search time, app switching, familiarity, and source availability can make the real difference smaller, larger, or negative. The display estimates positive effort avoided; it does not measure net productivity or subtract slow sessions.

## Interpretation and privacy

Changing assumptions recalculates every period. Totals are rounded to minutes; positive sub-minute amounts display as “<1 min.” No percentile, salary, annual projection, or “faster than other users” claims are made: there is no comparison cohort.

Only daily aggregate counts are retained locally. Statistics contain no text, snippet identifiers, app names, URLs, or individual event times, and have no network reporting. Recording can be paused; reset affects only statistics. Development tests use separate preferences and do not inflate live totals.
