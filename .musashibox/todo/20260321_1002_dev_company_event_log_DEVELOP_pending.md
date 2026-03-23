# 企業イベントログ統合テーブル

## 概要

企業に関するあらゆるイベント（決算発表、指標閾値突破、連続成長マイルストーン、データ取り込み等）を統一的に記録するテーブルとロギング機構を実装する。

## 背景・動機

- 既存のTODOには個別のイベント検出（financial_event_detection）やライフサイクル追跡（company_lifecycle_tracking）が計画されているが、検出されたイベントを永続化する統一ストレージが未定義
- アラートダイジェスト（investor_alert_digest）、企業タイムライン（company_financial_timeline_view）、スクリーニング状態変化検出（screening_state_change_detection）など複数の下流機能がイベントデータを必要とする
- 統一ログにすることで、「この企業に最近何が起きたか」を1テーブルで把握可能になる

## 実装方針

### テーブル設計 (EAVパターン活用)

```
company_events テーブル
- id
- company_id (integer, FK, index)
- kind (integer, enum)
- occurred_on (date, index) - イベントの発生日
- primary_value (string, nullable) - 検索に使う主値
- status (integer, enum: disabled=0, enabled=1)
- data_json (json) - イベント詳細
- timestamps
- index: (company_id, kind, occurred_on)
```

### kind enum 定義

```ruby
enum :kind, {
  financial_report_submitted: 1,   # 決算書提出
  metric_threshold_crossed: 2,     # 指標が閾値を超えた
  consecutive_growth_milestone: 3, # 連続成長の節目達成
  cash_flow_turnaround: 4,         # FCF転換
  valuation_change: 5,             # バリュエーション大幅変動
  stock_price_movement: 6,         # 株価の大幅変動
  listing_change: 7,               # 上場・上場廃止
  corporate_action: 8,             # 株式分割等
  data_import: 9,                  # データ取り込み完了
}
```

### ロギングインターフェース

```ruby
class CompanyEvent
  class << self
    def log(company:, kind:, occurred_on:, primary_value: nil, data: {})
      create!(
        company: company,
        kind: kind,
        occurred_on: occurred_on,
        primary_value: primary_value,
        data_json: data,
      )
    end
  end
end
```

### 各ジョブへの組み込み

- `ImportJquantsFinancialDataJob`: 新規決算データ取り込み時に `financial_report_submitted` を記録
- `CalculateFinancialMetricsJob`: 連続成長カウンター更新時にマイルストーンイベントを記録
- 今後追加されるイベント検出系機能から `metric_threshold_crossed` 等を記録

## 備考

- data_json には JsonAttribute concern を適用し、kind ごとにスキーマを定義
- STI または default_scope で kind ごとのサブクラスも検討
- 大量のイベントが蓄積されることを想定し、occurred_on へのインデックスを重視
