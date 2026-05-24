# Angular WebUI — v16 → v21 Upgrade Notes

This document covers what it took to upgrade the Angular WebUI from v16 to v21 and extend it
with all the features from the React+MUI flavor. It exists so that maintainers and contributors
understand why the codebase looks the way it does and can repeat (or extend) the work.

---

## Why the Upgrade Was Hard

The starting point was Angular 16 with four compounding blockers that meant a direct jump to
v21 was not possible — every `ng update` failed or produced a broken build.

| Blocker | Root cause | First breaks at |
|---|---|---|
| `@angular/material` at v14 with Angular v16 | Pre-existing mismatch in the codebase | Blocks every `ng update` |
| `@angular/flex-layout` abandoned by Google | No Angular 17+ build exists | Angular 17 |
| `@angular/material/theming` SCSS entrypoint | Deleted in Material v17 | Angular 17 |
| `browser` (Webpack) builder | Physically removed from CLI | Angular 19 |

Because each of these only surfaces at a different version boundary, the only safe path was to
step through every major version, fixing each batch of breaks before moving to the next. Jumping
two versions at once leaves you with overlapping error sets that are difficult to isolate.

---

## Upgrade Path

```
Angular 16  (Material 14 mismatch, abandoned flex-layout, Webpack builder)
    │
    ▼  Step 0 — Material 14 → 16 + MDC migration
    │  SCSS theming rewrite · 25 of 44 tracked issues resolved here
    │
    ▼  Step 1 — Angular 16 → 17
    │  @angular/flex-layout → @ngbracket/ngx-layout · remove rxjs-compat
    │
    ▼  Step 2 — Angular 17 → 18  (most complex step)
    │  browser builder → application (esbuild) · locale output path fix · ESLint flat config
    │
    ▼  Step 3 — Angular 18 → 19
    │  standalone: false flags · M2 SCSS prefix · toPromise() removal
    │
    ▼  Step 4 — Angular 19 → 20
    │  Node ≥ 20.19.0 hard requirement — upgrade dev machines and CI first
    │
    ▼  Step 5 — Angular 20 → 21
       TypeScript 5.9 · current Active LTS (supported to 2027)
```

44 issues were catalogued across all six phases. The breakdown by step:

| Step | Issues | Notes |
|---|---|---|
| Step 0 | 25 | Hardest single step — almost every UI component needed updating |
| Step 1 | 4 | flex-layout swap + dead package removal |
| Step 2 | 9 | Builder migration + the locale bug (see below) |
| Step 3 | 3 | Small — mostly deprecation removals |
| Step 4 | 2 | Node version gate |
| Step 5 | 1 | Minor |

---

## Notable Issues

### Step 0 — The MDC Migration

Material 15 replaced the old "non-MDC" component implementations with MDC-based ones.
Every CSS class name changed (`mat-row` → `mat-mdc-row`, `mat-chip-list` → `mat-chip-set`,
etc.), the slider API changed, form-field default appearance changed, and the SCSS theming
entrypoint (`@angular/material/theming`) was deleted.

The biggest impact was the **form-field appearance default**: in Material 14 the default was
`legacy` (underline only). In v15+ `legacy` is gone and the new default is `fill` (filled box).
35 form fields across the app — including the login page — would have changed appearance without
a global fix:

```typescript
// shared.module.ts — providers array
{ provide: MAT_FORM_FIELD_DEFAULT_OPTIONS, useValue: { appearance: 'outline' } }
```

The SCSS theming system was rewritten from scratch. The old `mat-palette()` / `mat-light-theme()`
/ `mat-dark-theme()` functions are gone. The new system uses `mat.define-theme()` with CSS custom
property overrides for dark mode.

### Step 2 — The Locale Output Path Bug

This was the most dangerous silent failure in the entire upgrade.

The `application` builder (esbuild) adds a `browser/` subdirectory to its output by default.
The Go locale handler serving the SPA expects locale directories directly at `public/en/`,
`public/de/`, etc. Without the fix, every user got English regardless of their browser language —
no error, no log, just silently wrong locale.

Fix in `angular.json`:

```json
"outputPath": {
  "base": ".dist/public",
  "browser": ""
}
```

### Step 2 — Ace Editor Crash

Deleting `polyfills.ts` (required by the application builder) removes the `global` polyfill that
`ace-builds` depends on. The YAML editor crashed silently in every Edit, Create, and Preview
dialog. Fix: add one line to `index.html` before any other scripts:

```html
<script>window.global = window;</script>
```

### Step 4 — Node Version Gate

