# BUGFIX: jquants_sync の ApplicationProperty が3つのジョブで共有されている問題の修正

## 概要

`SyncCompaniesJob`、`ImportDailyQuotesJob`、`ImportJquantsFinancialDataJob` の3つのジョブが同一の `ApplicationProperty(kind: :jquants_sync)` レコードを読み書きしている。これにより、各ジョブの `last_synced_date` が相互に上書きされ、インクリメンタル同期の開始日が不正になる。

## 背景・動機

### 現状の問題

3つのジョブが同じ `kind: :jquants_sync` を共有:

```ruby
# SyncCompaniesJob#record_sync_time (L60)
prop = ApplicationProperty.find_or_create_by!(kind: :jquants_sync)
prop.last_synced_at = Time.current.iso8601  # 時刻を書き込み

# ImportDailyQuotesJob#get_last_synced_date (L113) / record_sync_date (L123)
prop = ApplicationProperty.find_by(kind: :jquants_sync)
# last_synced_date を読み書き

# ImportJquantsFinancialDataJob#get_last_synced_date (L168) / record_sync_date (L181)
prop = ApplicationProperty.find_by(kind: :jquants_sync)
# last_synced_date を読み書き
```

### 具体的な障害シナリオ

1. `ImportDailyQuotesJob` が 2026-03-20 まで株価を取り込み、`last_synced_date = "2026-03-20"` を記録
2. `ImportJquantsFinancialDataJob` を実行すると、`get_last_synced_date` で `"2026-03-20"` を読み取る
3. 実際には財務データの最終同期は 2026-03-10 なのに、2026-03-20 から開始してしまう
4. **2026-03-10〜03-19 に開示された財務データが永久に取り込まれない**

逆のケースも発生する: 財務データジョブが古い日付で `last_synced_date` を上書きすると、株価ジョブが既に取り込んだ日付から再度取得を開始し、不要なAPI呼び出しが発生する。

## 実装方針

### 1. ApplicationProperty の kind enum を拡張

```ruby
# app/models/application_property.rb
enum :kind, {
  default: 0,
  edinet_sync: 1,
  jquants_sync: 2,            # 既存（廃止候補）
  data_integrity: 3,
  jquants_company_sync: 4,    # 新規: SyncCompaniesJob 用
  jquants_quote_sync: 5,      # 新規: ImportDailyQuotesJob 用
  jquants_financial_sync: 6,  # 新規: ImportJquantsFinancialDataJob 用
}
```

### 2. 各ジョブの kind を分離

- `SyncCompaniesJob` → `kind: :jquants_company_sync`
- `ImportDailyQuotesJob` → `kind: :jquants_quote_sync`
- `ImportJquantsFinancialDataJob` → `kind: :jquants_financial_sync`

### 3. DataIntegrityCheckJob の check_sync_freshness を更新

```ruby
[:edinet_sync, :jquants_company_sync, :jquants_quote_sync, :jquants_financial_sync].each do |kind|
  # ...
end
```

### 4. マイグレーション

既存の `jquants_sync` レコードが存在する場合、データを3つのレコードに分割するマイグレーション or seed を用意する。

## テスト

- DataIntegrityCheckJob の sync_freshness テストを更新（新しい kind に対応）
- 各ジョブが独立した kind を使用していることの確認

## 優先度

高。データ取り込みの正確性に直結する。複数ジョブを運用する際に、同期日が上書きされてデータ欠損が発生するリスクがある。
