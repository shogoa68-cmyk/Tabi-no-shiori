# Tabi-no-shiori（いまから旅ナビ）

## これは何？
1人で使う、旅行中のルート相談アプリ。
スマホで開き、現在地と現在時刻、事前に登録した「行きたい場所リスト」から、Claudeへのお願い文（プロンプト）を作る。
それを Claude アプリに渡すと、Claude が Web 検索で営業時間や電車を調べ、最適なルートを返す。

- 公開URL：https://shogoa68-cmyk.github.io/Tabi-no-shiori/
- 公開方法：GitHub Pages（main ブランチ / root）。push すると1〜2分で反映される
- 利用者：オーナー1人（スマホ、iPhone想定）
- **旅行本番が近い。** 大きな作り直しより、確実に動く小さな改善を優先する

## しくみ
- ファイルは `index.html` の1枚だけ（HTML・CSS・JS をすべてこの中に書く。ビルドなし・ライブラリなし）
- 保存先：`localStorage`（キー `tabi-navi-v1`）。端末のブラウザの中だけに保存
  - 形：`{ spots: [...], here: {lat,lng,acc,at,address} | null, settings: {要素id: 値} }`
  - spot：`{ id, name, prio(1-3), area, stay(分|null), hours, closed, kind, when, map, memo, done, created }`
  - **データの形を変えるときは、古いデータも読めるようにすること**（オーナーのリストが消えないように）
- 現在地：`navigator.geolocation`（HTTPS が必要）。住所への変換は OpenStreetMap Nominatim（失敗したら緯度経度のまま続ける）
- Claude への受け渡し：`buildPrompt(kind)` でお願い文を作る → 「コピーしてClaudeを開く」をタップ
  - タップした瞬間にクリップボードへコピーする（iOS はタップ中しかコピーできない）
  - `https://claude.ai/new?q=...` を開く（入力欄に自動で入らない環境では貼り付けてもらう）
- クイックボタン（次どこ行く？／近くでごはん／休けい／雨／遅れている／帰る）は、`SITUATION` の文をお願い文に足す
- 現在地が10分より古い、または未取得のときは、ルートを聞く前に取り直す

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
