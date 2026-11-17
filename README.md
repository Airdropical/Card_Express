# ELearnCard

ELearnCard is an iOS vocabulary-learning app with a browser preview and a FastAPI backend. The iOS app keeps working locally when signed out. When an account is connected, its folders, favorites, quiz settings, progress, activity, and language preferences sync to the ELearnCard API.

## Components

- `iOS/` — active SwiftUI app for iOS 17+, including invite-only account sign-in and profile sync
- `frontend/` — static browser preview served by the same origin as the API
- `backend/` — FastAPI service: `server.py` (routes), `config.py`, `db.py`, `auth.py`, `rate_limit.py`, `ai_client.py` (Gemini and usage limits), `agent_plan.py` (tutor plan helpers), `ai_prompts/`, `tests/`
- `data/` — word data and JSON schemas
- `archive/wordexpress-ios-prototype/` — preserved earlier standalone Xcode prototype; not part of the active app or Railway build
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

   The server refuses to start without a `JWT_SECRET` of at least 32 characters and a `DATABASE_URL`, in every environment.

4. Run the backend tests (no database or API key needed):

   ```sh
   pip install -r requirements-dev.txt
   python -m pytest backend/tests
   ```

5. Open `http://localhost:8080/`; the API health check is at `/api/health`.
6. In the iOS app's Profile tab, set the server URL to `http://127.0.0.1:8080` for the simulator. On a physical iPhone, use the Railway HTTPS domain; the app intentionally rejects non-HTTPS LAN endpoints.

Open `iOS/Lernkarten.xcodeproj` to build the active app. It remains local-only until an account is created or signed in. Registration requires the configured invitation code. Passwords must be at least 12 characters. API tokens are kept in the iOS Keychain.

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
- `POST /api/v1/auth/apple` — sign in with Apple: verifies the identity token and returns a session
- `GET /api/v1/account` — account email and today's AI usage
- `DELETE /api/v1/account` — delete the account with its synced data and usage records
- `POST /api/v1/auth/logout` — revoke the account's sessions
- `GET /api/v1/profile` — the synced learning data and its revision (`profile` is null before the first upload)
- `PUT /api/v1/profile` — upload the learning data; requires the current revision in `If-Match`, answers 409 otherwise
- `POST /api/generate-cards`, `/api/evaluate`, `/api/tutor`, `/api/agent-plan`, `/api/summary` — AI features
- `POST /api/v1/tests` — a tutor-written test, checked before it is generated
- `PUT`/`DELETE /api/v1/devices` — register or remove a device for push notifications
- `POST /api/internal/daily-tests` — scheduled job that sends the daily test notifications
- `POST /api/v1/auth/register`, `/api/v1/auth/login` — legacy email/password accounts; registration stays closed unless `REGISTRATION_INVITE_CODE` is set
- `GET /privacy`, `/terms`, `/imprint` — legal pages (`frontend/*.html`)

### Accounts and sync

The app signs in with Apple; the server checks the token's signature, audience (`APPLE_BUNDLE_ID`) and nonce. Signed-in devices keep one snapshot of the learning data per account. A device uploads when the cloud still has the revision it last saw and downloads when it has no changes of its own; if both sides changed, the app asks which version to keep. To revoke the Apple grant on account deletion, set `APPLE_TEAM_ID`, `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY`.

### Daily tests and notifications

`POST /api/v1/tests` writes a test from the cards the app sends: for a calendar entry with a linked deck in the next three days (`exam`) or from cards that went badly before (`weak`). The rules in `backend/daily_tests.py` run first; a test that is not due is refused without an AI request, and a written test is stored and served again for the rest of the day.

The app plans reminders on the device. Server-sent push is optional: set `APPLE_TEAM_ID`, `APNS_KEY_ID`, `APNS_PRIVATE_KEY` and `JOB_SECRET`, then let a scheduler (for example a Railway cron service) call the job once a day:

```sh
curl -fsS -X POST -H "X-Job-Secret: $JOB_SECRET" https://<your-domain>/api/internal/daily-tests
```

The job checks each registered account's synced data with the same rules and sends at most one notification per account and day. It makes no AI request. Accounts that get server push stop planning their own reminders.

### Plans

Every account has a `plan` (`free` today). `AI_DAILY_REQUEST_LIMIT_PLUS` is the daily limit for `plus`, prepared for a later subscription; nothing sets it yet.

### AI limits

Every account gets `AI_DAILY_REQUEST_LIMIT` requests per rolling 24 hours; `AI_GLOBAL_DAILY_REQUEST_LIMIT` caps all accounts together. The account named in `AI_UNLIMITED_ACCOUNT_EMAIL` is exempt.

### Before going public

- Fill in every highlighted `‹…›` placeholder in `frontend/privacy.html`, `terms.html` and `imprint.html` and have the texts checked.
- Check the Gemini API terms for your audience and region (paid tier for EU users, age restrictions) and conclude the data-processing agreements with Google and Railway.
- The Sign in with Apple capability needs a paid Apple Developer account.

## Current operating limits

This backend provides invite-only accounts, cloud storage for the existing profile model, and authenticated Gemini endpoints for card generation, answer evaluation, tutor chat, tutor action plans, and deck summaries. Keep registration invite-only for private use. AI request limits and a conservative token-cost budget are enforced per account (lifetime caps by default; set `AI_LIMIT_WINDOW_DAYS=30` for rolling 30-day caps). Requests that fail before Gemini answers do not count against them; set a separate Google AI Studio spending limit as a second safeguard. The app shows every tutor action plan for review and confirmation before applying it. This pilot does not send email verification or password-reset emails or deliver push notifications. Before public release, configure support/contact details, review the privacy notice for the actual legal entity and Railway region/retention settings, and add verified email and account recovery.
