# BUGFIX: SyncCompaniesJobのmark_unlistedがAPIのページネーション部分失敗で誤って上場廃止扱いにする

## 概要

`SyncCompaniesJob#mark_unlisted` は、JQUANTS API から取得した銘柄一覧に含まれない上場企業を `listed: false` に更新する。しかし API のページネーション処理が途中で失敗した場合、取得済み企業のみが `synced_codes` に含まれ、残りの企業が誤って上場廃止扱いになる。

## 背景・動機

### 現状のコード

```ruby
# SyncCompaniesJob#perform (L12-43)
def perform(api_key: nil)
  client = api_key ? JquantsApi.new(api_key: api_key) : JquantsApi.default
  listed_data = client.load_listed_info  # ページネーション自動処理

  synced_codes = []
  listed_data.each do |data|
    # ... 各銘柄をupsert ...
    synced_codes << code
  end

  mark_unlisted(synced_codes)  # synced_codesに含まれない企業をlisted=false
end
```

### JquantsApi#load_all_pages のページネーション

```ruby
# app/lib/jquants_api.rb L152-166
def load_all_pages(path, params = {})
  all_data = []
  loop do
    response = get(path, params)
    parsed = JSON.parse(response.body)
    data = parsed["data"] || []
    all_data.concat(data)
    pagination_key = parsed["pagination_key"]
    break if pagination_key.nil? || pagination_key.empty?
    params = params.merge(pagination_key: pagination_key)
  end
  all_data
end
```

### 障害シナリオ

1. JQUANTS API の `equities/master` は全上場企業（約4000社）を返す
2. ページネーションが2ページ目で 429 エラー（Faraday retry 3回失敗後に例外発生）
3. `load_listed_info` は例外を発生させず、1ページ目のデータ（例: 2000社）のみ返す
4. `synced_codes` には2000社のコードのみが入る
5. `mark_unlisted` が残り2000社を `listed: false` に更新
6. **上場中の2000社が誤って上場廃止扱いになる**

### 補足

- `synced_codes.empty?` の場合は `mark_unlisted` が early return するため、完全な API 失敗（0件返却）は安全
- 問題は部分的な失敗（一部の企業のみ取得できたケース）

## 実装方針

### 方針A: 取得数の妥当性チェック（推奨）

既存の上場企業数と取得数を比較し、大きな乖離がある場合は mark_unlisted をスキップする:

```ruby
def mark_unlisted(synced_codes)
  return if synced_codes.empty?

  current_listed_count = Company.listed.where.not(securities_code: nil).count
  # 取得数が既存の80%未満の場合、APIの部分失敗と判断してスキップ
  if current_listed_count > 0 && synced_codes.size < current_listed_count * 0.8
    Rails.logger.warn(
      "[SyncCompaniesJob] Skipping mark_unlisted: " \
      "fetched #{synced_codes.size} codes but #{current_listed_count} currently listed " \
      "(possible partial API failure)"
    )
    return
  end

  Company.listed
    .where.not(securities_code: synced_codes)
    .where.not(securities_code: nil)
    .update_all(listed: false)
end
```

### 方針B: load_all_pages にページ数チェックを追加

JquantsApi#load_all_pages が pagination_key の途中で例外をキャッチしている場合、`partial: true` フラグを返すようにする。

## テスト

- `mark_unlisted` に取得数チェックが入っていることの検証
  - 正常: 全件取得時は mark_unlisted が実行される
  - 異常: 取得数が著しく少ない場合はスキップされる
  - 境界: 初回同期（既存0件）では mark_unlisted が正常動作する

## 優先度

高。一度発生すると大量の企業が非上場扱いになり、全てのインポートジョブが対象外として処理をスキップする。復旧には再度 full sync が必要になるが、気付くまでに長期間データ欠損が蓄積する。
