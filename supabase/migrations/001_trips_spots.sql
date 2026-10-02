-- 旅ナビ：旅（trips）・メンバー（trip_members）・行きたい場所（spots）
-- Supabase の SQL Editor に全部貼って、1回だけ実行する。
-- likes（投票）・routes（ルート保存）は、みんなで版を作るときに追加する。

-- ---------- 表 ----------
create table public.trips (
  id          uuid primary key default gen_random_uuid(),
  title       text not null default '私の旅' check (char_length(title) <= 60),
  memo        text not null default '' check (char_length(memo) <= 400),
  created_by  uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table public.trip_members (
  trip_id    uuid not null references public.trips(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  role       text not null default 'member' check (role in ('owner', 'member')),
  joined_at  timestamptz not null default now(),
  primary key (trip_id, user_id)
);
create index trip_members_user_idx on public.trip_members(user_id);

create table public.spots (
  id          uuid primary key default gen_random_uuid(),
  trip_id     uuid not null references public.trips(id) on delete cascade,
  created_by  uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name        text not null check (char_length(name) between 1 and 60),
  prio        smallint not null default 2 check (prio between 1 and 3),
  area        text not null default '' check (char_length(area) <= 60),
  address     text not null default '' check (char_length(address) <= 120),
  stay        smallint check (stay between 1 and 1440),
  hours       text not null default '' check (char_length(hours) <= 40),
  closed      text not null default '' check (char_length(closed) <= 40),
  kind        text not null default '観光' check (char_length(kind) <= 20),
  when_text   text not null default '' check (char_length(when_text) <= 30),
  map         text not null default '' check (char_length(map) <= 2000),
  memo        text not null default '' check (char_length(memo) <= 300),
  done        boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index spots_trip_idx on public.spots(trip_id);

-- ---------- しくみ（関数・トリガー） ----------
-- この旅のメンバーかどうか（RLS の中で使う。security definer で RLS の堂々めぐりを防ぐ）
create function public.is_trip_member(t uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.trip_members where trip_id = t and user_id = (select auth.uid()));
$$;

-- 旅を作った人を、自動でオーナーとしてメンバーに入れる
create function public.add_trip_owner() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.trip_members (trip_id, user_id, role) values (new.id, new.created_by, 'owner');
  return new;
end $$;
create trigger trips_add_owner after insert on public.trips
  for each row execute function public.add_trip_owner();

-- 更新した時刻を自動で入れる
create function public.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end $$;
create trigger trips_touch before update on public.trips for each row execute function public.touch_updated_at();
create trigger spots_touch before update on public.spots for each row execute function public.touch_updated_at();

-- ---------- 見ていい人・書いていい人（RLS） ----------
alter table public.trips enable row level security;
alter table public.trip_members enable row level security;
alter table public.spots enable row level security;

create policy "trips: メンバーは見られる" on public.trips for select to authenticated
  using (public.is_trip_member(id) or created_by = (select auth.uid()));
create policy "trips: 自分の旅を作れる" on public.trips for insert to authenticated
  with check (created_by = (select auth.uid()));
create policy "trips: メンバーは直せる" on public.trips for update to authenticated
  using (public.is_trip_member(id)) with check (public.is_trip_member(id));
create policy "trips: 作った人だけ消せる" on public.trips for delete to authenticated
  using (created_by = (select auth.uid()));

create policy "trip_members: 同じ旅のメンバーは見られる" on public.trip_members for select to authenticated
  using (public.is_trip_member(trip_id));
create policy "trip_members: 自分はぬけられる" on public.trip_members for delete to authenticated
  using (user_id = (select auth.uid()));

create policy "spots: メンバーは見られる" on public.spots for select to authenticated
  using (public.is_trip_member(trip_id));
create policy "spots: メンバーは追加できる" on public.spots for insert to authenticated
  with check (public.is_trip_member(trip_id) and created_by = (select auth.uid()));
create policy "spots: メンバーは直せる" on public.spots for update to authenticated
  using (public.is_trip_member(trip_id)) with check (public.is_trip_member(trip_id));
create policy "spots: メンバーは消せる" on public.spots for delete to authenticated
  using (public.is_trip_member(trip_id));

-- ログインしていない人（anon）には何も見せない。ログインした人だけ使える
revoke all on public.trips, public.trip_members, public.spots from anon;
grant select, insert, update, delete on public.trips, public.spots to authenticated;
grant select, delete on public.trip_members to authenticated;
revoke execute on function public.is_trip_member(uuid), public.add_trip_owner(), public.touch_updated_at() from public, anon;
grant execute on function public.is_trip_member(uuid) to authenticated;
