# Quenly loyalty

## Frontend stack (overrides §3 of the design-taste-frontend skill)

`.claude/skills/design-taste-frontend` is vendored from Leonxlnx/taste-skill@ce26fc2 (MIT). Its §3 assumes
React/Next + Motion + npm icon packages. This repo has none of those; use the equivalents below instead.

- **Views:** Rails 7.2 ERB partials. No React, Next.js, Node, or `package.json`.
- **CSS:** Tailwind v4 via `tailwindcss-rails` (standalone binary), entry `app/assets/tailwind/application.css`.
  Use the token utilities from its `@theme inline` block (`bg-primary`, `text-ink-2`, `border-line`…),
  not raw hex. Marketing type is Hanken Grotesk, set on `.marketing`. Buttons reuse `l-btn l-btn-primary|l-btn-ghost`.
- **JS:** importmap + Hotwire (Turbo, Stimulus in `app/javascript/controllers`). Motion = CSS transitions or
  a Stimulus controller, never an animation library.
- **Components:** Preline UI markup. Vendor only the plugin you need into `vendor/javascript/` (see
  `preline-collapse.js`), pin it in `config/importmap.rb`, and init it on `turbo:load` (see `app/javascript/marketing.js`).
- **Icons:** the existing `ui_icon` helper (`app/helpers/icons_helper.rb`). Add a glyph there instead of adding a library.
- **Hand-drawn marketing doodles:** `doodle(shape)` in the same helper, drawn by `sketch_controller.js` with Rough.js
  (vendored `vendor/javascript/roughjs.js`, the one drawing library). Add a recipe to that controller for a new doodle.
  Rough.js only draws; motion stays CSS. Product UI keeps `ui_icon`.
- **Copy:** every string goes through `config/locales/vi.yml` and `en.yml`. Vietnamese is the primary language.
- **Scope:** the skill is for marketing pages (`layouts/marketing`: landing, merchant signup). It does not
  cover the merchant/admin dashboards or the customer PWA.

## Design skills: which one when

Two design skills are installed. The stack rules above apply to both.

- **design-taste-frontend** (vendored above): building or redesigning a marketing page. Its pre-flight
  check is the gate before shipping landing work.
- **Impeccable** (plugin `impeccable@impeccable`, enabled in `.claude/settings.json`): targeted passes on an
  existing UI (`/impeccable polish | critique | audit | typeset | layout | distill …`), including the
  merchant/admin dashboards that taste skill does not cover. Where the two disagree on a marketing page,
  taste skill wins. Ignore Impeccable's own stack defaults the same way as taste skill §3.
- Impeccable's automatic hooks are off (`IMPECCABLE_HOOK_DISABLED=1` plus `hook.enabled: false` in
  `.impeccable/config.json`), so run its detector on demand. That config also registers `.html.erb`,
  without which the detector skips every view in this repo.
