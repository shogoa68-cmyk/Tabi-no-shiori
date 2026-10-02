-- 旅ナビ：みんなで使う版（招待・いいね・ルート保存・名前）
-- 001_trips_spots.sql のあとに、Supabase の SQL Editor で1回だけ実行する。

-- ---------- 名前（Googleの名前を、同じ旅の人どうしで見せる） ----------
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text not null default '' check (char_length(name) <= 60),
  updated_at  timestamptz not null default now()
);

-- ---------- 招待（1回だけ・7日で切れる） ----------
create table public.trip_invites (
  code        text primary key default replace(gen_random_uuid()::text, '-', ''),
  trip_id     uuid not null references public.trips(id) on delete cascade,
  created_by  uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '7 days',
  used_by     uuid references auth.users(id) on delete set null,
  used_at     timestamptz
);
create index trip_invites_trip_idx on public.trip_invites(trip_id);

-- ---------- いいね（行きたい！） ----------
create table public.spot_likes (
  spot_id     uuid not null references public.spots(id) on delete cascade,
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (spot_id, user_id)
);

-- ---------- Claudeが返したルートの保存 ----------
create table public.routes (
  id          uuid primary key default gen_random_uuid(),
  trip_id     uuid not null references public.trips(id) on delete cascade,
  created_by  uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title       text not null default '' check (char_length(title) <= 60),
  body        text not null check (char_length(body) between 1 and 20000),
  created_at  timestamptz not null default now()
);
create index routes_trip_idx on public.routes(trip_id, created_at desc);

-- ---------- しくみ（関数） ----------
create function public.is_trip_owner(t uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.trip_members where trip_id = t and user_id = (select auth.uid()) and role = 'owner');
$$;

create function public.is_spot_member(s uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.spots sp join public.trip_members m on m.trip_id = sp.trip_id
                 where sp.id = s and m.user_id = (select auth.uid()));
$$;

create function public.shares_trip_with(other uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.trip_members a join public.trip_members b on a.trip_id = b.trip_id
                 where a.user_id = other and b.user_id = (select auth.uid()));
$$;

-- 招待コードで旅の名前を見る（参加する前の確認用。使えないコードは null）
create function public.preview_invite(p_code text) returns text
language sql stable security definer set search_path = '' as $$
  select t.title from public.trip_invites i join public.trips t on t.id = i.trip_id
  where i.code = p_code and i.used_at is null and i.expires_at > now() and (select auth.uid()) is not null;
$$;

-- 招待コードで旅に参加する（成功したら旅のid。すでにメンバーならコードは使わない）
create function public.join_trip(p_code text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare inv public.trip_invites; me uuid := (select auth.uid());
begin
  if me is null then raise exception 'not_logged_in'; end if;
  select * into inv from public.trip_invites where code = p_code for update;
  if not found or inv.used_at is not null or inv.expires_at <= now() then raise exception 'invite_invalid'; end if;
  if exists (select 1 from public.trip_members where trip_id = inv.trip_id and user_id = me) then return inv.trip_id; end if;
  insert into public.trip_members (trip_id, user_id, role) values (inv.trip_id, me, 'member');
  update public.trip_invites set used_by = me, used_at = now() where code = p_code;
  return inv.trip_id;
end $$;

-- ---------- 見ていい人・書いていい人（RLS） ----------
alter table public.profiles enable row level security;
alter table public.trip_invites enable row level security;
alter table public.spot_likes enable row level security;
alter table public.routes enable row level security;

create policy "profiles: 自分と同じ旅の人は見られる" on public.profiles for select to authenticated
  using (id = (select auth.uid()) or public.shares_trip_with(id));
create policy "profiles: 自分の名前を作れる" on public.profiles for insert to authenticated
  with check (id = (select auth.uid()));
create policy "profiles: 自分の名前を直せる" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "trip_invites: メンバーは見られる" on public.trip_invites for select to authenticated
  using (public.is_trip_member(trip_id));
create policy "trip_invites: メンバーは作れる" on public.trip_invites for insert to authenticated
  with check (public.is_trip_member(trip_id) and created_by = (select auth.uid()) and used_at is null);
create policy "trip_invites: メンバーは消せる" on public.trip_invites for delete to authenticated
  using (public.is_trip_member(trip_id));

create policy "spot_likes: メンバーは見られる" on public.spot_likes for select to authenticated
  using (public.is_spot_member(spot_id));
create policy "spot_likes: 自分のいいねを付けられる" on public.spot_likes for insert to authenticated
  with check (public.is_spot_member(spot_id) and user_id = (select auth.uid()));
create policy "spot_likes: 自分のいいねを外せる" on public.spot_likes for delete to authenticated
  using (user_id = (select auth.uid()));

create policy "routes: メンバーは見られる" on public.routes for select to authenticated
  using (public.is_trip_member(trip_id));
create policy "routes: メンバーは保存できる" on public.routes for insert to authenticated
  with check (public.is_trip_member(trip_id) and created_by = (select auth.uid()));
create policy "routes: メンバーは消せる" on public.routes for delete to authenticated
  using (public.is_trip_member(trip_id));

-- メンバーを外す：オーナーは自分以外を外せる／オーナー以外は自分だけぬけられる（オーナーは旅を削除してぬける）
drop policy "trip_members: 自分はぬけられる" on public.trip_members;
create policy "trip_members: ぬける・外す" on public.trip_members for delete to authenticated
  using ((user_id = (select auth.uid()) and role <> 'owner') or (public.is_trip_owner(trip_id) and user_id <> (select auth.uid())));

-- ---------- 権限（ログインしていない人には何も渡さない） ----------
revoke all on public.profiles, public.trip_invites, public.spot_likes, public.routes from anon;
grant select, insert, update on public.profiles to authenticated;
grant select, insert, delete on public.trip_invites, public.spot_likes, public.routes to authenticated;
revoke execute on function public.is_trip_owner(uuid), public.is_spot_member(uuid), public.shares_trip_with(uuid),
  public.preview_invite(text), public.join_trip(text) from public, anon;
grant execute on function public.is_trip_owner(uuid), public.is_spot_member(uuid), public.shares_trip_with(uuid),
  public.preview_invite(text), public.join_trip(text) to authenticated;
