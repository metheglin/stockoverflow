# WORKLOG: THINK分析 - 2026-03-22

作業日時: 2026-03-22 18:00 JST

## 作業概要

プロジェクト全体のコードベース・既存TODO・テストカバレッジを精査し、未対応の課題・改善点を特定して5件の新規TODOを作成した。

## 調査内容

### 調査対象

- **モデル**: Company, FinancialReport, FinancialValue, FinancialMetric, DailyQuote, ApplicationProperty, JsonAttribute concern
- **ジョブ**: SyncCompaniesJob, ImportDailyQuotesJob, ImportJquantsFinancialDataJob, ImportEdinetDocumentsJob, CalculateFinancialMetricsJob, DataIntegrityCheckJob
- **ライブラリ**: EdinetApi, JquantsApi, EdinetXbrlParser
- **テスト**: 全10 specファイル（モデル6、ジョブ1、ライブラリ3）
- **既存TODO**: 約90件以上のTODOファイル（pending/done混在）
- **マイグレーション・スキーマ**: 全6テーブルの構造

### 発見した主要な課題

1. **ROE計算の不正確性**: `FinancialMetric.get_profitability_metrics` で ROE の分母に `net_assets`（純資産）を使用。日本会計基準では純資産 ≠ 株主資本であり、非支配株主持分・新株予約権が含まれるため ROE が過小評価される。`shareholders_equity` は EDINET XBRL 経由で `data_json` に格納されている。

2. **日次株価データのギャップ検出不在**: `DataIntegrityCheckJob` は直近7日のデータ有無のみチェック。中間期間のギャップ（API障害やインポートエラーによる欠落）を検出する仕組みがない。バリュエーション算出の精度に影響。

3. **市場休日カレンダーの不在**: 祝日にAPIコールを実行する無駄、ギャップ検出での祝日誤検出、株価検索での最適取引日特定不能など、複数の問題の根本原因。

4. **メトリクス計算のトレーサビリティ不足**: 算出されたメトリクスが何のデータに基づいているか（株価、前期データ、計算日時）の記録がなく、不正確な値のデバッグが困難。

5. **EBITDA算出の簡易版問題**: 減価償却費データが未抽出のため、EBITDA = 営業利益という簡易式を使用。設備投資が大きい製造業などで EV/EBITDA が不正確。EDINET XBRL からの抽出が可能。

### 既存TODOとの重複確認

以下の既存TODOとの重複がないことを確認:
- ROE修正は `20260322_1502_dev_financial_report_association_fix` とは別の問題
- ギャップ検出は `20260319_1503_improve_data_coverage_analysis` とは粒度が異なる（企業レベル vs 日次レベル）
- 減価償却費抽出は `20260319_1504_plan_edinet_xbrl_enrichment` で言及されているが具体的な実装仕様は未定義
- プロバナンスは `20260320_1804_plan_financial_data_revision_history` とは目的が異なる（入力追跡 vs 変更履歴）

## 成果物

以下5件のTODOファイルを作成:

| ファイル | 種別 | 内容 |
|---------|------|------|
| `20260322_1800_bugfix_roe_shareholders_equity_DEVELOP_pending.md` | bugfix | ROEの分母をshareholders_equityに修正 |
| `20260322_1801_dev_daily_quote_gap_detection_DEVELOP_pending.md` | dev | 日次株価データのギャップ検出機能 |
| `20260322_1802_dev_market_holiday_calendar_DEVELOP_pending.md` | dev | 日本市場休日カレンダーの実装 |
| `20260322_1803_improve_metric_calculation_provenance_DEVELOP_pending.md` | improve | メトリクス計算の入力データ記録 |
| `20260322_1804_dev_depreciation_extraction_accurate_ebitda_DEVELOP_pending.md` | dev | 減価償却費抽出と正確なEBITDA算出 |

## 考えたこと

- ROEバグはデータ精度に直結する重要な修正。特に子会社を多く持つ大企業で影響が大きい。
- 市場休日カレンダーは基盤的な機能であり、ギャップ検出やインポート最適化など複数の機能の前提条件となる。先に実装することで後続の開発が効率化される。
- 減価償却費の抽出は EBITDA 以外にも将来的に ROA の改善（ROIC 算出時の NOPAT 計算等）にも活用できる。
- プロバナンスの記録はオーバーヘッドが小さく（data_json への数フィールド追加のみ）、デバッグ時の価値が非常に高い。
