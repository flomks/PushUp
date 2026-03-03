# PushUp App -- Backend & Supabase Setup

This directory contains everything needed to set up the Supabase backend for the PushUp App.

---

## Directory Structure

```
backend/
├── supabase/
│   ├── migrations/
│   │   └── 001_initial_schema.sql   # Full PostgreSQL schema + RLS policies
│   └── seed.sql                     # Optional test data for development
└── README.md                        # This file
```

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Supabase CLI | >= 1.200 | `brew install supabase/tap/supabase` |
| Docker Desktop | >= 4.x | https://www.docker.com/products/docker-desktop |
| psql (optional) | any | bundled with PostgreSQL |

---

## Option A: Supabase Cloud (Recommended for Production / Staging)

### Step 1 -- Create a Supabase Project

1. Go to **https://supabase.com** and sign in (or create a free account).
2. Click **"New project"**.
3. Fill in:
   - **Name:** `pushup-app` (or any name you like)
   - **Database Password:** choose a strong password and save it somewhere safe
   - **Region:** pick the region closest to your users
4. Click **"Create new project"** and wait ~2 minutes for provisioning.

### Step 2 -- Apply the Database Schema

**Via the SQL Editor (easiest):**

1. In the Supabase Dashboard, open your project.
2. Click **"SQL Editor"** in the left sidebar.
3. Click **"New query"**.
4. Copy the entire contents of `backend/supabase/migrations/001_initial_schema.sql` and paste it into the editor.
5. Click **"Run"** (or press `Cmd+Enter` / `Ctrl+Enter`).
6. You should see `Success. No rows returned` for each statement.

**Via the Supabase CLI:**

```bash
# Link your local project to the remote Supabase project
supabase link --project-ref <YOUR_PROJECT_REF>
# Your project ref is in the URL: https://supabase.com/dashboard/project/<ref>

# Push the migration
supabase db push
```

### Step 3 -- (Optional) Load Test Data

Only do this in a **development** project, never in production.

1. Open the SQL Editor in the Supabase Dashboard.
2. Paste the contents of `backend/supabase/seed.sql` and click **"Run"**.

### Step 4 -- Retrieve Your API Credentials

1. In the Supabase Dashboard, go to **Settings > API**.
2. Note down:
   - **Project URL** (e.g. `https://xyzxyzxyz.supabase.co`)
   - **anon / public key** (safe to use in the mobile app)
   - **service_role key** (keep secret -- only for server-side use)
   - **JWT Secret** (needed if you run a custom Ktor backend)

Store these as environment variables or in your CI/CD secrets. Never commit them to the repository.

---

## Option B: Local Development with Supabase CLI

Running Supabase locally lets you develop without touching the cloud project.

### Step 1 -- Start the Local Stack

```bash
# From the repository root
supabase start
```

Docker will pull the required images and start:
- PostgreSQL on `localhost:54322`
- Supabase Studio on `http://localhost:54323`
- REST API (PostgREST) on `http://localhost:54321`
- Auth (GoTrue) on `http://localhost:54321/auth/v1`

### Step 2 -- Apply Migrations

```bash
supabase db reset
# This drops and recreates the local DB, applies all migrations in order,
# and runs seed.sql if it exists at supabase/seed.sql.
```

Or apply only the migration without resetting:

```bash
supabase db push
```

### Step 3 -- Access Local Credentials

After `supabase start`, the CLI prints the local credentials:

```
API URL: http://localhost:54321
anon key: eyJ...
service_role key: eyJ...
DB URL: postgresql://postgres:postgres@localhost:54322/postgres
```

### Step 4 -- Stop the Local Stack

```bash
supabase stop
```

---

## Schema Overview

### Tables

| Table | Description |
|-------|-------------|
| `users` | User profiles (mirrors Supabase Auth) |
| `workout_sessions` | One row per workout session |
| `push_up_records` | Individual push-up events within a session |
| `time_credits` | Running totals of earned/spent screen-time credits per user |
| `user_settings` | Per-user configuration (credit rate, quality multiplier, daily cap) |

### Auto-generated REST API Endpoints

