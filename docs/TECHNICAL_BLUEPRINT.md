# Krezus — Technical Blueprint

> Stock Market Box for Everyone

---

## Table of Contents

1. [System Architecture](#1-system-architecture)
2. [Data Model](#2-data-model)
3. [User Flows](#3-user-flows)
4. [Frontend Structure](#4-frontend-structure)
5. [Backend API Design](#5-backend-api-design)
6. [Third-Party Integrations](#6-third-party-integrations)
7. [Compliance & Security](#7-compliance--security)
8. [Delivery Plan](#8-delivery-plan)

---

## 1. System Architecture

### 1.1 Logical Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                          CLIENTS                                │
│                                                                 │
│  ┌──────────────────────┐    ┌───────────────────────────────┐  │
│  │   Public Website     │    │   Investor Dashboard (Auth)   │  │
│  │   (Next.js SSR/SSG)  │    │   (Next.js CSR + Auth Guard)  │  │
│  │                      │    │                               │  │
│  │  - Home              │    │  - Portfolio                  │  │
│  │  - Manifesto         │    │  - Orders                    │  │
│  │  - How it works      │    │  - Card activation           │  │
│  │  - Shop (3-step)     │    │  - Account settings          │  │
│  │  - Login / Signup    │    │                               │  │
│  └──────────┬───────────┘    └──────────────┬────────────────┘  │
│             │                               │                   │
└─────────────┼───────────────────────────────┼───────────────────┘
              │           HTTPS               │
              ▼                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                     API GATEWAY / BACKEND                       │
│                     (Node.js + Express/Fastify)                 │
│                                                                 │
│  ┌────────────┐ ┌───────────┐ ┌───────────┐ ┌───────────────┐  │
│  │ Auth       │ │ Shop /    │ │ Gift Card │ │ Brokerage     │  │
│  │ Module     │ │ Payments  │ │ Module    │ │ Module        │  │
│  │            │ │           │ │           │ │               │  │
│  │ - JWT      │ │ - Stripe  │ │ - Create  │ │ - Alpaca API  │  │
│  │ - OAuth    │ │   Checkout│ │ - Activate│ │ - Orders      │  │
│  │ - Sessions │ │ - Webhook │ │ - Deliver │ │ - Portfolio   │  │
│  └─────┬──────┘ └─────┬─────┘ └─────┬─────┘ └──────┬────────┘  │
│        │              │             │               │           │
│  ┌─────▼──────────────▼─────────────▼───────────────▼────────┐  │
│  │                    PostgreSQL Database                     │  │
│  │  (Users, GiftCards, Orders, Payments, Portfolios, Logs)   │  │
│  └───────────────────────────────────────────────────────────┘  │
│        │              │                             │           │
└────────┼──────────────┼─────────────────────────────┼───────────┘
         │              │                             │
         ▼              ▼                             ▼
┌──────────────┐ ┌─────────────┐  ┌──────────────────────────────┐
│ Google /     │ │   Stripe    │  │      Alpaca Markets          │
│ Facebook     │ │             │  │      (Broker-as-a-Service)   │
│ OAuth        │ │ - Checkout  │  │                              │
│              │ │ - Webhooks  │  │  - Account creation          │
│              │ │ - Refunds   │  │  - ACH funding               │
│              │ │             │  │  - Fractional order exec     │
│              │ │             │  │  - Portfolio / positions     │
└──────────────┘ └─────────────┘  └──────────────────────────────┘
```

### 1.2 Data Flow Summaries

**Gift Purchase Flow:**
```
Browser → Next.js (Shop) → POST /api/orders → Stripe Checkout Session
  → Stripe hosted page → Stripe Webhook (payment_intent.succeeded)
  → Backend confirms order → Creates GiftCard record → Sends delivery email
```

**Card Activation Flow:**
```
Dashboard → POST /api/gift-cards/:code/activate → Validate code
  → Create/link Alpaca broker account → Fund account via Alpaca ACH
  → Mark card as ACTIVATED → Redirect to stock selection
```

**Stock Execution Flow:**
```
Dashboard → POST /api/orders/stock → Validate balance in Alpaca
  → Submit fractional order to Alpaca → Poll/webhook for fill
  → Record transaction → Update portfolio view
```

**Portfolio Display Flow:**
```
Dashboard → GET /api/portfolio → Fetch positions from Alpaca API
  → Merge with local transaction history → Return aggregated view
```

### 1.3 Recommended Stack

| Layer | Technology | Justification |
|-------|-----------|---------------|
| Frontend | **Next.js 14 (App Router)** | SSR for SEO on public pages, CSR for dashboard, single codebase |
| Styling | **Tailwind CSS** | Rapid UI, consistent design tokens, matches spec color system |
| State | **Zustand** | Lightweight, no boilerplate, sufficient for this scope |
| Backend | **Node.js + Fastify** | High performance, TypeScript native, schema validation built-in |
| ORM | **Prisma** | Type-safe DB access, migrations, works well with PostgreSQL |
| Database | **PostgreSQL 16** | Relational integrity for financial data, JSONB for flexible fields |
| Cache | **Redis** | Session store, rate limiting, idempotency keys |
| Auth | **NextAuth.js (Auth.js)** | Built-in Google/Facebook OAuth, JWT + session support |
| Hosting | **Vercel (FE) + Railway/Render (BE)** | Simple deployment, auto-scaling, cost-effective for MVP |
| Email | **Resend or SendGrid** | Transactional emails for gift card delivery |

---

## 2. Data Model

### 2.1 Entity-Relationship Overview

```
User 1──n GiftCard (as buyer)
User 1──n GiftCard (as recipient)
User 1──1 BrokerAccount
User 1──n Order
User 1──n Transaction

GiftCard 1──1 Payment
GiftCard 1──n Order (stock purchases from this card's funds)

Order 1──1 Transaction
Order n──1 Stock

BrokerAccount 1──n Transaction
```

### 2.2 Entity Definitions

#### User

| Field | Type | Notes |
|-------|------|-------|
| id | UUID (PK) | Internal identifier |
| email | VARCHAR(255) | Unique, indexed |
| password_hash | VARCHAR(255) | Nullable (OAuth users) |
| first_name | VARCHAR(100) | PII — encrypted at rest |
| last_name | VARCHAR(100) | PII — encrypted at rest |
| phone | VARCHAR(20) | PII — nullable |
| date_of_birth | DATE | Required for brokerage KYC |
| oauth_provider | ENUM(google, facebook, email) | |
| oauth_provider_id | VARCHAR(255) | External OAuth ID |
| kyc_status | ENUM(none, pending, approved, rejected) | Alpaca KYC status mirror |
| created_at | TIMESTAMPTZ | |
| updated_at | TIMESTAMPTZ | |

**Ownership:** Krezus-owned. KYC status mirrors Alpaca but is stored locally for display.
**Sensitive data:** first_name, last_name, email, phone, date_of_birth — encrypted at rest, access-logged.

#### BrokerAccount

| Field | Type | Notes |
|-------|------|-------|
| id | UUID (PK) | |
| user_id | UUID (FK → User) | Unique — one account per user |
| alpaca_account_id | VARCHAR(255) | Alpaca's external account ID |
| alpaca_account_status | ENUM(pending, active, suspended, closed) | |
| funding_status | ENUM(none, pending, complete, failed) | |
| created_at | TIMESTAMPTZ | |
| updated_at | TIMESTAMPTZ | |

**Ownership:** Mapping entity. The actual brokerage account lives in Alpaca. Krezus stores only the reference and sync status.

#### GiftCard

| Field | Type | Notes |
|-------|------|-------|
| id | UUID (PK) | |
| code | VARCHAR(16) | Unique activation code, indexed |
| buyer_email | VARCHAR(255) | Who purchased it |
| buyer_name | VARCHAR(200) | Display name of buyer |
| recipient_email | VARCHAR(255) | Nullable — physical cards may not have this |
| recipient_name | VARCHAR(200) | |
| recipient_user_id | UUID (FK → User) | Set upon activation |
| amount_cents | INTEGER | Value in cents (EUR) |
| currency | VARCHAR(3) | Default 'EUR' |
| status | ENUM(pending_payment, paid, delivered, activated, expired) | |
| delivery_type | ENUM(digital, physical) | |
| personal_message | TEXT | Optional message from buyer |
| theme | VARCHAR(50) | Card visual theme |
| payment_id | UUID (FK → Payment) | |
| activated_at | TIMESTAMPTZ | Null until activated |
| expires_at | TIMESTAMPTZ | Configurable expiry |
| created_at | TIMESTAMPTZ | |

**Ownership:** Fully Krezus-owned.
**Sensitive data:** buyer/recipient emails — PII.

#### Payment

| Field | Type | Notes |
|-------|------|-------|
| id | UUID (PK) | |
| stripe_payment_intent_id | VARCHAR(255) | Unique, idempotency anchor |
| stripe_checkout_session_id | VARCHAR(255) | |
| amount_cents | INTEGER | |
| currency | VARCHAR(3) | |
| status | ENUM(pending, succeeded, failed, refunded) | |
| gift_card_id | UUID (FK → GiftCard) | |
| metadata | JSONB | Stripe metadata mirror |
| created_at | TIMESTAMPTZ | |
| updated_at | TIMESTAMPTZ | |

**Ownership:** Krezus stores payment records. Funds are held by Stripe, then transferred. Krezus never holds user funds directly.

#### Stock

| Field | Type | Notes |
|-------|------|-------|
| id | UUID (PK) | |
| symbol | VARCHAR(10) | e.g. AAPL, VOO |
| name | VARCHAR(255) | |
| type | ENUM(stock, etf) | |
| description | TEXT | |
| logo_url | VARCHAR(500) | |
| is_available | BOOLEAN | Whether offered on Krezus |
| risk_level | ENUM(low, medium, high) | Display-only |
| created_at | TIMESTAMPTZ | |

**Ownership:** Krezus curated catalog. Actual trading data comes from Alpaca.

#### Order

| Field | Type | Notes |
|-------|------|-------|
| id | UUID (PK) | |
| user_id | UUID (FK → User) | |
| gift_card_id | UUID (FK → GiftCard) | Which card funds this order |
| stock_id | UUID (FK → Stock) | |
| alpaca_order_id | VARCHAR(255) | Alpaca's order reference |
| side | ENUM(buy) | V1: buy only |
| type | ENUM(market) | V1: market orders only |
| notional_amount_cents | INTEGER | Dollar/euro amount to invest |
| qty_shares | DECIMAL(18,8) | Fractional shares filled |
| status | ENUM(pending, submitted, filled, partially_filled, cancelled, rejected) | |
| filled_at | TIMESTAMPTZ | |
| created_at | TIMESTAMPTZ | |
| updated_at | TIMESTAMPTZ | |

**Ownership:** Mixed. Created by Krezus, execution details from Alpaca.

#### Transaction

| Field | Type | Notes |
|-------|------|-------|
| id | UUID (PK) | |
| user_id | UUID (FK → User) | |
| broker_account_id | UUID (FK → BrokerAccount) | |
| order_id | UUID (FK → Order) | Nullable (funding txns have no order) |
| type | ENUM(funding, stock_buy, stock_sell, dividend, fee) | |
| amount_cents | INTEGER | |
| currency | VARCHAR(3) | |
| description | TEXT | |
| created_at | TIMESTAMPTZ | |

**Ownership:** Krezus audit log of all financial movements.

#### Portfolio (Materialized View / Computed)

Portfolio is **not stored as a table**. It is computed in real-time by:
1. Fetching current positions from Alpaca API
2. Joining with local Stock metadata
3. Enriching with local Transaction history for cost basis

The API returns a computed object:

```json
{
  "total_value_cents": 15000,
  "total_gain_cents": 320,
  "total_gain_pct": 2.18,
  "positions": [
    {
      "symbol": "AAPL",
      "name": "Apple Inc.",
      "qty": "0.05321",
      "market_value_cents": 8500,
      "cost_basis_cents": 8200,
      "gain_cents": 300,
      "gain_pct": 3.66
    }
  ]
}
```

### 2.3 Indexing Strategy

| Index | Table | Purpose |
|-------|-------|---------|
| `idx_giftcard_code` | GiftCard(code) | Activation lookup |
| `idx_giftcard_status` | GiftCard(status) | Filtering |
| `idx_payment_stripe_pi` | Payment(stripe_payment_intent_id) | Webhook dedup |
| `idx_order_user` | Order(user_id) | User order history |
| `idx_order_alpaca` | Order(alpaca_order_id) | Alpaca sync |
| `idx_user_email` | User(email) | Login lookup |

---

## 3. User Flows

### 3.1 Anonymous User → Gift Purchase

```
1. User lands on Home page
2. User navigates to Shop (/shop)
3. STEP 1 — Select amount:
   - Predefined amounts (€25, €50, €100, €150, €200) or custom
   - Select delivery type (digital / physical)
   → State: { amount, deliveryType }

4. STEP 2 — Personalize:
   - Enter buyer name, buyer email
   - Enter recipient name, recipient email (optional for physical)
   - Choose card theme
   - Add personal message (optional)
   → State: { ...prev, buyer, recipient, theme, message }

5. STEP 3 — Payment:
   - Review summary
   - Click "Pay with Stripe"
   → POST /api/orders/gift
   → Backend creates GiftCard (status: pending_payment) + Payment record
   → Backend creates Stripe Checkout Session
   → Redirect to Stripe hosted checkout

6. On Stripe page:
   - User enters card details
   - Stripe processes payment

7. Stripe redirects to /shop/confirmation?session_id=xxx
   - Frontend polls or waits for backend confirmation
   - Display success with order details

8. (Async) Stripe fires webhook → payment_intent.succeeded
   - Backend updates Payment status → succeeded
   - Backend updates GiftCard status → paid
   - Backend triggers delivery (email or physical queue)
```

**Error States:**
- Payment declined → Stripe shows error on checkout page; user can retry
- Webhook delivery failure → Stripe retries (up to 72h); backend is idempotent on `stripe_payment_intent_id`
- Duplicate webhook → Ignored via idempotency check on payment_intent_id
- Invalid email → Client-side validation + server-side validation; 422 returned

### 3.2 Stripe Checkout → Payment Confirmation

```
1. POST /api/orders/gift received
2. Server validates input (amount in allowed range, emails valid)
3. Server creates:
   - GiftCard record (status: pending_payment)
   - Payment record (status: pending)
4. Server calls stripe.checkout.sessions.create({
     mode: 'payment',
     line_items: [{ price_data: { amount, currency }, quantity: 1 }],
     metadata: { gift_card_id, payment_id },
     success_url: '/shop/confirmation?session_id={CHECKOUT_SESSION_ID}',
     cancel_url: '/shop?cancelled=true'
   })
5. Return { checkout_url } to frontend
6. Frontend redirects to Stripe

7. Webhook handler (POST /api/webhooks/stripe):
   - Verify signature with stripe.webhooks.constructEvent()
   - Extract payment_intent_id
   - Check idempotency: if Payment already succeeded → return 200
   - Update Payment → succeeded
   - Update GiftCard → paid
   - Queue delivery job
   - Return 200
```

### 3.3 Gift Card Delivery

```
Digital:
1. GiftCard status = paid
2. Background job sends email to recipient_email
   - Contains: activation code, personal message, buyer name, card visual
   - CTA button: "Activate your gift" → links to /activate?code=XXX
3. Also sends confirmation email to buyer_email
4. GiftCard status → delivered

Physical:
1. GiftCard status = paid
2. Order queued in admin fulfillment dashboard (or third-party print service)
3. Physical card contains printed activation code
4. Manual status update → delivered (or automated via shipping webhook)
```

**Edge Cases:**
- Email bounce → Log delivery failure; allow buyer to re-trigger via support
- Code already activated → Show clear error message on activation page

### 3.4 User Signup / Login

```
Email signup:
1. User visits /signup
2. Enters email, password, first name, last name
3. POST /api/auth/register
4. Server creates User (kyc_status: none)
5. Email verification link sent
6. User clicks link → email verified
7. Redirect to dashboard

OAuth (Google / Facebook):
1. User clicks "Continue with Google"
2. Redirect to Google OAuth consent
3. Google callback to /api/auth/callback/google
4. Server checks if User exists with this OAuth ID
   - Yes → login, issue JWT
   - No → create User from OAuth profile, issue JWT
5. Redirect to dashboard

Login:
1. POST /api/auth/login { email, password }
2. Verify credentials
3. Issue JWT (access token: 15min, refresh token: 7d)
4. Return tokens
```

**Edge Cases:**
- OAuth user tries email login → "This account uses Google Sign-In"
- Duplicate email across providers → Merge prompt or block with message

### 3.5 Card Activation

```
1. Authenticated user navigates to /dashboard/activate
   - Or clicks link from email: /activate?code=XXX → redirect to login if needed
2. Enters activation code (or pre-filled from URL)
3. POST /api/gift-cards/:code/activate
4. Server validates:
   - Code exists
   - Status = paid or delivered (not already activated, not expired)
   - Not already linked to another user
5. Server links GiftCard.recipient_user_id = current user
6. If user has no BrokerAccount:
   - Trigger Alpaca account creation (POST /v1/accounts)
   - Store alpaca_account_id in BrokerAccount
   - KYC may be required → status: pending
7. If KYC approved:
   - Initiate funding: transfer gift card amount to Alpaca account
   - BrokerAccount.funding_status → pending
8. GiftCard.status → activated
9. Redirect user to stock selection / dashboard

Idempotency: Activating the same code twice by the same user returns success
(already activated). Different user → 409 Conflict.
```

**Edge Cases:**
- KYC rejected → Show message, offer support contact
- Funding fails → Retry mechanism; show "pending" state on dashboard
- Expired card → 410 Gone with explanation

### 3.6 Money Transfer to Alpaca

```
1. Triggered after card activation (automatic)
2. Backend calls Alpaca POST /v1/accounts/{id}/transfers
   - transfer_type: "ach"
   - amount: gift card value
   - direction: "INCOMING"
3. Alpaca processes transfer (takes 1-3 business days for ACH)
4. Backend polls or receives webhook for transfer status
5. On completion:
   - BrokerAccount.funding_status → complete
   - User notified: "Your funds are ready to invest"
6. Transaction record created (type: funding)
```

**Edge Cases:**
- ACH failure → Notify user, retry once, then escalate to support
- Partial funding → Not applicable (single amount transfer)

### 3.7 Stock Purchase Execution

```
1. User browses available stocks on dashboard
2. Selects stock (e.g., AAPL)
3. Enters amount to invest (in EUR/USD)
4. Frontend shows preview: estimated shares, disclaimers
5. User confirms → POST /api/orders/stock
6. Server validates:
   - User has BrokerAccount with active status
   - Sufficient buying power (check Alpaca balance)
   - Stock is available on Krezus catalog
7. Server submits to Alpaca: POST /v1/trading/accounts/{id}/orders
   - symbol, notional (dollar amount), side: buy, type: market, time_in_force: day
8. Alpaca returns order ID
9. Server creates Order record (status: submitted)
10. Poll Alpaca for fill status (or webhook)
11. On fill:
    - Update Order: status → filled, qty_shares, filled_at
    - Create Transaction record
    - Return updated portfolio
```

**Edge Cases:**
- Market closed → Inform user, queue for next open or reject
- Insufficient funds → 400 with clear message
- Order rejected by Alpaca → Surface Alpaca error, log details
- Partial fill → Update with partial qty; rare for market orders on liquid stocks

### 3.8 Portfolio Visualization

```
1. User navigates to /dashboard
2. Frontend calls GET /api/portfolio
3. Backend:
   a. Fetch positions from Alpaca: GET /v1/trading/accounts/{id}/positions
   b. Fetch account info: GET /v1/trading/accounts/{id}/account
   c. Join with local Stock table for names/logos
   d. Calculate cost basis from local Transaction records
   e. Compute gains (unrealized)
4. Return portfolio object
5. Frontend renders:
   - Total value card
   - Gain/loss indicator
   - Position list with sparkline charts (via market data API)
   - Transaction history
```

---

## 4. Frontend Structure

### 4.1 Route Map

| Route | Auth | Page | Rendering |
|-------|------|------|-----------|
| `/` | No | Home | SSG |
| `/manifesto` | No | Manifesto | SSG |
| `/how-it-works` | No | How It Works | SSG |
| `/shop` | No | Shop — Step 1 (Amount) | CSR |
| `/shop/personalize` | No | Shop — Step 2 (Personalize) | CSR |
| `/shop/checkout` | No | Shop — Step 3 (Review + Pay) | CSR |
| `/shop/confirmation` | No | Order Confirmation | CSR |
| `/login` | No | Login | CSR |
| `/signup` | No | Signup | CSR |
| `/dashboard` | Yes | Portfolio Overview | CSR |
| `/dashboard/activate` | Yes | Card Activation | CSR |
| `/dashboard/invest` | Yes | Stock Selection + Buy | CSR |
| `/dashboard/orders` | Yes | Order History | CSR |
| `/dashboard/settings` | Yes | Account Settings | CSR |

### 4.2 Shared / Reusable Components

```
components/
├── layout/
│   ├── Navbar.tsx              — Logo, nav links, CTA button, auth state
│   ├── Footer.tsx              — Links, legal, socials
│   ├── PageWrapper.tsx         — Max-width container, padding
│   └── AuthGuard.tsx           — Redirect to /login if unauthenticated
├── ui/
│   ├── Button.tsx              — Primary (green #00C853), Secondary, Ghost variants
│   ├── Input.tsx               — Text, email, password with validation states
│   ├── Card.tsx                — Elevated card with optional image header
│   ├── Badge.tsx               — Status badges (paid, activated, pending)
│   ├── Modal.tsx               — Confirmation dialogs
│   ├── Stepper.tsx             — 3-step progress indicator for shop funnel
│   ├── AmountSelector.tsx      — Predefined buttons + custom input
│   ├── StockCard.tsx           — Logo, name, price, mini-chart
│   ├── PortfolioSummary.tsx    — Total value, gain/loss display
│   └── RiskDisclaimer.tsx      — Standardized risk warning component
├── forms/
│   ├── GiftPersonalizationForm.tsx
│   ├── LoginForm.tsx
│   ├── SignupForm.tsx
│   └── ActivationForm.tsx
└── icons/
    └── (SVG icon components)
```

### 4.3 Design Tokens (from Spec)

```typescript
// tailwind.config.ts (extend)
colors: {
  krezus: {
    green:    '#00C853',   // Primary CTA
    dark:     '#1A1A2E',   // Dark backgrounds
    navy:     '#16213E',   // Secondary dark
    light:    '#F5F5F5',   // Light backgrounds
    white:    '#FFFFFF',
    grey:     '#9E9E9E',   // Secondary text
    red:      '#FF1744',   // Error / loss
    amber:    '#FFD600',   // Warning
  }
}

fontFamily: {
  heading: ['Inter', 'sans-serif'],
  body:    ['Inter', 'sans-serif'],
}
```

### 4.4 Page Details

#### Home (`/`)

**Components:** Hero, ValueProposition (3-col), HowItWorksPreview (3-step), Testimonials, CTA banner, Footer
**State:** None
**API Calls:** None (static)

#### Manifesto (`/manifesto`)

**Components:** PageHeader, ContentSection (rich text), CTA
**State:** None
**API Calls:** None (static)

#### How It Works (`/how-it-works`)

**Components:** PageHeader, StepCards (buy → activate → invest), FAQ accordion
**State:** None
**API Calls:** None (static)

#### Shop — Step 1 (`/shop`)

**Components:** Stepper(1/3), AmountSelector, DeliveryTypeToggle, ContinueButton
**State:** Zustand `useShopStore` — `{ amount, deliveryType }`
**API Calls:** None

#### Shop — Step 2 (`/shop/personalize`)

**Components:** Stepper(2/3), GiftPersonalizationForm, ThemeSelector, BackButton, ContinueButton
**State:** Zustand `useShopStore` — `{ ...prev, buyerName, buyerEmail, recipientName, recipientEmail, theme, message }`
**API Calls:** None

#### Shop — Step 3 (`/shop/checkout`)

**Components:** Stepper(3/3), OrderSummary, StripePayButton, RiskDisclaimer
**State:** Reads from `useShopStore`
**API Calls:** `POST /api/orders/gift` → receives Stripe checkout URL → redirect

#### Confirmation (`/shop/confirmation`)

**Components:** SuccessIcon, OrderDetails, NextStepsCTA
**State:** Query param `session_id`
**API Calls:** `GET /api/orders/gift/confirm?session_id=xxx`

#### Login (`/login`)

**Components:** LoginForm, OAuthButtons (Google, Facebook), SignupLink
**State:** Local form state
**API Calls:** `POST /api/auth/login` or OAuth redirect

#### Signup (`/signup`)

**Components:** SignupForm, OAuthButtons, LoginLink
**State:** Local form state
**API Calls:** `POST /api/auth/register`

#### Dashboard — Portfolio (`/dashboard`)

**Components:** PortfolioSummary, PositionList (StockCard[]), TransactionHistory, ActivateCTA (if no positions)
**State:** `usePortfolioStore` — fetched data
**API Calls:** `GET /api/portfolio`, `GET /api/transactions`

#### Dashboard — Activate (`/dashboard/activate`)

**Components:** ActivationForm (code input), StatusDisplay
**State:** Local
**API Calls:** `POST /api/gift-cards/:code/activate`

#### Dashboard — Invest (`/dashboard/invest`)

**Components:** StockCatalog (grid of StockCard), SearchFilter, BuyModal (amount input, preview, confirm), RiskDisclaimer
**State:** `useInvestStore` — selected stock, amount
**API Calls:** `GET /api/stocks`, `GET /api/stocks/:symbol/quote`, `POST /api/orders/stock`

#### Dashboard — Orders (`/dashboard/orders`)

**Components:** OrderList (table/cards with status badges), OrderDetail modal
**State:** Fetched
**API Calls:** `GET /api/orders`

#### Dashboard — Settings (`/dashboard/settings`)

**Components:** ProfileForm, KYCStatusDisplay, LinkedAccounts
**State:** Fetched user data
**API Calls:** `GET /api/user/profile`, `PUT /api/user/profile`

---

## 5. Backend API Design

### 5.1 General Conventions

- **Base URL:** `https://api.krezus.com/v1`
- **Format:** JSON
- **Auth:** Bearer JWT in `Authorization` header (except public endpoints)
- **Errors:** Consistent error envelope:

```json
{
  "error": {
    "code": "GIFT_CARD_EXPIRED",
    "message": "This gift card has expired and can no longer be activated.",
    "status": 410
  }
}
```

### 5.2 Auth Endpoints

#### `POST /v1/auth/register`
**Auth:** Public
```json
// Request
{
  "email": "user@example.com",
  "password": "SecureP@ss1",
  "first_name": "Jean",
  "last_name": "Dupont"
}
// Response 201
{
  "user": { "id": "uuid", "email": "user@example.com" },
  "access_token": "eyJ...",
  "refresh_token": "eyJ..."
}
```

#### `POST /v1/auth/login`
**Auth:** Public
```json
// Request
{ "email": "user@example.com", "password": "SecureP@ss1" }
// Response 200
{
  "user": { "id": "uuid", "email": "user@example.com", "kyc_status": "approved" },
  "access_token": "eyJ...",
  "refresh_token": "eyJ..."
}
```

#### `POST /v1/auth/refresh`
**Auth:** Public (with refresh token)
```json
// Request
{ "refresh_token": "eyJ..." }
// Response 200
{ "access_token": "eyJ...", "refresh_token": "eyJ..." }
```

#### `GET /v1/auth/oauth/:provider`
**Auth:** Public
Initiates OAuth flow. Provider = `google` | `facebook`. Redirects to provider.

#### `GET /v1/auth/oauth/:provider/callback`
**Auth:** Public
Handles OAuth callback. Creates/finds user, returns JWT via redirect with token in URL fragment.

### 5.3 Products / Stocks

#### `GET /v1/stocks`
**Auth:** Authenticated
```json
// Response 200
{
  "stocks": [
    {
      "id": "uuid",
      "symbol": "AAPL",
      "name": "Apple Inc.",
      "type": "stock",
      "logo_url": "https://...",
      "risk_level": "medium"
    }
  ]
}
```

#### `GET /v1/stocks/:symbol/quote`
**Auth:** Authenticated
```json
// Response 200
{
  "symbol": "AAPL",
  "price": 18945,
  "currency": "USD",
  "change_pct": 1.23,
  "updated_at": "2025-01-15T14:30:00Z"
}
```
Data sourced from Alpaca Market Data API, cached for 15 seconds in Redis.

### 5.4 Gift Card Endpoints

#### `POST /v1/orders/gift`
**Auth:** Public
```json
// Request
{
  "amount_cents": 5000,
  "currency": "EUR",
  "delivery_type": "digital",
  "buyer_name": "Marie Curie",
  "buyer_email": "marie@example.com",
  "recipient_name": "Pierre Curie",
  "recipient_email": "pierre@example.com",
  "theme": "birthday",
  "message": "Happy birthday! Start investing 🎉"
}
// Response 201
{
  "gift_card_id": "uuid",
  "checkout_url": "https://checkout.stripe.com/c/pay/cs_xxx"
}
```

**Idempotency:** Client sends `Idempotency-Key` header. Server stores key in Redis (TTL 24h). Duplicate requests return the original response.

#### `GET /v1/orders/gift/confirm`
**Auth:** Public
```json
// Query: ?session_id=cs_xxx
// Response 200
{
  "gift_card_id": "uuid",
  "status": "paid",
  "amount_cents": 5000,
  "recipient_name": "Pierre Curie",
  "delivery_type": "digital"
}
```

#### `POST /v1/gift-cards/:code/activate`
**Auth:** Authenticated
```json
// Response 200
{
  "gift_card_id": "uuid",
  "amount_cents": 5000,
  "status": "activated",
  "broker_account_status": "active",
  "funding_status": "pending"
}
```

**Idempotency:** Same user activating same code = 200 (already activated). Different user = 409.

### 5.5 Order / Trading Endpoints

#### `POST /v1/orders/stock`
**Auth:** Authenticated
```json
// Request
{
  "symbol": "AAPL",
  "amount_cents": 2500,
  "idempotency_key": "uuid-client-generated"
}
// Response 201
{
  "order_id": "uuid",
  "alpaca_order_id": "alpaca-uuid",
  "status": "submitted",
  "symbol": "AAPL",
  "notional_amount_cents": 2500
}
```

#### `GET /v1/orders`
**Auth:** Authenticated
```json
// Response 200
{
  "orders": [
    {
      "id": "uuid",
      "symbol": "AAPL",
      "status": "filled",
      "notional_amount_cents": 2500,
      "qty_shares": "0.01321",
      "filled_at": "2025-01-15T15:00:00Z"
    }
  ]
}
```

### 5.6 Portfolio

#### `GET /v1/portfolio`
**Auth:** Authenticated
```json
// Response 200
{
  "total_value_cents": 15000,
  "cash_balance_cents": 2500,
  "total_gain_cents": 320,
  "total_gain_pct": 2.18,
  "positions": [
    {
      "symbol": "AAPL",
      "name": "Apple Inc.",
      "logo_url": "https://...",
      "qty": "0.05321",
      "market_value_cents": 8500,
      "cost_basis_cents": 8200,
      "gain_cents": 300,
      "gain_pct": 3.66
    }
  ]
}
```

### 5.7 Transactions

#### `GET /v1/transactions`
**Auth:** Authenticated
```json
// Query: ?limit=20&offset=0
// Response 200
{
  "transactions": [
    {
      "id": "uuid",
      "type": "stock_buy",
      "amount_cents": 2500,
      "description": "Bought 0.013 AAPL",
      "created_at": "2025-01-15T15:00:00Z"
    }
  ],
  "total": 5
}
```

### 5.8 User Profile

#### `GET /v1/user/profile`
**Auth:** Authenticated

#### `PUT /v1/user/profile`
**Auth:** Authenticated
Allows updating non-sensitive fields (name, phone). Sensitive changes (email) require re-authentication.

### 5.9 Webhooks

#### `POST /v1/webhooks/stripe`
**Auth:** Stripe signature verification
Handles: `checkout.session.completed`, `payment_intent.succeeded`, `payment_intent.payment_failed`, `charge.refunded`

#### `POST /v1/webhooks/alpaca`
**Auth:** Alpaca webhook signature
Handles: `account.updated`, `transfer.updated`, `order.updated`

---

## 6. Third-Party Integrations

### 6.1 Stripe Checkout

**Integration Type:** Stripe Checkout (hosted page), not Stripe Elements.

**Flow:**
1. Backend creates a Checkout Session via `stripe.checkout.sessions.create()`
2. Frontend redirects to the Stripe-hosted page
3. On completion, Stripe redirects to success/cancel URL
4. Stripe sends webhook for async confirmation

**Webhook Setup:**
- Endpoint: `POST /v1/webhooks/stripe`
- Events: `checkout.session.completed`, `payment_intent.succeeded`, `payment_intent.payment_failed`
- Signature verification using `stripe.webhooks.constructEvent(body, sig, secret)`
- All webhook handlers are idempotent (check Payment status before updating)

**Security:**
- Webhook secret stored in environment variable
- Raw body parsing required for signature verification
- All amounts validated server-side (ignore client-sent amounts)

**Failure Handling:**
- Webhook delivery failure → Stripe retries with exponential backoff
- Server returns 200 immediately after processing to avoid timeout
- Unprocessable events logged and acknowledged (return 200 to prevent retries)

### 6.2 Alpaca Markets (Broker API)

**Integration Type:** Alpaca Broker API (not Trading API) — used for managing customer accounts.

**Account Creation:**
```
POST https://broker-api.alpaca.markets/v1/accounts
{
  "contact": { "email_address", "phone_number", "street_address", "city", "state", "postal_code" },
  "identity": { "given_name", "family_name", "date_of_birth", "tax_id_type", "country_of_tax_residence" },
  "disclosures": { ... },
  "agreements": [{ "agreement": "customer_agreement", "signed_at": "...", "ip_address": "..." }]
}
```
- KYC is handled by Alpaca (automated CIP checks)
- Account status returned: SUBMITTED → APPROVED or REJECTED
- Krezus polls or uses webhooks for status updates

**Funding:**
```
POST https://broker-api.alpaca.markets/v1/accounts/{account_id}/transfers
{
  "transfer_type": "ach",
  "relationship_id": "...",
  "amount": "50.00",
  "direction": "INCOMING"
}
```
- For MVP: Krezus uses an omnibus funding approach or Alpaca's built-in funding mechanism
- ACH transfers take 1-3 business days
- Krezus creates a Journal entry from its master account to the user's account for instant funding (if using omnibus model)

**Order Execution:**
```
POST https://broker-api.alpaca.markets/v1/trading/accounts/{account_id}/orders
{
  "symbol": "AAPL",
  "notional": "25.00",
  "side": "buy",
  "type": "market",
  "time_in_force": "day"
}
```
- Fractional shares supported via `notional` parameter
- Market orders only in V1
- Order status: new → partially_filled → filled (or cancelled/rejected)

**Portfolio Sync:**
```
GET https://broker-api.alpaca.markets/v1/trading/accounts/{account_id}/positions
GET https://broker-api.alpaca.markets/v1/trading/accounts/{account_id}/account
```
- Positions fetched on-demand, cached briefly (30s Redis)
- Market data for quotes via Alpaca Data API

**Auth:** API key + secret in Authorization header (Basic auth, base64 encoded). Keys stored in environment variables, never in code.

**Failure Handling:**
- API rate limits: 429 → exponential backoff with jitter
- Network failure: Retry up to 3 times with backoff
- Order rejection: Surface error to user, log full Alpaca response
- Account creation failure: Retry once, then queue for manual review

### 6.3 Google & Facebook OAuth

**Library:** NextAuth.js (Auth.js) handles the full OAuth2 flow.

**Google:**
- Provider: Google Cloud Console OAuth 2.0
- Scopes: `openid`, `email`, `profile`
- Callback: `/api/auth/callback/google`

**Facebook:**
- Provider: Facebook Login for Business
- Scopes: `email`, `public_profile`
- Callback: `/api/auth/callback/facebook`

**Flow:**
1. NextAuth redirects to provider
2. Provider authenticates user
3. Callback receives `id_token` / `access_token`
4. NextAuth extracts `email`, `name`, `provider_id`
5. Backend upserts User record
6. JWT issued for session

**Security:**
- CSRF protection via state parameter (handled by NextAuth)
- Tokens never exposed to frontend
- OAuth secrets in environment variables

---

## 7. Compliance & Security

### 7.1 Krezus Does Not Hold Funds

This is a critical architectural constraint:

- **Payment processing:** Stripe holds funds during checkout. Stripe transfers to Krezus operating account (for revenue) or directly to Alpaca (for investment funds).
- **Investment funds:** Held in Alpaca customer accounts. Krezus cannot access or move customer investment funds.
- **Krezus role:** Facilitator / technology layer. Not a broker, not a bank, not a custodian.

This must be reflected in:
- Terms of service
- All user-facing disclosures
- Technical architecture (no internal ledger for user funds)

### 7.2 Separation of Responsibilities

| Responsibility | Owner |
|----------------|-------|
| Payment processing | Stripe |
| Fund custody | Alpaca (via clearing partner) |
| KYC/AML checks | Alpaca |
| Brokerage compliance | Alpaca (registered broker-dealer) |
| Data privacy (GDPR) | Krezus |
| UI/UX, product | Krezus |
| Gift card issuance & fulfillment | Krezus |
| Customer support (L1) | Krezus |
| Trade execution | Alpaca |

### 7.3 Audit Logs

All sensitive operations must be logged in an `audit_log` table:

| Field | Type |
|-------|------|
| id | UUID |
| user_id | UUID (nullable — system actions) |
| action | VARCHAR(100) — e.g., `gift_card.activated`, `order.submitted`, `payment.succeeded` |
| resource_type | VARCHAR(50) |
| resource_id | UUID |
| metadata | JSONB — request IP, user agent, etc. |
| created_at | TIMESTAMPTZ |

Retention: 7 years minimum for financial audit trail.

### 7.4 Encryption

| Data | At Rest | In Transit |
|------|---------|------------|
| User PII (name, DOB, phone) | AES-256 column-level encryption | TLS 1.3 |
| Passwords | bcrypt (cost 12) | TLS 1.3 |
| Gift card codes | Hashed (SHA-256) + stored separately | TLS 1.3 |
| API keys (Stripe, Alpaca) | Environment variables / secrets manager | TLS 1.3 |
| Database | Encrypted volume (provider-managed) | TLS |
| Backups | Encrypted | — |

### 7.5 Risk Disclaimers Display Logic

Risk disclaimers must appear:

1. **Shop checkout page** (Step 3) — Before payment confirmation:
   > "Investing involves risk. The value of investments can go down as well as up. Past performance is not a guarantee of future results."

2. **Stock purchase confirmation** — Before order submission:
   > "You are about to place a market order. The execution price may differ from the displayed quote. Fractional shares may have limited liquidity."

3. **Dashboard footer** — Persistent on all dashboard pages:
   > "Krezus does not provide investment advice. Brokerage services are provided by Alpaca Securities LLC, a registered broker-dealer and member of FINRA/SIPC."

4. **Signup flow** — During account creation:
   > Link to full risk disclosure document + terms of service. Checkbox required.

Component: `<RiskDisclaimer variant="checkout|order|footer|signup" />` renders the appropriate text.

### 7.6 Additional Security Measures

- **Rate limiting:** 100 req/min per IP (public), 300 req/min per user (authenticated)
- **CORS:** Whitelist only `krezus.com` and `app.krezus.com`
- **CSP headers:** Strict Content-Security-Policy
- **Input validation:** Zod schemas on all API inputs (server-side)
- **SQL injection:** Prevented by Prisma parameterized queries
- **XSS:** React's default escaping + CSP
- **CSRF:** SameSite cookies + CSRF tokens on state-changing requests

---

## 8. Delivery Plan

### 8.1 MVP Scope

**In Scope:**
- Public website (Home, Manifesto, How it works)
- Gift card purchase flow (3-step shop funnel)
- Stripe Checkout integration (payment + webhooks)
- Digital gift card delivery via email
- User signup/login (email + Google OAuth)
- Gift card activation flow
- Alpaca account creation + funding
- Stock purchase (market orders, fractional shares)
- Portfolio display (positions, gains)
- Basic transaction history
- Risk disclaimers throughout
- Audit logging

**Out of Scope (V1):**
- Physical gift card fulfillment (flag exists, fulfillment manual)
- Mobile app (announcement only)
- Selling / liquidating positions
- ETF thematic boxes (catalog exists, complex UX deferred)
- Advanced order types (limit, stop)
- Dividend reinvestment (DRIP)
- Facebook OAuth (lower priority, add post-MVP)
- Multi-currency support (EUR-only MVP, USD conversion handled by Alpaca)
- Admin dashboard (use direct DB queries + Stripe/Alpaca dashboards)
- Referral program
- Push notifications

### 8.2 Suggested Milestones

| Milestone | Scope |
|-----------|-------|
| **M1 — Foundation** | Project setup, DB schema, auth (email + Google), static pages (Home, Manifesto, How it works) |
| **M2 — Shop & Payment** | 3-step shop funnel, Stripe Checkout integration, webhook handling, gift card creation, email delivery |
| **M3 — Activation & Brokerage** | Card activation flow, Alpaca account creation, KYC status handling, funding flow |
| **M4 — Trading & Portfolio** | Stock catalog, buy flow, Alpaca order execution, portfolio display, transaction history |
| **M5 — Polish & Compliance** | Risk disclaimers, error handling, audit logs, security hardening, edge cases |
| **M6 — QA & Launch** | End-to-end testing, load testing, Alpaca sandbox → production, Stripe live mode, deployment |

### 8.3 Technical Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Alpaca KYC rejection rates | Users unable to invest after receiving gift | Communicate KYC requirements upfront; offer refund path |
| ACH funding delays (1-3 days) | Poor UX after activation | Consider Alpaca instant funding if available; clear status messaging |
| Alpaca Broker API availability | Core trading blocked | Implement circuit breaker; cache portfolio data; queue orders |
| EUR→USD conversion | Price uncertainty for EU users | Display estimated conversion; use Alpaca's built-in FX or integrate separate FX provider |
| Regulatory requirements (EU) | Potential need for MiFID II compliance | Legal review required; Krezus may need to register as tied agent or rely fully on Alpaca's EU entity |
| Stripe webhook reliability | Payments confirmed but not processed | Implement reconciliation job (poll Stripe for recent sessions every 5 min) |
| Gift card fraud | Stolen codes, bulk activation | Rate limit activation, monitor patterns, add CAPTCHA on activation |

### 8.4 Open Questions for Founder

1. **Regulatory structure:** Is Krezus operating under Alpaca's broker-dealer license, or does Krezus need its own regulatory status (especially for EU users)?
2. **Currency handling:** Are gift cards priced in EUR? How is the EUR→USD conversion handled for US stock purchases? Who bears the FX spread?
3. **Physical gift cards:** What is the fulfillment process? Third-party printer? In-house? What triggers the "delivered" status?
4. **Gift card expiry:** Is there an expiry period? What happens to expired cards? Refund?
5. **Funding model:** Does Krezus use an omnibus account (Krezus master → journal to user) or individual ACH per user? Omnibus enables instant funding but adds compliance complexity.
6. **Revenue model:** Markup on gift card amount? Commission on trades? Spread? This affects Payment and Order data modeling.
7. **KYC timing:** Is KYC required at activation (blocking) or can it be deferred until first trade?
8. **Supported stocks:** Is the catalog fixed (curated by Krezus) or does it include all Alpaca-tradable securities?
9. **Mobile app timeline:** Is the V1 web app meant to be mobile-responsive, or is a separate React Native app planned for V2?
10. **Data residency:** Where must user data be stored? EU-only (GDPR)? Does this affect hosting choices?

---

*This document serves as the technical contract between product and engineering. All implementation should reference this blueprint. Any deviation requires explicit discussion and approval.*
