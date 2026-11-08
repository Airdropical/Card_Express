# Word Express

Word Express is an iOS vocabulary-learning app with a browser preview. The iOS app keeps working locally when signed out. When an account is connected, its folders, favorites, quiz settings, progress, activity, and language preferences sync to the Word Express API.

## Components

- `ios/` — SwiftUI app for iOS 17+, including invite-only account sign-in and profile sync
- `frontend/` — static browser preview served by the same origin as the API
- `backend/` — FastAPI service, account authentication, profile storage, rate limiting, and content endpoint
- `data/` — word data and JSON schemas
- PostgreSQL — account, profile, and rate-limit storage; provisioned separately in Railway

## Local development

1. Create a local PostgreSQL database and copy `.env.example` to `.env`.
2. Set a random `JWT_SECRET` (at least 32 characters) and a different random `REGISTRATION_INVITE_CODE` (at least 20 characters). Run `python3 -c 'import secrets; print(secrets.token_urlsafe(48))'` twice to generate separate values.
3. Install dependencies and start the API from the repository root:

   ```sh
   python3 -m venv .venv
   . .venv/bin/activate
   pip install -r requirements.txt
   sh backend/entrypoint.sh
   ```

4. Open `http://localhost:8080/`; the API health check is at `/api/health`.
5. In the iOS app's Profile tab, set the server URL to `http://127.0.0.1:8080` for the simulator. On a physical iPhone, use the Railway HTTPS domain; the app intentionally rejects non-HTTPS LAN endpoints.

The iOS app remains local-only until an account is created or signed in. Registration requires the configured invitation code. Passwords must be at least 12 characters. API tokens are kept in the iOS Keychain.

## Railway deployment

1. Connect this repository to a Railway service. The root `Dockerfile` builds the service, and `railway.toml` configures its health check.
2. Add a Railway PostgreSQL service and reference its `DATABASE_URL` from the app service.
3. Add these private service variables:
   - `APP_ENV=production`
   - `DATABASE_URL=${{Postgres.DATABASE_URL}}` (use the actual Railway database service name)
   - `JWT_SECRET` — a random secret with at least 32 characters
   - `REGISTRATION_INVITE_CODE` — a private value for account creation
   - `JWT_ISSUER=word-express`
   - `CORS_ORIGINS` — comma-separated browser origins only; keep empty if the preview is served from this same domain
4. Deploy. The container runs Alembic migrations before starting Uvicorn. Confirm `/api/health` returns `{"ok":true,...}`.
5. Set the iOS app's Profile → server address to the Railway HTTPS domain. Do not put database credentials or JWT secrets in the iOS app or repository.

Railway terminates public TLS; mobile requests must use the generated `https://` domain. HTTP is accepted by the iOS client only for `localhost` or `127.0.0.1` development.

## API

- `GET /api/health` — readiness check including PostgreSQL connectivity
- `GET /api/v1/content` — bundled word data
- `POST /api/v1/auth/register` — invite-only account creation
- `POST /api/v1/auth/login` — email/password login
- `POST /api/v1/auth/logout` — revoke current account sessions
- `GET /api/v1/profile` — current account profile and revision
- `PUT /api/v1/profile` — validate and persist profile using the required `If-Match` revision
- `DELETE /api/v1/account` — delete account and cloud profile after password confirmation
- `GET /privacy` — technical privacy notice

When an account is created, the current local profile is copied to that account. Signing into an existing account loads its cloud profile onto the device. Profile updates use revision checks so an older device cannot silently overwrite a newer cloud copy. Offline changes remain on-device and are retried when synchronization is requested or the app starts with a stored session.

Authentication attempts and profile writes are limited in PostgreSQL. Login is limited by both client address and email; registration also requires the private invitation code. Profiles are capped at 1 MB. Keep Railway's database and service usage visible in its billing dashboard and configure budget/usage alerts there; the app cannot enforce the provider's infrastructure bill.

## Current operating limits

This backend provides invite-only accounts, cloud storage for the existing profile model, and authenticated Gemini endpoints for card generation, answer evaluation, tutor chat, tutor action plans, and deck summaries. Keep registration invite-only for private use. AI request limits and a conservative token-cost budget are enforced per account; set a separate Google AI Studio spending limit as a second safeguard. The app shows every tutor action plan for review and confirmation before applying it. This pilot does not send email verification or password-reset emails or deliver push notifications. Before public release, configure support/contact details, review the privacy notice for the actual legal entity and Railway region/retention settings, and add verified email and account recovery.
