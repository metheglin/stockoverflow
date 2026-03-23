# WORKLOG: コードベース精査による実装ギャップ分析

**作業日時:** 2026-03-22 16:00

**元TODO:** TODO_TYPE=THINK（プロンプト指示）

## 作業の概要

既存130件のTODOおよび過去23件のTHINKワークログを踏まえ、コードレベルの精査をおこない、まだ特定されていない具体的な実装課題を発見・TODO化した。

## 分析アプローチ

過去のTHINK分析は主に「機能・分析面のギャップ」（指標追加、スクリーニング機能、UI/API）に焦点を当てていた。今回は観点を変え、以下に注力した:

1. **データ型の正確性** - JSON属性の型変換が未実装
2. **データモデルの概念的正確性** - period_typeのセマンティクス
3. **パフォーマンスのボトルネック** - 大規模データ取り込みのスケーラビリティ
4. **計算の前提条件** - 株価調整係数の未活用
5. **データ整合性** - マルチソースデータのマージ時の情報損失

## 考えたこと

### プロジェクト現状の所感

- 既存TODOが130件と膨大。DEVELOP_pending が95件以上ある
- 分析系の高度な指標（Piotroski, Altman, DuPont, Magic Formula等）のTODOが多い
- 一方で、それらの基盤となるデータの正確性・型安全性に関する課題が見落とされている
- 「計算が正しい」前提で高度な指標を積み上げても、基盤のデータ品質が低ければ意味がない
- 今回は「高度な機能の追加」ではなく「既存基盤の堅牢化」に重点を置いた

### 発見した具体的課題

#### 1. JsonAttribute の型強制（type coercion）が未実装

`define_json_attributes` のスキーマで `type: :integer`, `type: :decimal` を指定しているが、getter はJSON値をそのまま返す。JQUANTSは数値を文字列として返すケースがあり、EDINETのXBRLパーサーは整数を返す。同一カラムに `"12345"` と `12345` が混在すると、比較演算やソートで予期しない挙動が発生する。

#### 2. Semi-annual（半期）の period_type マッピングが不正

`ImportEdinetDocumentsJob#determine_quarter` が半期報告書を `:q2` にマッピングしている。しかし証券取引法上の半期報告（中間期）と第2四半期累計報告は概念的に異なる。`FinancialReport` の `report_type` enum には `semi_annual: 4` が存在するが、`FinancialValue` と `FinancialMetric` の `period_type` enum にはこれが存在しない。

#### 3. Import Job のパフォーマンスボトルネック

全ジョブが `find_or_initialize_by` + `save` のN+1パターンで動作。上場企業4000社 × 日次株価250営業日/年 = 年間100万レコード。数年分の初期インポートで数百万レコードを処理する際、1レコードにつき2クエリ（SELECT + INSERT/UPDATE）が発行される。Rails の `upsert_all` への切り替えで桁違いの改善が見込める。

#### 4. DailyQuote の株価調整メソッドの欠如

`adjustment_factor` と `adjusted_close` はDBに保存されているが、調整済みの始値・高値・安値・出来高を計算するメソッドがない。`CalculateFinancialMetricsJob#load_stock_price` は `close_price` をそのまま使っており、株式分割前後で指標が不正確になるリスクがある。

#### 5. data_json マージ時の競合の無検出

`ImportJquantsFinancialDataJob` と `ImportEdinetDocumentsJob` の両方が `data_json` をマージするが、既存値と新規値が異なる場合に無条件で上書きされ、ログにも残らない。例えば JQUANTS の業績予想と EDINET の業績予想が異なる場合、どちらが正しいか判断する材料が失われる。

## 作成したTODO

| ファイル | TODO_TYPE | 概要 |
|---|---|---|
| `20260322_1600_dev_json_attribute_type_coercion_DEVELOP_pending.md` | DEVELOP | JsonAttribute の型強制実装 |
| `20260322_1601_dev_semi_annual_period_type_fix_DEVELOP_pending.md` | DEVELOP | 半期 period_type のenum追加・マッピング修正 |
| `20260322_1602_improve_bulk_upsert_import_performance_DEVELOP_pending.md` | DEVELOP | Import Jobのバルクupsert最適化 |
| `20260322_1603_dev_daily_quote_adjusted_price_methods_DEVELOP_pending.md` | DEVELOP | DailyQuote 株価調整計算メソッド追加 |
| `20260322_1604_dev_financial_value_data_json_merge_conflict_logging_DEVELOP_pending.md` | DEVELOP | data_json マージ競合検出・ログ出力 |

## 優先度の考え方

上記5件はすべて「基盤の堅牢化」に分類される。高度な分析指標を積み上げる前に解決すべき課題群であり、既存の95件のDEVELOP_pendingよりも優先度が高いと考える。

推奨実装順序:
1. JsonAttribute 型強制（すべてのJSON属性読み出しに影響）
2. Semi-annual period_type 修正（データモデルの正確性）
3. data_json マージ競合ログ（データ品質の可視化）
4. DailyQuote 調整済み価格メソッド（バリュエーション計算の正確性）
5. バルクupsert最適化（運用効率、ただしリファクタリング規模が大きい）
