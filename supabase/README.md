# Supabase setup

The migration defines the v1 data model, indexes, constraints, and Row Level Security. Apply it to a new project with the Supabase CLI:

```sh
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

Security-sensitive invitation acceptance, profile bootstrapping, activity creation, metadata fetching, and APNs dispatch must be implemented as server-side functions before enabling the remote repositories. Invitation codes must be generated randomly and stored only as hashes; the iOS client must never receive a service-role key.

Before production:

- Replace the example bundle and App Group identifiers.
- Configure Apple and email auth redirect URLs.
- Add a transactional `create_group` function that creates the group and its first admin membership together.
- Add a rate-limited `accept_invite` function that hashes the supplied code and increments usage atomically.
- Add database triggers for `updated_at` and trusted activity events.
- Test every RLS policy using two users in different groups.
- Store APNs signing material only in the server secret store.
