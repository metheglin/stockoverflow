# Efficiency / Turnover Metrics（効率性指標）

## 概要

FinancialMetricに資産効率性を示す指標を追加する。
ROEやROAは実装済みだが、それらを構成するより詳細な効率性指標（回転率系）が不足している。
DuPont分析やCCC分析の基礎となる指標群を実装する。

## 背景

- FinancialValueには `total_assets`, `net_assets`, `net_sales` が固定カラムとして存在
- `total_assets` と `net_sales` の組み合わせで総資産回転率が計算可能
- より高度な回転率（売上債権回転率、棚卸資産回転率）はEDINET XBRLの詳細データが必要だが、現状data_jsonにこれらの項目がない
- まずは計算可能な指標から実装し、将来のXBRL拡張に備える

## 実装する指標

### FinancialMetric.data_json への追加フィールド

1. **total_asset_turnover** (総資産回転率)
   - 計算: net_sales / total_assets
   - 意味: 資産をどれだけ効率的に売上に変換しているか

2. **equity_turnover** (自己資本回転率)
   - 計算: net_sales / net_assets
   - 意味: 自己資本の活用効率

3. **operating_cf_to_sales** (営業CF対売上高比率)
   - 計算: operating_cf / net_sales
   - 意味: 売上のうちどれだけが営業キャッシュフローとして残っているか。利益の質の指標

4. **operating_cf_to_assets** (営業CF対総資産比率)
   - 計算: operating_cf / total_assets
   - 意味: 資産からどれだけ現金を生み出しているか

5. **capex_to_operating_cf** (設備投資対営業CF比率)
   - 計算: abs(investing_cf) / operating_cf （operating_cfが正の場合のみ）
   - 意味: 営業CFのうちどれだけを設備投資に回しているか

## 技術的注意点

- CalculateFinancialMetricsJob 内で計算
- data_json のスキーマ定義に新フィールドを追加
- ゼロ除算の安全な処理（既存の safe_divide パターンに従う）
- テストは FinancialMetric のメソッド単位で記述
