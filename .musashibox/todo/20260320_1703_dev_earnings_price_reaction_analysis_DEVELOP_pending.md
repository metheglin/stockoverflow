# 決算発表前後の株価反応分析

## 概要

決算発表日（financial_report.disclosed_at）前後の株価変動を分析し、市場の反応パターンを定量化する。決算サプライズ（既存のsurprise指標）と株価反応を紐づけ、市場が決算をどう評価したかを可視化する。

## 背景

- daily_quotesに日次株価データ、financial_reportにdisclosed_at（開示日）が存在するが、両者を組み合わせた分析機能がない
- 既存のearnings_surprise指標（予想vs実績の乖離）は財務上のサプライズだが、市場がそれをどう評価したか（株価反応）は未分析
- ユースケース「飛躍し始める直前の変化を調べる」において、株価反応パターンは重要なシグナル

## 実装内容

### FinancialMetric の data_json に追加する項目

- `earnings_reaction`: 決算発表後の株価反応データ
  - `reaction_1d`: 発表翌日のリターン（%）
  - `reaction_3d`: 発表後3営業日のリターン（%）
  - `reaction_5d`: 発表後5営業日のリターン（%）
  - `pre_announcement_5d`: 発表前5営業日のリターン（%）（事前織り込み度）
  - `volume_ratio`: 発表翌日の出来高 / 直近20日平均出来高（出来高サプライズ）
  - `gap_direction`: "positive" / "negative" / "neutral"（±1%閾値）

### 計算ロジック

1. **決算発表日の特定**
   - `financial_report.disclosed_at` を基準日とする
   - disclosed_atが存在しない場合はスキップ

2. **基準株価の取得**
   - 発表日前営業日のclose_priceを基準価格とする
   - 発表日が休日の場合は直前の営業日を使用

3. **リターン計算**
   - N日後リターン = (N日後close_price - 基準価格) / 基準価格
   - 営業日ベースでカウント（daily_quotesにデータがある日のみ）

4. **出来高比率**
   - 発表翌日volume / 直近20営業日の平均volume

### 実装方針

- CalculateFinancialMetricsJob のバリュエーション計算と同じタイミングで実行
- financial_reportとdaily_quotesの両方にデータが揃っている場合のみ計算
- DailyQuoteモデルに `load_around_date(company_id:, date:, range:)` のようなヘルパーメソッドを追加

### テスト

- リターン計算のテスト（既知の株価データからの期待値検証）
- 休日・欠損データへの対応テスト
- 出来高比率の計算テスト
- disclosed_atが存在しない場合のスキップ確認

## 備考

- サプライズ指標と株価反応の組み合わせにより「ポジティブサプライズなのに株価下落（期待織り込み済み）」等の分析が可能
- 飛躍直前パターン分析（20260320_1404）のインプットデータとしても活用できる
