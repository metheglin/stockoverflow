# 決算発表日カレンダーのインポート

## 概要

JquantsApiに既に実装済みの `load_earnings_calendar` エンドポイントを活用し、企業の決算発表日データをインポートする機能を実装する。決算発表前後の分析、データ更新タイミングの予測、アラート機能の基盤となる。

## 背景

- `JquantsApi#load_earnings_calendar` は既に実装されているが、これを利用するジョブ・モデルが存在しない
- 決算発表日は投資分析において非常に重要な情報であり、以下のユースケースがある:
  - 決算発表直前・直後の株価変動分析（`dev_earnings_price_reaction_analysis` と連携）
  - 今後いつ新しい財務データが利用可能になるかの予測
  - 決算発表シーズンにおけるデータ取り込みの優先順位付け
  - 「来週決算発表がある企業」の一覧表示

## 実装内容

### 1. earnings_calendarsテーブルの作成

```ruby
create_table :earnings_calendars do |t|
  t.references :company, null: false, foreign_key: true
  t.date :announcement_date, null: false         # 決算発表日
  t.integer :fiscal_year, null: false            # 対象決算年度
  t.integer :period_type, null: false, default: 0 # enum: annual/q1/q2/q3
  t.integer :announcement_type, default: 0       # enum: scheduled/actual/revised
  t.json :data_json                              # 追加情報格納用
  t.timestamps
end

add_index :earnings_calendars, [:company_id, :announcement_date], unique: true
add_index :earnings_calendars, :announcement_date
```

### 2. EarningsCalendarモデル

- `belongs_to :company`
- enum: `period_type`, `announcement_type`
- JQUANTSのフィールドマッピング
- `get_attributes_from_jquants(data)` クラスメソッド

### 3. ImportEarningsCalendarJob

- JQUANTS earnings calendar APIから決算発表日データをインポート
- インクリメンタル取り込み: 前回同期日からの差分
- フル取り込み: 全企業の決算発表日カレンダー

### 4. Company scope追加

```ruby
scope :upcoming_earnings, ->(days: 7) {
  joins(:earnings_calendars)
    .where(earnings_calendars: { announcement_date: Date.today..(Date.today + days.days) })
}
```

## テスト

- EarningsCalendarモデルの `get_attributes_from_jquants` メソッドのテスト
- ジョブの稼働テストは記述しない

## 依存関係

- `dev_earnings_price_reaction_analysis` (20260320_1703) との連携が想定される
- `dev_job_scheduling` (20260310_1402) でスケジュール対象に追加する必要あり
