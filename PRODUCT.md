# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

- **Shop owners** of small Vietnamese businesses: cafés, milk-tea and restaurants (F&B), fashion and
  cosmetics retail, spa, salon and gym services. They evaluate and buy the product, often on a phone,
  often after asking someone on Zalo first.
- **Their customers** (end members), who use the shop's app to collect points or stamps and redeem rewards.
- **Cashiers / staff**, who scan the member code at the counter.

## Product Purpose

Quenly lets a small shop run its own loyalty program: points, tiers, stamp cards, missions, a lucky wheel,
referrals, vouchers and push campaigns, so a one-time visitor becomes a regular. Success is a shop that
signs up, configures its program itself, and gets its customers coming back.

## Positioning

**Every shop gets a loyalty app in its own brand**: its logo, colors and its own subdomain (optionally a
custom domain), with no Quenly branding in front of the customer. Customers do not install anything; it
runs as a PWA in the browser. Self-serve setup and a low monthly price (the landing states "under
7,000đ a day") support this but are secondary.

## Operating Context

- Counter flow: the member opens their personal QR in the shop's app, staff scans it on the merchant
  scanner (or the member scans a counter QR), points or stamps land on the bill.
- Members sign in with email + OTP. Shops sign up at `/merchant/signup`; plans are billed monthly via PayOS
  after a free trial (`Workspace::TRIAL_DAYS`, currently 14) and a grace period (`Workspace::GRACE_DAYS`).
- Shop owners are sold to through Zalo and Messenger; links pasted there must preview well.

## Capabilities and Constraints

- Three apps in one Rails codebase: customer PWA, merchant dashboard, super admin. Feature list:
  `docs/TINH-NANG.md`.
- Plan names, prices and features come from `Plan` records; marketing copy must not hardcode them.
- Vietnamese is the primary language; every string is translated (vi/en).
- The product is not publicly launched yet; search indexing is intentionally blocked.
- Undecided: a sales contact channel. A Zalo link is wanted but no number exists yet (`SALES_ZALO_URL`).

## Brand Commitments

- Name: **Quenly**.
- Logo (since 2026-09-30): a brown-to-amber "Q" holding a four-point star, with the "Quenly" wordmark.
  Sources `app/assets/images/quenly-{mark,lockup}-clean.png`; web sizes `quenly-mark.png`, `quenly-lockup.png`;
  platform icon `public/icon.png`, link preview `public/og.png`.
- The rest of the marketing identity may be replaced.

## Evidence on Hand

- Real product screenshots from the demo shop "Mộc Cà Phê": `app/assets/images/landing/`.
- **No real customers, testimonials, logos, or usage metrics yet.** Never fabricate them; prove the
  product by showing it working instead.

## Product Principles

1. The shop's brand comes first; Quenly stays in the background.
2. Show the mechanism working rather than claiming benefits.
3. A small-shop owner must understand it and start without help, and can ask a person when unsure.
4. Never state a number, customer or claim the product cannot back.
