# Screenshots

Drop real product captures here. Recommended: desktop **1440×900** PNGs.

- `dashboard.png` — top of the main dashboard. Used in the landing's product
  window.

To use one in the site, edit `docs/src/components/ProductWindow.astro` and
replace the mock window body with:

```astro
<img src={asset('screenshots/dashboard.png')} alt="Baudflow dashboard" />
```

Until then, the landing renders a CSS/SVG mock of the dashboard — the site ships
either way.
