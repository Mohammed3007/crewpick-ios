begin;

create extension if not exists pgcrypto;

create type public.group_role as enum ('admin', 'member');
create type public.idea_category as enum ('food', 'activity', 'event', 'trip', 'other');
create type public.idea_status as enum ('board', 'planned', 'completed');
create type public.reaction_kind as enum ('in', 'maybe', 'pass');
create type public.notification_frequency as enum ('instant', 'daily_digest', 'off');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 80),
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  emoji text not null default '🎉',
  photo_path text,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.group_members (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.group_role not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table public.group_invites (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  code_hash text not null unique,
  created_by uuid not null references public.profiles(id),
  expires_at timestamptz not null,
  max_uses integer check (max_uses is null or max_uses > 0),
  use_count integer not null default 0 check (use_count >= 0),
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.ideas (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 200),
  category public.idea_category not null,
  location text,
  distance_km numeric(8,2) check (distance_km is null or distance_km >= 0),
  price_level smallint check (price_level between 1 and 4),
  note text check (char_length(note) <= 2000),
  source_url text,
  normalized_url text,
  image_path text,
  created_by uuid not null references public.profiles(id),
  status public.idea_status not null default 'board',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index ideas_group_normalized_url_unique on public.ideas(group_id, normalized_url) where normalized_url is not null;
create index ideas_group_created_idx on public.ideas(group_id, created_at desc);

create table public.reactions (
  idea_id uuid not null references public.ideas(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind public.reaction_kind not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (idea_id, user_id)
);

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  idea_id uuid not null references public.ideas(id) on delete cascade,
  author_id uuid not null references public.profiles(id),
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.plans (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  idea_id uuid not null references public.ideas(id),
  created_by uuid not null references public.profiles(id),
  completed_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index plans_one_active_per_group on public.plans(group_id) where completed_at is null;

create table public.notification_preferences (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  frequency public.notification_frequency not null default 'instant',
  updated_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  token_hash text not null unique,
  environment text not null check (environment in ('sandbox', 'production')),
  updated_at timestamptz not null default now()
);

create table public.activity_events (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  actor_id uuid not null references public.profiles(id),
  kind text not null,
  idea_id uuid references public.ideas(id) on delete cascade,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index activity_group_created_idx on public.activity_events(group_id, created_at desc);

create schema if not exists private;
revoke all on schema private from public;

create or replace function private.is_group_member(target_group uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from group_members where group_id = target_group and user_id = auth.uid()) $$;

create or replace function private.is_group_admin(target_group uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from group_members where group_id = target_group and user_id = auth.uid() and role = 'admin') $$;

create or replace function private.idea_group(target_idea uuid)
returns uuid language sql stable security definer set search_path = public
as $$ select group_id from ideas where id = target_idea $$;

alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.group_invites enable row level security;
alter table public.ideas enable row level security;
alter table public.reactions enable row level security;
alter table public.comments enable row level security;
alter table public.plans enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.device_tokens enable row level security;
alter table public.activity_events enable row level security;

create policy profiles_read_group_peers on public.profiles for select using (
  id = auth.uid() or exists (
    select 1 from public.group_members mine join public.group_members peer on peer.group_id = mine.group_id
    where mine.user_id = auth.uid() and peer.user_id = profiles.id
  )
);
create policy profiles_insert_self on public.profiles for insert with check (id = auth.uid());
create policy profiles_update_self on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

create policy groups_read_members on public.groups for select using (private.is_group_member(id));
create policy groups_insert_owner on public.groups for insert with check (created_by = auth.uid());
create policy groups_update_admin on public.groups for update using (private.is_group_admin(id));
create policy groups_delete_admin on public.groups for delete using (private.is_group_admin(id));

create policy members_read_group on public.group_members for select using (private.is_group_member(group_id));
create policy members_manage_admin on public.group_members for all using (private.is_group_admin(group_id)) with check (private.is_group_admin(group_id));

create policy invites_read_admin on public.group_invites for select using (private.is_group_admin(group_id));
create policy invites_create_admin on public.group_invites for insert with check (private.is_group_admin(group_id) and created_by = auth.uid());
create policy invites_update_admin on public.group_invites for update using (private.is_group_admin(group_id));

create policy ideas_read_members on public.ideas for select using (private.is_group_member(group_id));
create policy ideas_insert_members on public.ideas for insert with check (private.is_group_member(group_id) and created_by = auth.uid());
create policy ideas_update_creator_or_admin on public.ideas for update using (created_by = auth.uid() or private.is_group_admin(group_id));
create policy ideas_delete_creator_or_admin on public.ideas for delete using (created_by = auth.uid() or private.is_group_admin(group_id));

create policy reactions_read_members on public.reactions for select using (private.is_group_member(private.idea_group(idea_id)));
create policy reactions_insert_self on public.reactions for insert with check (user_id = auth.uid() and private.is_group_member(private.idea_group(idea_id)));
create policy reactions_update_self on public.reactions for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy reactions_delete_self on public.reactions for delete using (user_id = auth.uid());

create policy comments_read_members on public.comments for select using (private.is_group_member(private.idea_group(idea_id)));
create policy comments_insert_self on public.comments for insert with check (author_id = auth.uid() and private.is_group_member(private.idea_group(idea_id)));
create policy comments_update_self on public.comments for update using (author_id = auth.uid()) with check (author_id = auth.uid());
create policy comments_delete_self_or_admin on public.comments for delete using (author_id = auth.uid() or private.is_group_admin(private.idea_group(idea_id)));

create policy plans_read_members on public.plans for select using (private.is_group_member(group_id));
create policy plans_insert_members on public.plans for insert with check (private.is_group_member(group_id) and created_by = auth.uid());
create policy plans_update_members on public.plans for update using (private.is_group_member(group_id));
create policy plans_delete_admin on public.plans for delete using (private.is_group_admin(group_id));

create policy preferences_self on public.notification_preferences for all using (user_id = auth.uid()) with check (user_id = auth.uid() and private.is_group_member(group_id));
create policy tokens_self on public.device_tokens for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy activity_read_members on public.activity_events for select using (private.is_group_member(group_id));

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage on schema private to authenticated;
grant execute on all functions in schema private to authenticated;

commit;

