# TODO: 日次バリュエーション指標の時系列追跡

## 概要

DailyQuoteに蓄積された日次株価とFinancialValueの直近決算データを組み合わせ、日次でPER・PBR・PSR・時価総額を算出・蓄積する仕組みを構築する。

## 背景・課題

現在、PER/PBR/PSRなどのバリュエーション指標は `CalculateFinancialMetricsJob` にて決算日前後の株価1点でのみ算出されている（FinancialMetric.data_json に格納）。しかし、これではバリュエーション指標の「推移」が追えない。

プロジェクト目標の「ある企業の業績が飛躍し始める直前にどのような変化があったかを調べる」ユースケースにおいて、「飛躍前にバリュエーションが割安だった期間」や「市場の評価（PER水準）がいつ変わり始めたか」を把握するには、日次でのバリュエーション追跡が不可欠。

また、時価総額（close_price x shares_outstanding）は多くの分析の基盤となる重要な指標だが、現在はget_valuation_metricsとget_ev_ebitda内でインラインに算出されるのみで、永続化されていない。

## 実装方針

### 新テーブル: daily_valuations

```
daily_valuations
  - company_id (FK, not null)
  - traded_on (date, not null)
  - market_cap (bigint) -- 時価総額 = adjusted_close * shares_outstanding
  - per (decimal 10,4) -- 株価 / EPS
  - pbr (decimal 10,4) -- 株価 / BPS
  - psr (decimal 10,4) -- 時価総額 / 売上高
  - dividend_yield (decimal 10,4) -- 配当利回り
  - data_json (json) -- ev_ebitda等の拡張用
  - unique index: [company_id, traded_on]
  - index: [traded_on]
```

### 新ジョブ: CalculateDailyValuationsJob

- 各上場企業について、DailyQuoteの各日の株価と、その時点で直近確定の FinancialValue を紐付けてバリュエーション指標を算出
- 直近のFinancialValueの特定: その日以前でfiscal_year_endが最も近いannualデータを使用
- インクリメンタル処理: 前回計算日以降のDailyQuoteに対してのみ計算
- フル再計算オプション: `recalculate: true` で全期間再計算

### 新モデル: DailyValuation

- DailyQuoteとFinancialValueを参照し、日次でのバリュエーション指標を提供
- `self.get_attributes(daily_quote, financial_value)` クラスメソッドで算出ロジックを集約

## テスト

- DailyValuationモデルの算出ロジック（get_attributes）のユニットテスト
  - 正常系: 各指標の正しい算出
  - エッジケース: EPS=0（PER算出不可）、BPS=0、shares_outstanding=nil 等

## 依存関係

- 既存のDailyQuote, FinancialValue, Companyモデルに依存
- dev_job_scheduling完了後にスケジュール登録が望ましい
