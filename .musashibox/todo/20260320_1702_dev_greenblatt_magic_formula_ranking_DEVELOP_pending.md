# Greenblatt Magic Formula ランキングシステム

## 概要

Joel Greenblattの「Magic Formula」投資戦略に基づくランキングシステムを実装する。益回り（Earnings Yield）とROIC（投下資本利益率）の2軸で全上場企業をランキングし、両方のランキングが高い（＝割安かつ高収益な）企業を発見する。

## 背景

- 既存TODOでROIC（20260320_1401）は計画されているが、Magic Formulaとしての統合ランキングは未定義
- PEG ratio（20260320_1504）は成長性考慮の割安度を測るが、Magic Formulaは収益性+割安度の組み合わせ
- スクリーニングのユースケース「注目すべき企業を一覧できる」に直結する機能

## 実装内容

### 新規モデル or 既存モデル拡張

FinancialMetric の data_json に追加:

- `earnings_yield`: 益回り = EBIT / Enterprise Value
- `magic_formula_ey_rank`: 益回りランキング順位（全上場企業中）
- `magic_formula_roic_rank`: ROICランキング順位（全上場企業中）
- `magic_formula_combined_rank`: 合計ランキング = ey_rank + roic_rank（小さいほど良い）

### 計算ロジック

1. **益回り（Earnings Yield）**
   - `EBIT = operating_income`
   - `Enterprise Value = 時価総額 + 有利子負債 - 現金等価物`
   - `EY = EBIT / EV`
   - 有利子負債が不明な場合: `EV = 時価総額 + (total_assets - net_assets) - cash_and_equivalents` で近似

2. **ROIC**
   - `ROIC = NOPAT / Invested Capital`
   - `NOPAT = operating_income * (1 - 実効税率)` ※実効税率はデフォルト30%
   - `Invested Capital = total_assets - current_liabilities - cash_and_equivalents`
   - current_liabilitiesが不明な場合は算出不可

3. **ランキング**
   - 全上場企業の直近年度データを対象
   - 金融セクター（銀行・保険・証券）は除外（資本構造が特殊なため）
   - EYとROICそれぞれで降順ランク付け
   - combined_rank = ey_rank + roic_rank

### 実装方針

- ランキング計算は全企業を対象とするバッチ処理として実装
- `CalculateFinancialMetricsJob` の後に実行する新規ジョブ、またはCalculateFinancialMetricsJobの最終ステップとして実装
- ランキングは直近の年度決算データに基づく

### テスト

- `get_earnings_yield()` の計算テスト
- `get_magic_formula_roic()` の計算テスト
- ランキング計算のテスト（小規模データセットで順位付けの正確性を検証）
- 金融セクター除外の検証

## 備考

- 「ウォール街のランダム・ウォーカー」的な定量スクリーニング戦略の実装第一弾
- 将来的にはバックテスト（20260320_1603）と組み合わせて、過去のMagic Formula上位銘柄のパフォーマンス検証が可能