Angular 20 requires Node ≥ 20.19.0. This is a hard requirement — the CLI refuses to run.
Every developer machine, CI runner, and Dockerfile must be updated before attempting Step 4.
(The Dockerfile already used `node:20-alpine` — only the host machines needed upgrading.)

### ngx-charts — Version Must Match Angular Version

`@swimlane/ngx-charts` has a strict peer dependency ladder. The wrong version produces blank
charts with no error:

| Angular | ngx-charts version |
|---|---|
| 17 | `22.0.0` |
| 18–21 | `23.1.0` (with yarn peer override) |

---

## Package Changes Summary

| Package | Before | After |
|---|---|---|
| `@angular/core` (all packages) | 16.2.1 | 21.x |
| `@angular/cdk` / `@angular/material` | **14.2.7** | 21.x |
| `@angular/flex-layout` | 15.0.0-beta.42 | **REMOVED** |
| `@ngbracket/ngx-layout` | — | 21.x |
| `@swimlane/ngx-charts` | 21.1.3 | 23.1.0 |
| `rxjs-compat` | 6.6.7 | **REMOVED** |
| `codelyzer` | 6.0.2 | **REMOVED** |
| TypeScript | 5.1.6 | 5.9.x |
| Node.js minimum | 16.14 | **20.19.0** |
| `zone.js` | 0.13.3 | 0.14.x |
| Build system | Webpack (`browser` builder) | esbuild (`application` builder) |
| ESLint config | `.eslintrc.yaml` (legacy) | `eslint.config.js` (flat config) |
| `src/polyfills.ts` | Present | **Deleted** (esbuild handles it) |
| `HttpClientModule` | In root NgModule | `provideHttpClient()` |

---

## Features Added Post-Upgrade

After the upgrade reached Angular 21, all features from the React+MUI flavor were integrated
into the Angular WebUI. The original Angular codebase had core Kubernetes resources coverage;
these were all new pages:

| Feature | Description |
|---|---|
| **Event Timeline** | Live 5-second feed, time-bucketed grouping, warning highlight |
| **RBAC Viewer** | All cluster role bindings, resolved rules, wildcard detection |
| **Certificate Tracker** | TLS secrets scanned with `crypto/x509`, expiry countdown, status badges |
| **Policy Audit** | Polaris security scoring (0–100) per workload, expandable check details |
| **Registry Manager** | Image pull secrets cross-referenced with pod `imagePullSecrets` |
| **Resource Efficiency** | CPU/memory request vs limit vs actual, trend arrows (VictoriaMetrics) |
| **Cluster Map** | Namespace-scoped topology view, health filter, zoom |
| **Application Projects** | Per-namespace cards with pod health and resource totals |
| **cert-manager** | Certificate, Issuer, ClusterIssuer — auto-detected via CRD presence |
| **MetalLB** | IP Address Pools and L2 Advertisements — auto-detected via CRD presence |
| **Kubescape Security** | Compliance scores and CVE findings — auto-detected |
| **Gateway API** | GatewayClasses, Gateways, HTTPRoutes — auto-detected |
| **Pod Security / Network Policies** | Pod Security Standards and NetworkPolicy visualisation |
| **About page** | Build info, version, links |

The Angular flavor also retains features the React version does not have:

- **Form-based resource creation** (deploy wizard)
- **i18n** (9 locales: de, en, es, fr, ja, ko, zh-Hans, zh-Hant, zh-Hant-HK)

---

## QA Process

- 5 QA rounds before the upgrade was considered stable
- 5-stage regression analysis covering: runtime correctness, visual regressions, memory leaks, feature gaps, performance
- Real-cluster smoke test against a K3s cluster (NUC-02, k8s-native namespace)
- All action paths tested: login, theme toggle, workloads list, pod detail, logs, exec terminal, settings sliders, create YAML, nav pin/unpin, all 14 new feature pages

---

## What Was Not Upgraded

**AI Chat Drawer** — implemented in React+MUI, not yet ported to Angular. The backend API
(`POST /api/v1/ai/chat`) is shared and works. The Angular implementation would follow the same
SSE streaming pattern.

**Cluster Shell** — kubectl WebSocket terminal. React+MUI has a full implementation. Angular has
standard pod exec (`xterm`) but not the cluster-level kubectl shell.

---

## Version

Angular 21 is the current Active LTS release (supported to 2027). The next upgrade cycle
(to v22 or v23) should be considerably simpler — the breaking MDC migration and builder change
are both behind us, and the incremental steps will be smaller.
