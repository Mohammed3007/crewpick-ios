begin;

-- Activity rows are written by trusted database triggers so clients cannot
-- impersonate another member or fabricate events.
create or replace function public.log_new_group_member()
returns trigger language plpgsql security definer set search_path = public, pg_temp
as $$
declare group_name text;
begin
  select name into group_name from public.groups where id = new.group_id;
  insert into public.activity_events (group_id, actor_id, kind, metadata)
  values (new.group_id, new.user_id, 'memberJoined', jsonb_build_object('group_name', group_name));
  return new;
end;
$$;

create trigger group_members_log_activity
after insert on public.group_members
for each row execute function public.log_new_group_member();

create or replace function public.log_new_idea()
returns trigger language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  insert into public.activity_events (group_id, actor_id, kind, idea_id, metadata)
  values (new.group_id, new.created_by, 'ideaAdded', new.id, jsonb_build_object('title', new.title));
  return new;
end;
$$;

create trigger ideas_log_creation
after insert on public.ideas
for each row execute function public.log_new_idea();

create or replace function public.log_new_comment()
returns trigger language plpgsql security definer set search_path = public, pg_temp
as $$
declare target_group uuid; idea_title text;
begin
  select group_id, title into target_group, idea_title from public.ideas where id = new.idea_id;
  insert into public.activity_events (group_id, actor_id, kind, idea_id, metadata)
  values (target_group, new.author_id, 'commentAdded', new.idea_id, jsonb_build_object('title', idea_title));
  return new;
end;
$$;

create trigger comments_log_creation
after insert on public.comments
for each row execute function public.log_new_comment();

create or replace function public.log_reaction_change()
returns trigger language plpgsql security definer set search_path = public, pg_temp
as $$
declare target_idea uuid; target_actor uuid; target_group uuid; idea_title text;
begin
  target_idea := coalesce(new.idea_id, old.idea_id);
  target_actor := coalesce(new.user_id, old.user_id);
  select group_id, title into target_group, idea_title from public.ideas where id = target_idea;
  if target_group is not null then
    insert into public.activity_events (group_id, actor_id, kind, idea_id, metadata)
    values (target_group, target_actor, 'reactionChanged', target_idea, jsonb_build_object('title', idea_title));
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create trigger reactions_log_activity
after insert or update or delete on public.reactions
for each row execute function public.log_reaction_change();

create or replace function public.log_idea_status_change()
returns trigger language plpgsql security definer set search_path = public, pg_temp
as $$
declare activity_kind text;
begin
  if new.status is not distinct from old.status then return new; end if;
  if new.status = 'planned' then activity_kind := 'planCreated';
  elsif new.status = 'completed' then activity_kind := 'planCompleted';
  else return new;
  end if;
  insert into public.activity_events (group_id, actor_id, kind, idea_id, metadata)
  values (new.group_id, auth.uid(), activity_kind, new.id, jsonb_build_object('title', new.title));
  return new;
end;
$$;

create trigger ideas_log_status_activity
after update of status on public.ideas
for each row execute function public.log_idea_status_change();

revoke all on function public.log_new_group_member() from public;
revoke all on function public.log_new_idea() from public;
revoke all on function public.log_new_comment() from public;
revoke all on function public.log_reaction_change() from public;
revoke all on function public.log_idea_status_change() from public;

commit;
