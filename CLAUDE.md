# Tabi-no-shiori（いまから旅ナビ）

## これは何？
1人で使う、旅行中のルート相談アプリ。
スマホで開き、現在地と現在時刻、事前に登録した「行きたい場所リスト」から、Claudeへのお願い文（プロンプト）を作る。
それを Claude アプリに渡すと、Claude が Web 検索で営業時間や電車を調べ、最適なルートを返す。

- 公開URL：https://shogoa68-cmyk.github.io/Tabi-no-shiori/
- 公開方法：GitHub Pages（main ブランチ / root）。push すると1〜2分で反映される
- 利用者：オーナー1人（スマホ、iPhone想定）
- 直近の旅行では使わないことになった（2026-10）。日程を気にせず、Supabase 保存などの大きめの変更もしてよい。ただし公開中のページ（main）はいつも動く状態に保つ（大きな変更はブランチで作って、確認してから main に入れる）

## しくみ
- ファイルは `index.html` の1枚だけ（HTML・CSS・JS をすべてこの中に書く。ビルドなし・ライブラリなし。例外：クラウド保存用の supabase-js だけは jsDelivr から版を固定して読みこむ）
- 保存先：`localStorage`（キー `tabi-navi-v1`）。端末のブラウザの中だけに保存
  - 形：`{ spots: [...], here: {lat,lng,acc,at,address} | null, settings: {要素id: 値}, backupAt?: 最後にコピーした時刻, guardHideUntil?: 案内を隠す期限 }`
  - spot：`{ id, name, prio(1-3), area, address, stay(分|null), hours, closed, kind, when, map, memo, done, created }`（`address` は後から追加。古いデータにはないので空として扱う）
  - **データの形を変えるときは、古いデータも読めるようにすること**（オーナーのリストが消えないように）
- データを守る案内（`#guard`）：iPhoneのSafariは7日間ひらかないサイトのデータを消すことがあるため、
  - ログインしていない人に「Googleでログイン」をすすめる（iPhoneのSafariなら「ホーム画面に追加」もすすめる。ホーム画面アプリでもログインすれば同じリストが出る）。ログインしない人向けに「データをコピー」も残す
  - クラウドと一度でも同期できていれば（`tabi-navi-sync` に userId と lastSync がある）カードは出さない
  - 出す条件：iPhoneのSafari、またはバックアップが一度もない／7日以上前。「あとで」で3日間かくす
  - 起動時に `navigator.storage.persist()` を呼ぶ
- クラウド保存（「旅の設定・バックアップ」の中。だれにでも表示）：Supabase プロジェクト `cnnwxwiqauyawngkpapk`、Google ログイン。supabase-js は起動時に読みこむ（読めなくても手元保存で動く）
  - 表：`supabase/migrations/001_trips_spots.sql`（trips / trip_members / spots ＋ RLS。likes・routes はみんなで版で追加）
  - ログインしなくても今までどおり localStorage だけで動くこと。ページに書いてよいのは publishable key（anon key）だけ
  - 同期：localStorage が手元のコピー。変更は `cloudMark(id, "up"|"del")`／`cloudMarkTrip()` で印をつけ、`runSync()` が送る→受け取る（クラウドが正。未送信の変更だけ手元を優先）
  - 同期の帳面は localStorage `tabi-navi-sync`（userId・tripId・dirty・orphans など）。新しい場所の id は uuid。古い id はハッシュで決まった uuid に変える（端末がちがっても同じ id になる）
  - はじめてつないだ端末にクラウドにない場所があれば、自動で送らずに「追加しますか？」と聞く（ほかの端末で消した場所がよみがえらないように）
  - 旅のメモ（trip-memo）は trips.memo に保存。いまは1人1つの旅だけ使う
