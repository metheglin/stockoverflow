# BUGFIX: EDINET四半期報告書のfiscal_year_endがperiodEndを使用しておりJQUANTSと不整合

## 概要

`ImportEdinetDocumentsJob` は四半期報告書（Q1/Q2/Q3）の `fiscal_year_end` に EDINET API の `periodEnd`（四半期末日）を使用している。一方、`ImportJquantsFinancialDataJob` は `CurFYEn`（実際の決算期末日）を使用する。この不整合により、EDINET の四半期データが JQUANTS の四半期データを補完できず、重複レコードが生成される。

## 背景・動機

### 現状のコード

```ruby
# ImportEdinetDocumentsJob#process_document (L127)
fiscal_year_end = parse_date(doc["periodEnd"])  # 四半期末日を使用

# ImportJquantsFinancialDataJob#import_statement (L93)
fiscal_year_end = parse_date(data["CurFYEn"])   # 決算期末日を使用
```

### 具体例: 3月決算企業のQ1報告書

- **EDINET**: periodStart=2024-04-01, periodEnd=2024-06-30
  - → `fiscal_year_end = 2024-06-30`, `period_type = :q1`
- **JQUANTS**: CurFYEn=2025-03-31, CurPerType=1Q
  - → `fiscal_year_end = 2025-03-31`, `period_type = :q1`

### FinancialValue のユニークキー

`(company_id, fiscal_year_end, scope, period_type)` で一意制約がある。

- JQUANTS Q1: `(company_id, 2025-03-31, :consolidated, :q1)`
- EDINET Q1: `(company_id, 2024-06-30, :consolidated, :q1)`

**キーが一致しないため、upsert_financial_value で既存レコードが見つからず、新しいレコードが作成される。**

### 影響

1. **データ補完の失敗**: EDINET の拡張データ（shareholders_equity, cost_of_sales 等）が JQUANTS レコードに反映されない
2. **重複レコード**: 同一企業・同一期間の FinancialValue が2件存在する（fiscal_year_end が異なるだけ）
3. **メトリクス算出の混乱**: CalculateFinancialMetricsJob が両方のレコードに対してメトリクスを算出する
4. **スクリーニング結果の重複**: 同一企業が異なる fiscal_year_end で複数回表示される

## 実装方針

### 方針A: EDINET側でfiscal_year_endを正しく推定する（推奨）

EDINET の periodStart/periodEnd から決算期末日を推定する:

```ruby
def estimate_fiscal_year_end(doc, report_type)
  period_end = parse_date(doc["periodEnd"])
  return period_end if report_type == :annual || report_type == :semi_annual

  # 四半期の場合: 決算期末日を推定
  # periodStart から12ヶ月後の前月末 = 決算期末日
  period_start = parse_date(doc["periodStart"])
  return period_end unless period_start

  # 会計年度開始月から12ヶ月後を算出
  fiscal_year_end_month = period_start + 12.months - 1.day
  fiscal_year_end_month.end_of_month
end
```

例:
- periodStart=2024-04-01 → 2024-04-01 + 12months - 1day = 2025-03-31 → end_of_month = 2025-03-31

### 方針B: 既存JQUANTSレコードとのマッチングを拡張する

upsert_financial_value で fiscal_year_end の完全一致ではなく、company_id + scope + period_type で既存レコードを探し、fiscal_year_end の近似マッチングをおこなう。ただし誤マッチのリスクがあるため方針Aを推奨。

## テスト

- `estimate_fiscal_year_end` メソッドのテスト
  - 3月決算企業のQ1/Q2/Q3
  - 12月決算企業のQ1/Q2/Q3
  - 通期は periodEnd をそのまま返す
  - periodStart が nil の場合のフォールバック

## 優先度

高。四半期データの EDINET→JQUANTS 補完が完全に機能していない。shareholders_equity（ROE計算に必要）をはじめとする EDINET 拡張データが四半期レコードに反映されない。
