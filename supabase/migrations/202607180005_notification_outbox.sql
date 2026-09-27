begin;

create type public.notification_delivery_mode as enum ('instant', 'daily_digest');
create type public.notification_delivery_status as enum ('pending', 'processing', 'delivered', 'failed');

create table public.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.activity_events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  delivery_mode public.notification_delivery_mode not null,
  status public.notification_delivery_status not null default 'pending',
  available_at timestamptz not null default now(),
  attempt_count integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_id, user_id)
);
create index notification_deliveries_ready_idx
on public.notification_deliveries(status, available_at);
alter table public.notification_deliveries enable row level security;

create or replace function public.enqueue_activity_notifications()
returns trigger language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  -- Reaction changes remain visible in Activity but intentionally do not push in v1.
  if new.kind = 'reactionChanged' then return new; end if;

  insert into public.notification_deliveries (event_id, user_id, delivery_mode, available_at)
  select
    new.id,
    members.user_id,
    case when coalesce(preferences.frequency, 'instant') = 'daily_digest'
      then 'daily_digest'::public.notification_delivery_mode
      else 'instant'::public.notification_delivery_mode
    end,
    case when coalesce(preferences.frequency, 'instant') = 'daily_digest'
      then date_trunc('day', now() at time zone 'UTC') + interval '1 day 9 hours'
      else now()
    end
  from public.group_members members
  left join public.notification_preferences preferences
    on preferences.group_id = members.group_id and preferences.user_id = members.user_id
  where members.group_id = new.group_id
    and members.user_id <> new.actor_id
    and coalesce(preferences.frequency, 'instant') <> 'off'
  on conflict (event_id, user_id) do nothing;
  return new;
end;
$$;

create trigger activity_enqueue_notifications
after insert on public.activity_events
for each row execute function public.enqueue_activity_notifications();

create or replace function public.claim_notification_deliveries(batch_size integer default 100)
returns setof public.notification_deliveries
language sql security definer set search_path = public, pg_temp
as $$
  with candidates as (
    select id from public.notification_deliveries
    where available_at <= now()
      and (
        status = 'pending'
        or (status = 'processing' and updated_at < now() - interval '10 minutes')
      )
    order by available_at, created_at
    limit greatest(1, least(batch_size, 500))
    for update skip locked
  ), claimed as (
    update public.notification_deliveries deliveries
    set status = 'processing', attempt_count = attempt_count + 1, updated_at = now()
    from candidates
    where deliveries.id = candidates.id
    returning deliveries.*
  )
  select * from claimed;
$$;

create or replace function public.finish_notification_deliveries(delivery_ids uuid[], failure text default null)
returns void language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if failure is null then
    update public.notification_deliveries
    set status = 'delivered', last_error = null, updated_at = now()
    where id = any(delivery_ids);
  else
    update public.notification_deliveries
    set
      status = case when attempt_count >= 3 then 'failed'::public.notification_delivery_status else 'pending'::public.notification_delivery_status end,
      available_at = now() + make_interval(mins => least(60, (power(2, attempt_count)::integer))),
      last_error = left(failure, 500),
      updated_at = now()
    where id = any(delivery_ids);
  end if;
end;
$$;

revoke all on table public.notification_deliveries from anon, authenticated;
revoke all on function public.enqueue_activity_notifications() from public;
revoke all on function public.claim_notification_deliveries(integer) from public;
revoke all on function public.finish_notification_deliveries(uuid[], text) from public;
grant execute on function public.claim_notification_deliveries(integer) to service_role;
grant execute on function public.finish_notification_deliveries(uuid[], text) to service_role;

commit;
