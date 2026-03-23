# 決算期変更時のメトリクス計算ハンドリング

## 背景・課題

`CalculateFinancialMetricsJob#find_previous_financial_value` は、`fiscal_year_end` の約1年前（±1ヶ月: 11〜13ヶ月前）の範囲で前期データを検索している。

```ruby
prev_start = fv.fiscal_year_end - 13.months
prev_end = fv.fiscal_year_end - 11.months
```

日本の上場企業は決算期変更（例: 3月決算→12月決算）を行うケースがある。決算期変更が発生すると:

1. **前期データが検索範囲外になる**: 3月決算→12月決算に変更した場合、前期(2025年3月)と当期(2025年12月)の差は9ヶ月しかなく、11〜13ヶ月の検索窓に入らない
2. **YoY指標がnilになる**: revenue_yoy等が全てnilとなり、成長性の追跡が途切れる
3. **連続増収増益カウントが不正にリセットされる**: 実際には増収が続いていても、前期が見つからないためconsecutive_revenue_growthが0にリセットされる
4. **変則決算期間の比較**: 決算期変更年度は12ヶ月未満の変則期間となることが多く、単純なYoY比較が不適切になる

## 対応方針

### 1. 前期データ検索ロジックの拡張

`find_previous_financial_value` を改修し、±1ヶ月で見つからない場合に拡大検索を行う:

- まず通常の11〜13ヶ月前を検索
- 見つからない場合、同一company_id・scope・period_typeで `fiscal_year_end < current` の最新レコードを1件取得
- ただし24ヶ月以上古いデータは除外する

### 2. 決算期変更フラグの付与

`FinancialValue` または `FinancialMetric` の `data_json` に `fiscal_year_changed: true` フラグを設定:

- 前期の fiscal_year_end との月差が 10ヶ月以下 or 14ヶ月以上の場合にフラグを立てる
- `period_months` （当該期間の月数）も記録し、12ヶ月未満の変則期間を識別可能にする

### 3. 変則期間のYoY計算への注意付記

- 決算期変更年度のYoY指標には `data_json` に `yoy_unreliable: true` を付与し、スクリーニング時にフィルタリング可能にする
- 連続増収増益のカウントについて、変則期間をどう扱うか（カウントしない/条件付きカウント）のルールを定める

## テスト観点

- FinancialMetricモデルの計算メソッドに対するテスト（DBアクセス不要部分）
- 決算期変更ケースのfiscal_year_endサンプルデータを用いたユニットテスト
- `fiscal_year_changed` フラグ判定ロジックのテスト

## 関連TODO

- `20260322_0900_dev_fiscal_period_continuity_verification`: 決算期の連続性検証（欠損期間の検出）。本TODOは「期間は存在するが前期との間隔が異なる」ケースを扱う
- `20260322_0904_dev_financial_report_period_months_tracking`: period_monthsの追跡。本TODOで記録するperiod_monthsと連携可能
