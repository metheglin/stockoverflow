# WORKLOG: bugfix_dashboard_search2

作業日時: 2026-04-01

## 作業概要

WEBダッシュボードの検索で、検索条件を変更して再検索しても結果が更新されないバグを修正した。

## 原因

`app/views/dashboard/search/execute.turbo_stream.erb` で `turbo_stream.replace "search_results"` を使用していた。

Turbo Streamの `replace` アクションは、対象のDOM要素(id="search_results" の `<turbo-frame>`)を **要素ごと** 新しいコンテンツで置換する。初回検索後、`<turbo-frame id="search_results">` は `<div class="section-card" data-controller="result-table">` に完全に置き換えられ、`id="search_results"` を持つ要素がDOMから消失する。

そのため、2回目以降の検索では `turbo_stream.replace` のターゲット (`id="search_results"`) が見つからず、Turbo Streamの差し替えがサイレントに失敗していた。ブラウザリロードすると `<turbo-frame id="search_results">` が再描画されるため、再度1回だけ検索が成功する、という挙動になっていた。

## 修正内容

- `app/views/dashboard/search/execute.turbo_stream.erb`
  - `turbo_stream.replace` を `turbo_stream.update` に変更
  - `update` はターゲット要素の **内側のコンテンツのみ** を置換し、ターゲット要素自体(`<turbo-frame id="search_results">`)は保持する
  - これにより、何度検索を実行しても常にターゲット要素が存在し、正常に結果が更新される

## テスト

- RSpec全478テスト通過(0 failures, 5 pending: API key未設定のもの)