- 現在地：`navigator.geolocation`（HTTPS が必要）。住所への変換は OpenStreetMap Nominatim（失敗・4秒たっても返事がないときは緯度経度のまま続ける）
- Claude への受け渡し：`buildPrompt(kind)` でお願い文を作る → 「コピーしてClaudeを開く」をタップ
  - タップした瞬間にクリップボードへコピーする（iOS はタップ中しかコピーできない）
  - `https://claude.ai/new?q=...` を開く（入力欄に自動で入らない環境では貼り付けてもらう）
  - URL が `URL_MAX`（12000文字）を超えたら文は入れずに開き、貼り付けを案内する。日本語はURLで1文字9文字になるので、お願い文の決まった文章は短く保つ（現在地の地図リンクは入れない。場所の地図リンクは住所がなく短いときだけ）
- Googleマップのリンク読みこみ：「場所を追加」の URL 欄に貼ると、名前・住所・エリアを自動で入れる（空の欄だけ）
  - 長いURL（`google.com/maps?q=〒… 住所 名前` や `/maps/place/名前/`）はページの中だけで読み取る
  - 短縮リンク（`maps.app.goo.gl`）は Supabase Edge Function（ダッシュボード上の名前は `hyper-function`、コードは `supabase/functions/resolve-map/index.ts`）で長いURLに戻す。呼び先は `index.html` の `RESOLVER`（プロジェクト `cnnwxwiqauyawngkpapk`。空なら短縮リンクは読まない）
  - 営業時間・Webサイトは取らない（当日 Claude に調べてもらう）
- クイックボタン（次どこ行く？／近くでごはん／休けい／雨／遅れている／帰る）は、`SITUATION` の文をお願い文に足す
- 現在地が10分より古い、または未取得のときは、ルートを聞く前に取り直す
  - 取り直し中はボタンに「現在地を取得中…」と出して押せなくする。位置情報は10秒、住所変換（Nominatim）は4秒であきらめる
  - 取れなかったときは前の位置で作り、「○分前の位置で作りました」と知らせる。15分より古い位置はお願い文に「いまは移動しているかも」と書く

## デザインのきまり
- スマホ片手で使う1列レイアウト。下に固定の「ルートを聞く」バーがある
- 色はすべて `:root` の CSS 変数（トークン）で指定。ダークモードは `prefers-color-scheme` で切りかえる
- フォント：Zen Maru Gothic（見出し）、Zen Kaku Gothic New（本文）、IBM Plex Mono（時計）。Google Fonts から読みこむ
- 横スクロールを出さない（幅390pxで確認）。入力欄の文字は16px（iOSで勝手にズームしないように）
- 文言はやさしい日本語で書く。絵文字は使わない

## オーナーへの説明のしかた（大事）
- 小学校高学年〜中学生にもわかるように、やさしく説明する
- コードを直したときは、ところどころで専門用語をわかりやすく解説する（例：「localStorage＝ブラウザの中の小さなメモ帳」）
- オーナーはフォワーダー（国際物流）の仕事をしている。GitHub Pages・Supabase は別のプロジェクト（forwarder-support）で使ったことがある

## 確認のしかた
- `index.html` を Playwright などで幅390pxで開き、次の3つを確かめる
  1. 場所の追加・編集・削除・「行った」チェックができる
  2. 再読みこみしてもリストが残る
  3. お願い文が作られる（geolocation はテスト用の位置をわたす）
- コンソールエラーが出ないこと

## これからの候補（オーナーと相談して決める）
- 行きたい場所の並べかえ（ドラッグ）、日ごとのグループ分け
- Claude が返したルートを貼り付けて保存・表示する欄
- オフラインでも開けるようにする（Service Worker / PWA）
- 将来：ボタンだけでルートを出す（Supabase Edge Function ＋ Claude API。APIキーは絶対にページに書かない）
- 保留中：みんなで場所を集める版（Supabase：trips / spots / likes / routes ＋ 匿名ログイン ＋ RLS）。設計は別にあり、旅行後に再開予定
