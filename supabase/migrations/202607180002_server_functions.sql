begin;

-- Keep user-facing rows synchronized without trusting client timestamps.
create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
create trigger groups_set_updated_at before update on public.groups
for each row execute function public.set_updated_at();
create trigger ideas_set_updated_at before update on public.ideas
for each row execute function public.set_updated_at();
create trigger reactions_set_updated_at before update on public.reactions
for each row execute function public.set_updated_at();
create trigger comments_set_updated_at before update on public.comments
for each row execute function public.set_updated_at();
create trigger preferences_set_updated_at before update on public.notification_preferences
for each row execute function public.set_updated_at();
create trigger tokens_set_updated_at before update on public.device_tokens
for each row execute function public.set_updated_at();

-- Supabase Auth owns auth.users; every account receives a matching profile.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  chosen_name text;
begin
  chosen_name := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'CrewPick member'
  );
  insert into public.profiles (id, display_name)
  values (new.id, left(chosen_name, 80))
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- The first membership must be created in the same privileged transaction as
-- the group; the regular membership RLS policy intentionally requires an admin.
create or replace function public.create_group(group_name text, group_emoji text default '🎉')
returns public.groups language plpgsql security definer set search_path = public, private, pg_temp
as $$
declare
  created_group public.groups;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if char_length(trim(group_name)) not between 1 and 80 then raise exception 'invalid group name' using errcode = '22023'; end if;

  insert into public.groups (name, emoji, created_by)
  values (trim(group_name), coalesce(nullif(trim(group_emoji), ''), '🎉'), auth.uid())
  returning * into created_group;

  insert into public.group_members (group_id, user_id, role)
  values (created_group.id, auth.uid(), 'admin');
  insert into public.notification_preferences (group_id, user_id, frequency)
  values (created_group.id, auth.uid(), 'instant');
  return created_group;
end;
$$;

-- Invite plaintext is returned only at creation time. Only its SHA-256 hash is
-- retained, so database readers cannot enumerate usable invitation codes.
create or replace function public.create_group_invite(
  target_group uuid,
  valid_for interval default interval '7 days',
  allowed_uses integer default null
)
returns table(code text, expires_at timestamptz)
language plpgsql security definer set search_path = public, private, extensions, pg_temp
as $$
declare
  compact_code text;
  display_code text;
  expiry timestamptz;
begin
  if not private.is_group_admin(target_group) then raise exception 'admin required' using errcode = '42501'; end if;
  if valid_for <= interval '0 seconds' or valid_for > interval '30 days' then raise exception 'invalid expiry' using errcode = '22023'; end if;
  if allowed_uses is not null and allowed_uses <= 0 then raise exception 'invalid usage limit' using errcode = '22023'; end if;

  compact_code := upper(substr(encode(gen_random_bytes(8), 'hex'), 1, 10));
  display_code := substr(compact_code, 1, 5) || '-' || substr(compact_code, 6, 5);
  expiry := now() + valid_for;
  insert into public.group_invites (group_id, code_hash, created_by, expires_at, max_uses)
  values (target_group, encode(digest(compact_code, 'sha256'), 'hex'), auth.uid(), expiry, allowed_uses);
  return query select display_code, expiry;
end;
$$;

create or replace function public.accept_group_invite(invite_code text)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp
as $$
declare
  normalized_code text;
  matching_invite public.group_invites;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  normalized_code := upper(regexp_replace(invite_code, '[^A-Za-z0-9]', '', 'g'));
  if char_length(normalized_code) < 6 then raise exception 'invalid invitation' using errcode = '22023'; end if;

  select * into matching_invite
  from public.group_invites
  where code_hash = encode(digest(normalized_code, 'sha256'), 'hex')
    and revoked_at is null and expires_at > now()
    and (max_uses is null or use_count < max_uses)
  for update;
  if not found then raise exception 'invalid invitation' using errcode = '22023'; end if;

  insert into public.group_members (group_id, user_id, role)
  values (matching_invite.group_id, auth.uid(), 'member')
  on conflict do nothing;
  if found then
    update public.group_invites set use_count = use_count + 1 where id = matching_invite.id;
  end if;
  insert into public.notification_preferences (group_id, user_id, frequency)
  values (matching_invite.group_id, auth.uid(), 'instant')
  on conflict do nothing;
  return matching_invite.group_id;
end;
$$;

create or replace function public.revoke_group_invite(invite_id uuid)
returns void language plpgsql security definer set search_path = public, private, pg_temp
as $$
declare target_group uuid;
begin
  select group_id into target_group from public.group_invites where id = invite_id;
  if target_group is null or not private.is_group_admin(target_group) then raise exception 'admin required' using errcode = '42501'; end if;
  update public.group_invites set revoked_at = now() where id = invite_id;
end;
$$;

-- A hash is useful for deduplication, but APNs dispatch also needs the original
-- token. Access remains restricted to the owning user through RLS.
alter table public.device_tokens add column token text not null unique;

create or replace function public.register_device_token(raw_token text, apns_environment text)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp
as $$
declare token_digest text;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if apns_environment not in ('sandbox', 'production') then raise exception 'invalid APNs environment' using errcode = '22023'; end if;
  if raw_token !~ '^[0-9a-fA-F]{32,200}$' then raise exception 'invalid device token' using errcode = '22023'; end if;
  token_digest := encode(digest(lower(raw_token), 'sha256'), 'hex');
  insert into public.device_tokens (user_id, token_hash, token, environment)
  values (auth.uid(), token_digest, lower(raw_token), apns_environment)
  on conflict (token_hash) do update set
    user_id = excluded.user_id, token = excluded.token,
    environment = excluded.environment, updated_at = now();
end;
$$;

create or replace function public.set_notification_preference(target_group uuid, new_frequency public.notification_frequency)
returns void language plpgsql security definer set search_path = public, private, pg_temp
as $$
begin
  if not private.is_group_member(target_group) then raise exception 'membership required' using errcode = '42501'; end if;
  insert into public.notification_preferences (group_id, user_id, frequency)
  values (target_group, auth.uid(), new_frequency)
  on conflict (group_id, user_id) do update set frequency = excluded.frequency, updated_at = now();
end;
$$;

revoke all on function public.create_group(text, text) from public;
revoke all on function public.create_group_invite(uuid, interval, integer) from public;
revoke all on function public.accept_group_invite(text) from public;
revoke all on function public.revoke_group_invite(uuid) from public;
revoke all on function public.register_device_token(text, text) from public;
revoke all on function public.set_notification_preference(uuid, public.notification_frequency) from public;
grant execute on function public.create_group(text, text) to authenticated;
grant execute on function public.create_group_invite(uuid, interval, integer) to authenticated;
grant execute on function public.accept_group_invite(text) to authenticated;
grant execute on function public.revoke_group_invite(uuid) to authenticated;
grant execute on function public.register_device_token(text, text) to authenticated;
grant execute on function public.set_notification_preference(uuid, public.notification_frequency) to authenticated;

commit;
