# Screenshots

Real product captures, taken from a running instance. Desktop **1440×900** PNGs
(JPEG for the oscilloscope — see below).

| File | What it shows | Used on |
|---|---|---|
| `dashboard.png` | Main dashboard — hero readout, heatmap, SLA, speed history | landing, `/features`, `/why`, getting-started |
| `oscilloscope.jpg` | Live Ookla test in the CRT oscilloscope (download phase) | `/features` |
| `ping.png` | `/ping` live per-sample diagnostics panel | `/features`, ping docs |
| `heatmap.png` | Health heatmap calendar wall | `/features` |
| `schedules.png` | Schedules table (multiple schedules) | `/features`, schedules docs |
| `settings.png` | Settings page | configuration docs |
| `history.png` | History table | (spare) |

## Wiring

Screenshots render through `<Screenshot>` (`src/components/Screenshot.astro`) —
a browser-chrome frame around an `<img>`. In `.astro` pages:

```astro
import Screenshot from '../components/Screenshot.astro';
import { asset } from '../utils';

<Screenshot src={asset('screenshots/dashboard.png')} alt="..." url="baudflow.v1n.space" />
```

In markdown docs, use a plain image (styled by `.prose img` in `global.css`):

```md
![The dashboard](/screenshots/dashboard.png)
```

## Re-capturing

Drive a browser against a running instance (the project's own instance sits
behind Authentik). Capture at 1440×900, PNG. The `oscilloscope.jpg` is JPEG
because the live panel only stays open during a run — swap it for a PNG when a
clean mid-test capture is available.
