# DCF法による理論株価(本質的価値)推定

## 概要

オーナー利益（Owner Earnings）を基にしたDCF（割引キャッシュフロー）モデルを実装し、各企業の理論株価を推定する。現在の株価と比較して割安度（Margin of Safety）を算出する。

バリュー投資の根幹となる分析手法であり、既存のバリュエーション指標（PER, PBR, PSR）を補完する本質的な価値評価を提供する。

## 実装内容

### FinancialMetric の data_json に追加する項目

- `owner_earnings`: オーナー利益 = 純利益 + 減価償却費 - 設備投資（investing_cfの近似）
- `intrinsic_value_per_share`: 1株当たり理論株価（DCFモデルベース）
- `margin_of_safety`: 安全余裕率 = (理論株価 - 現在株価) / 理論株価
- `discount_rate`: 適用した割引率（デフォルト10%）
- `terminal_growth_rate`: 永久成長率（デフォルト2%）

### 計算ロジック

1. **オーナー利益の算出**
   - `owner_earnings = net_income + (operating_cf - net_income)` （減価償却の近似）
   - operating_cfが取得できない場合は `net_income * 0.8` を簡易代替

2. **DCFモデル**
   - 予測期間: 10年
   - 成長率: 直近のrevenue_yoyを基に逓減モデルを適用（初年度は実績YoY、最終年度は永久成長率に収束）
   - ターミナルバリュー: Gordon Growth Model
   - 割引率: デフォルト10%（将来的にWACC推定に拡張可能）

3. **1株当たり理論株価**
   - DCF合計値 / 発行済株式数

4. **安全余裕率**
   - daily_quotesから直近の株価を取得して算出

### CalculateFinancialMetricsJob への統合

- 既存のバリュエーション指標計算の後に追加
- financial_valueにoperating_cfとnet_incomeが存在し、daily_quotesで株価が取得できる場合のみ計算

### テスト

- FinancialMetric specに以下を追加:
  - `get_owner_earnings()` の計算テスト
  - `get_intrinsic_value()` のDCFモデルテスト（既知の入力に対する期待出力の検証）
  - `get_margin_of_safety()` の安全余裕率テスト
  - エッジケース: 赤字企業、成長率が異常に高い/低い場合

## 備考

- 既存TODOのバリュエーション系指標（PER, PBR, PSR, PEG, EV/EBITDA）は相対的な割安/割高を示すが、本機能は絶対的な価値評価を提供する
- 将来的にはβ値やWACCの推定、複数シナリオの感度分析に拡張可能
