# Supabase setup

The migrations define the v1 data model, indexes, constraints, Row Level Security, profile bootstrap, atomic group/invitation/reaction/plan RPCs, trusted activity triggers, notification preferences, and APNs device registration. Apply them in filename order to a new project with the Supabase CLI:

```sh
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

Invitation codes are generated server-side and retained only as hashes; plaintext is returned once to the creating admin. The iOS client must never receive a service-role key. When `SUPABASE_URL` and `SUPABASE_ANON_KEY` are configured, the app automatically uses native Supabase Auth and `SupabaseRemoteStore`; otherwise it runs the deterministic local preview.

Before production:

- Replace the example bundle and App Group identifiers.
- Configure Apple and email auth redirect URLs.
- Test every RLS policy using two users in different groups.
- Add the rate limits appropriate for the chosen Supabase plan.
- Deploy `metadata-preview` and `dispatch-notifications`, configure the secrets listed in `functions/.env.example`, and schedule the dispatcher at least once per minute with Supabase Cron. Send `Authorization: Bearer $DISPATCH_SECRET` from the scheduled request.
- Store APNs signing material only in the server secret store.

The notification outbox is populated transactionally from trusted activity events. Instant rows are eligible immediately; daily-digest rows become eligible at 09:00 UTC the next day. The dispatcher claims work with `FOR UPDATE SKIP LOCKED`, retries transient failures three times, removes invalid APNs tokens, and never sends reaction notifications in v1. Adjust the digest time when profile time-zone support is added.

`metadata-preview` requires a valid Supabase user JWT. It accepts HTTPS on port 443 only, revalidates each redirect, rejects private/reserved DNS results, limits response size and time, and returns only normalized Open Graph fields used to prefill an editable idea draft.
