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
- Implement and deploy the metadata-fetch and APNs-dispatch Edge Functions.
- Store APNs signing material only in the server secret store.
