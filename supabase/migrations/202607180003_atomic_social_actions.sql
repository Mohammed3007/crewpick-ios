begin;

create or replace function public.set_reaction(target_idea uuid, new_kind public.reaction_kind)
returns void language plpgsql security definer set search_path = public, private, pg_temp
as $$
declare existing_kind public.reaction_kind;
begin
  if not private.is_group_member(private.idea_group(target_idea)) then
    raise exception 'membership required' using errcode = '42501';
  end if;
  select kind into existing_kind from public.reactions
  where idea_id = target_idea and user_id = auth.uid();
  if existing_kind = new_kind then
    delete from public.reactions where idea_id = target_idea and user_id = auth.uid();
  else
    insert into public.reactions (idea_id, user_id, kind)
    values (target_idea, auth.uid(), new_kind)
    on conflict (idea_id, user_id) do update set kind = excluded.kind, updated_at = now();
  end if;
end;
$$;

create or replace function public.set_idea_status(target_idea uuid, new_status public.idea_status)
returns void language plpgsql security definer set search_path = public, private, pg_temp
as $$
declare target_group uuid;
begin
  target_group := private.idea_group(target_idea);
  if not private.is_group_member(target_group) then
    raise exception 'membership required' using errcode = '42501';
  end if;
  if new_status = 'planned' then
    update public.ideas set status = 'board' where group_id = target_group and status = 'planned' and id <> target_idea;
    delete from public.plans where group_id = target_group and completed_at is null;
    update public.ideas set status = 'planned' where id = target_idea;
    insert into public.plans (group_id, idea_id, created_by) values (target_group, target_idea, auth.uid());
  elsif new_status = 'completed' then
    update public.ideas set status = 'completed' where id = target_idea;
    update public.plans set completed_at = now() where group_id = target_group and idea_id = target_idea and completed_at is null;
  else
    update public.ideas set status = 'board' where id = target_idea;
    delete from public.plans where group_id = target_group and idea_id = target_idea and completed_at is null;
  end if;
end;
$$;

revoke all on function public.set_reaction(uuid, public.reaction_kind) from public;
revoke all on function public.set_idea_status(uuid, public.idea_status) from public;
grant execute on function public.set_reaction(uuid, public.reaction_kind) to authenticated;
grant execute on function public.set_idea_status(uuid, public.idea_status) to authenticated;

commit;
