# Supabase setup

The migrations define the v1 data model, indexes, constraints, Row Level Security, profile bootstrap trigger, atomic group/invitation RPCs, notification preference RPC, and APNs device registration. Apply them to a new project with the Supabase CLI:

```sh
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

Invitation codes are generated server-side and retained only as hashes; plaintext is returned once to the creating admin. The iOS client must never receive a service-role key. The repository includes a public-key-only REST/RPC transport, but remote mode should not be enabled until an Auth session is wired and the policies below are exercised against a real project.

Before production:

- Replace the example bundle and App Group identifiers.
- Configure Apple and email auth redirect URLs.
- Test every RLS policy using two users in different groups.
- Add trusted activity-event triggers and the rate limits appropriate for the chosen Supabase plan.
- Implement and deploy the metadata-fetch and APNs-dispatch Edge Functions.
- Store APNs signing material only in the server secret store.
