# DailyBudget — Personal Finance Tracker

A multi-user budgeting web app. Visitors create an account and get their own **private** dashboard for income, expenses, daily and monthly budgets, bills and savings goals.

- **Frontend:** one file, `index.html` (HTML + CSS + vanilla JavaScript). No npm, no build step, no custom server.
- **Backend:** [Supabase](https://supabase.com) — Auth + PostgreSQL with Row Level Security (RLS).
- **Hosting:** GitHub Pages (free).

| File | Purpose |
|---|---|
| `index.html` | The whole app (landing page, login, dashboard, all features) |
| `supabase_setup.sql` | Database tables, constraints, indexes, security policies, functions |
| `README.md` | This guide |
| `.gitignore` | Keeps secrets and personal exports out of Git |

---

## 1. Create the Supabase backend (about 10 minutes)

1. Sign up at <https://supabase.com> and click **New project**. Pick a name, a region near you, and a strong database password (store it in a password manager — you will not need it in the app).
2. Open **SQL Editor → New query**, paste the **entire contents of `supabase_setup.sql`**, and click **Run**. It is safe to run again later.
3. Open **Project Settings → API** (or **API Keys**) and copy:
   - **Project URL** (looks like `https://abcdxyz.supabase.co`)
   - **Publishable key** (or the legacy **anon** key). These are designed to be public.

> ⚠️ **Never** put the `service_role` / secret key or the database password in `index.html`. Anyone can read that file.

## 2. Configure the app

Open `index.html` in a text editor, search for `SUPABASE_URL`, and replace the two placeholders:

```js
const SUPABASE_URL = 'https://YOUR-PROJECT-REF.supabase.co';
const SUPABASE_KEY = 'YOUR-PUBLISHABLE-OR-ANON-KEY';
```

If you leave the placeholders, the app shows a setup screen instead of crashing.

If you use a **custom Supabase domain**, also add it to `connect-src` in the `<meta http-equiv="Content-Security-Policy">` tag near the top of `index.html`.

## 3. Configure Supabase Auth

In the Supabase dashboard go to **Authentication**:

1. **URL Configuration**
   - **Site URL:** your final site address, e.g. `https://YOUR-USERNAME.github.io/dailybudget/`
   - **Redirect URLs:** add the same address (and `http://localhost:8000/` if you test locally).
   - Email confirmation and password-reset links only work for addresses listed here.
2. **Sign In / Providers → Email:** keep *Email* enabled. Recommended: turn **Confirm email** ON so people must verify their address. (The app handles both settings.)
3. **Password policy:** set the minimum length to at least 8 (the app enforces 8 in the form).
4. **Emails:** Supabase's built-in email sender is rate-limited and meant for testing. For a real public launch, configure your own SMTP provider under **Authentication → SMTP Settings**.
5. Consider enabling **CAPTCHA protection** (Authentication → Attack Protection) if the site gets spam sign-ups. (Not wired into this app's forms; Supabase documents the required changes.)

## 4. Run it locally (optional)

Browsers block some features on `file://`, so serve the folder instead:

```bash
python3 -m http.server 8000
# then open http://localhost:8000/
```

Add `http://localhost:8000/` to the Supabase Redirect URLs (step 3).

## 5. Deploy to GitHub Pages

1. Create a new GitHub repository (e.g. `dailybudget`). Public is required for free Pages on most plans.
2. Upload `index.html`, `supabase_setup.sql`, `README.md` and `.gitignore` (drag and drop in the web UI works, or use git).
3. Repository **Settings → Pages → Build and deployment**: Source = **Deploy from a branch**, Branch = `main`, folder = `/ (root)`. Save.
4. After a minute your site is live at `https://YOUR-USERNAME.github.io/dailybudget/`.
5. Put that address into Supabase **Site URL** and **Redirect URLs** (step 3), then test sign-up and login.

Each time you edit `index.html` and push, Pages republishes automatically.

---

## Features

- Landing page, sign up, log in, log out, email verification, password reset, persistent sessions
- Dashboard: tracked balance, available-to-spend, today's and monthly income/expenses, remaining daily budget, upcoming bills, recent transactions, spending-by-category, income-vs-expenses and daily-trend charts, budget utilisation, insights
- Transactions: add / edit / delete (with confirmation), search, filter by date range, type, category, payment method, essential; sort; paging; CSV export
- Daily budget with progress bar, warnings at 50 % / 80 % / 100 % and when exceeded, optional rollover
- Monthly overall and per-category budgets, history, "copy from previous month"
- Bills with recurrence (once / weekly / monthly / annually), upcoming / overdue / paid views
- Savings goals with progress, remaining amount and suggested monthly contribution
- Reports with custom date ranges, charts and CSV export
- Settings: profile, currency (USD default), opening balance, light/dark mode, change password, full JSON backup, account deletion
- Responsive layout: sidebar on desktop, slide-out menu and floating "+" button on phones/tablets

## How the numbers work

- **Tracked balance** = opening balance + income − expenses dated on or before today. It is *your records*, not your bank's.
- **Available to spend** = tracked balance − money assigned to savings goals. Goals are an allocation of the balance, not an expense, so nothing is counted twice.
- **Credit cards:** record the *purchase* as an expense with payment method "Credit card". Marking a credit-card **bill** as paid does **not** create an expense (that would count the same money twice).
- **Bills vs expenses:** a bill is a reminder. When you mark a bill paid you may also create one expense; it is linked to the bill (`transactions.bill_id`). Paying a recurring bill moves its due date forward without creating anything else.
- **Daily budget remaining** = daily limit (+ carry-over if enabled) − that day's *expenses only*. Income never reduces spending.
- **Rollover (optional):** carry-over = max(0, Σ(daily limit − spent) for each earlier day this month, starting at your first transaction). Overspending reduces it, never below zero; it resets each month.
- **Currency:** changing it only changes display; amounts are not converted.
- **Insights** are computed in the browser from your own rows. Only real figures are shown.

## Security and privacy

- Authentication is handled by Supabase Auth; the app never sees or stores passwords. The session is managed by the Supabase client.
- **Authorization is enforced by the database.** Every table has RLS enabled and forced, with SELECT/INSERT/UPDATE/DELETE policies that require `auth.uid() = user_id` (or `id` for profiles). Triggers block changing a row's owner. The `anon` role has no table privileges, so signed-out visitors cannot read anything.
- Only the public key is in `index.html`. Hiding buttons is never relied on for security.
- All user text is HTML-escaped before display. CSV exports neutralise cells starting with `= + - @` to prevent spreadsheet formula injection.
- Amounts and dates are validated in the browser **and** by database constraints (positive, ≤ 2 decimals, bounded).
- Financial data and tokens are not placed in URLs, and the app does not log transaction details. Only the theme name is kept in `localStorage`.
- No bank logins or card numbers are requested or stored. Transactions are not sent to AI or analytics services.
- A Content Security Policy limits scripts to the page itself plus `cdn.jsdelivr.net` and connections to `*.supabase.co`.
- **GitHub Pages is public hosting:** anyone can read `index.html`. That is expected — the code is public, the data is not. Do not put secrets in the repository.
- Users can export their data and delete their account (`delete_my_account()` removes the auth user; all rows are removed by `ON DELETE CASCADE`).

### Honest limitations
- Third-party scripts (Supabase JS, Chart.js) load from jsDelivr at pinned versions. For stricter supply-chain safety, add [Subresource Integrity](https://developer.mozilla.org/docs/Web/Security/Subresource_Integrity) `integrity` hashes or self-host the two files.
- The CSP uses `'unsafe-inline'` because everything lives in one file.
- Supabase's email rate limits and bot protection need configuring for a high-traffic launch.
- Balances and savings are user-entered and unverified. This is not financial advice.

## Backups and data portability

- Each user: **Settings → Your data** → CSV of transactions or a full JSON backup.
- Owner: Supabase free projects have no automatic downloadable backups; paid plans include daily backups. You can also export tables from **Table Editor** or use `pg_dump`. Free projects pause after a week of inactivity — log in occasionally or upgrade for production use.

## Maintenance

- **Schema changes:** edit `supabase_setup.sql` (it is idempotent) and re-run it, or add new `alter table` statements.
- **Upgrading libraries:** change the version in the two `<script src>` tags and retest.
- **Monitor:** Supabase **Logs** and **Auth → Users**. Remove abusive accounts there.
- **Rotating keys:** if you ever exposed a secret key, rotate it in Project Settings → API immediately.
- **Troubleshooting**
  - *"The database tables were not found"* → run `supabase_setup.sql`.
  - *Email links go to the wrong page* → fix Site URL / Redirect URLs.
  - *Blank page after login* → open the browser console; confirm the URL/key and that the SQL ran without errors.
  - *Charts missing* → a content blocker may be blocking jsDelivr.

## Prototype / not-implemented notes

Everything listed under Features is functional against a real Supabase project. Not included: bank syncing, receipts upload, multi-currency conversion, sample demo data, push/email reminders for bills (alerts appear inside the app only), and MFA/CAPTCHA UI (Supabase supports them; they need extra configuration). The code could only be tested here with logic and rendering tests against a stub — please do a sign-up → add transaction → refresh run-through on your own Supabase project before sharing the link.