Supabase exposes every table automatically via PostgREST. All endpoints require the `Authorization: Bearer <jwt>` header.

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/rest/v1/workout_sessions` | List own sessions |
| POST | `/rest/v1/workout_sessions` | Create a new session |
| PATCH | `/rest/v1/workout_sessions?id=eq.<id>` | Update a session |
| DELETE | `/rest/v1/workout_sessions?id=eq.<id>` | Delete a session |
| GET | `/rest/v1/push_up_records?session_id=eq.<id>` | List records for a session |
| POST | `/rest/v1/push_up_records` | Insert a push-up record |
| GET | `/rest/v1/time_credits` | Get own credit balance |
| PATCH | `/rest/v1/time_credits?user_id=eq.<uid>` | Update credit balance |
| GET | `/rest/v1/user_settings` | Get own settings |
| PATCH | `/rest/v1/user_settings?user_id=eq.<uid>` | Update settings |

Full PostgREST documentation: https://postgrest.org/en/stable/

### Row Level Security

RLS is enabled on all tables. The policies enforce:

- A user can only **read, insert, update, or delete their own rows**.
- `push_up_records` access is gated through `workout_sessions.user_id`.
- The `handle_new_auth_user` trigger automatically creates rows in `users`, `time_credits`, and `user_settings` when a new Supabase Auth user signs up.

---

## Verifying the Setup

Run these queries in the SQL Editor to confirm everything is in place:

```sql
-- List all tables
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;

-- Confirm RLS is enabled
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;

-- Confirm indexes exist
SELECT indexname, tablename
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;
```

Expected tables: `push_up_records`, `time_credits`, `user_settings`, `users`, `workout_sessions`.
All should show `rowsecurity = true`.

---

## Environment Variables

The mobile app (KMP shared module) and any custom backend service need these variables:

| Variable | Where to find it | Used by |
|----------|-----------------|---------|
| `SUPABASE_URL` | Settings > API > Project URL | KMP API client, Ktor backend |
| `SUPABASE_ANON_KEY` | Settings > API > anon/public | KMP API client (mobile) |
| `SUPABASE_SERVICE_ROLE_KEY` | Settings > API > service_role | Ktor backend only (keep secret) |
| `SUPABASE_JWT_SECRET` | Settings > API > JWT Settings | Ktor backend JWT validation |
| `DATABASE_URL` | Settings > Database > Connection string | Ktor backend (Exposed) |

Create a `.env` file locally (never commit it):

```bash
SUPABASE_URL=https://xyzxyzxyz.supabase.co
SUPABASE_ANON_KEY=eyJ...
SUPABASE_SERVICE_ROLE_KEY=eyJ...
SUPABASE_JWT_SECRET=your-jwt-secret
DATABASE_URL=postgresql://postgres:<password>@db.xyzxyzxyz.supabase.co:5432/postgres
```

---

## Next Steps

After the schema is applied:

1. **Task 1B.2** -- Configure Supabase Auth (Email, Apple Sign-In, Google Sign-In).
2. **Task 1B.3** -- Set up the Ktor backend project for custom API endpoints.
3. **Task 1B.7** -- Implement the KMP API client (Ktor Client) to talk to Supabase.
4. **Task 1B.8** -- Implement Auth Use-Cases in the KMP shared module.

---

## Troubleshooting

**"permission denied for table users"**
Make sure you are using the `anon` key (not the `service_role` key) in the mobile app, and that the user is authenticated (JWT token in the `Authorization` header).

**"new row violates row-level security policy"**
The `auth.uid()` in the JWT does not match the `user_id` you are trying to insert. Make sure the client sends the correct JWT.

**Trigger `trg_on_auth_user_created` not firing locally**
The trigger fires on `auth.users`. When seeding locally without going through Supabase Auth, insert directly into `public.users` (as the seed.sql does).

**`gen_random_uuid()` not found**
This function is available in PostgreSQL 13+ and is enabled by default in Supabase. If you are running a very old PostgreSQL version locally, enable pgcrypto: `CREATE EXTENSION IF NOT EXISTS pgcrypto;`
