# DEVELOP: EDINET同期カーソルが失敗日付をスキップする問題の修正

## 概要

ImportEdinetDocumentsJob は処理結果に関わらず `end_date` を同期カーソルとして記録するため、途中の日付で失敗が発生しても次回のインクリメンタル取り込みでリトライされない。ImportJquantsFinancialDataJob が採用している `@last_successful_date` パターンに統一する。

## 背景・動機

### 現状の問題

ImportEdinetDocumentsJob#perform（L27-33）:

```ruby
(start_date..end_date).each do |date|
  process_date(date)                        # 例外はrescue内で吸収される
  sleep(SLEEP_BETWEEN_DAYS) if date < end_date
end

record_sync_date(end_date)                  # 常に end_date を記録
```

`process_date` 内のエラーは rescue ブロックで吸収され、`@stats[:errors]` に計上されるのみ。その後のループは続行し、最終的に `end_date` がそのまま同期カーソルとして記録される。

### 具体例

- from_date: 2026-03-01, to_date: 2026-03-20 で実行
- 2026-03-10 のAPI呼び出しでネットワークエラーが発生
- 2026-03-10 の書類は取り込まれない
- end_date = 2026-03-20 が記録される
- 次回のインクリメンタル実行は 2026-03-20 以降から開始
- **2026-03-10 のデータは永久に取り込まれない**

### 対比: ImportJquantsFinancialDataJob

こちらは `@last_successful_date` を追跡し、ensure ブロックで最後に成功した日付を記録する適切な実装となっている（L52-66）。

## 実装方針

```ruby
def perform(from_date: nil, to_date: nil, api_key: nil)
  @client = api_key ? EdinetApi.new(api_key: api_key) : EdinetApi.default
  @stats = { processed: 0, supplemented: 0, created: 0, skipped: 0, errors: 0 }
  @last_successful_date = nil

  start_date = from_date ? Date.parse(from_date) : get_last_synced_date
  end_date = to_date ? Date.parse(to_date) : Date.yesterday

  (start_date..end_date).each do |date|
    process_date(date)
    @last_successful_date = date  # process_date内でrescueしているため、ここに到達=日付単位では処理完了
    sleep(SLEEP_BETWEEN_DAYS) if date < end_date
  end
ensure
  record_sync_date(@last_successful_date) if @last_successful_date
  log_result
end
```

### 注意点

- `process_date` はドキュメント単位のエラーを吸収しつつ、日付リスト取得自体のエラーも rescue する
- 日付リスト取得に失敗した場合は `@last_successful_date` が更新されないため、前日の日付がカーソルになる
- これにより最悪でも「1日分のデータ欠損」で留まる

## 優先度

高。データ取り込みの信頼性に直結する。現状では一度の障害で特定日のデータが永久欠損する。
