-- 自分の「いつもの最寄駅」を、ログインした人ごとに保存する（メイン1つ・サブ1つ）
-- 形：{ "main": { "name": "新宿駅", "lat": 35.68, "lng": 139.70 }, "sub": { ... } }
-- 見られるのは、これまでの profiles の決まり（自分と同じ旅の人）。自分の行だけ直せる（002 の policy のまま）
alter table public.profiles add column if not exists home jsonb;
