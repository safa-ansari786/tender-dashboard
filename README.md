# IDCG Tender Platform — Supabase foundation

## Current status
- The existing dashboard remains unchanged and continues to use browser localStorage.
- `client.js` provides a Supabase JS v2 wrapper for authentication and tender CRUD.
- `config.example.js` documents the browser-side configuration format.
- The client is not yet wired into `index.html`; that is a separate migration step after the IDCG Supabase project is configured and tested.
- No live Supabase project is connected and no tender records have been imported by this starter package.

## Setup
1. Create the Supabase project under an IDCG-controlled account.
2. In the Supabase SQL Editor, review and run the IDCG schema v1 SQL script in a fresh project only.
3. Copy `config.example.js` to `config.js`.
4. Set the project URL and publishable (or legacy anon) key in `config.js`.
5. Keep `config.js` out of source control if the organisation prefers not to publish project identifiers. The publishable key is not a service secret, but database access must be protected by Row Level Security.
6. Load Supabase JS v2, then `supabase/config.js`, then `supabase/client.js` before using `window.IDCGCloud`.

## Security
- Never put a Supabase `service_role` key, database password, SMTP password, or other secret in browser code or GitHub.
- Do not enable unrestricted public sign-up for this internal application.
- Use invite-only authentication and database Row Level Security (RLS).
- Test permissions using separate accounts for each role before production use.
- Hiding a UI button is not authorization; permissions must be enforced by RLS.

## Tender field mapping
The current dashboard uses camelCase fields (`name`, `client`, `value`, `currency`, `date`, `status`). The database uses snake_case fields (`tender_name`, `client_name`, `tender_value`, `tender_currency`, `tender_date`). A dedicated mapping and migration layer must be implemented and tested before switching the live dashboard to cloud data.

## Next implementation stages
1. Add a login screen and authenticated session handling.
2. Map the existing dashboard record shape to the database schema.
3. Load and save tenders through Supabase, with safe loading/error states.
4. Add user profiles, roles, and permission-aware controls.
5. Import the 78-record backup with source rows retained for traceability.
6. Test multi-currency reporting and role isolation before deployment.
