# WORKLOG: データ分析機能のギャップ分析と新規TODO作成

**作業日時**: 2026-03-19 15:00
**TODO_TYPE**: THINK
**対応元TODO**: なし（自主的なTHINK作業）

## 作業概要

プロジェクト全体のコードベース・既存TODO・ワークログを精査し、既存のpending TODOでカバーされていない重要な開発領域を特定した。前回のTHINK（20260319_1400）ではインフラ層の完成度評価と基盤機能のTODOを作成したが、今回は「分析の質と信頼性を高める」観点に焦点を当てた。

## 現状分析

### 既存pending TODO（9件）の分類

| 領域 | TODO |
|------|------|
| 分析基盤 | analysis_query_layer, sector_analysis_foundation |
| 指標拡張 | extend_financial_health_metrics, trend_turning_point_detection |
| インフラ | job_scheduling, job_monitoring_notification |
| UI/出力 | data_export_cli, web_api, web_dashboard |

### 未カバー領域の特定

既存TODOを分析した結果、以下の5つの領域がカバーされていないことを確認:

1. **業績予想修正の追跡**: data_jsonに予想値のスナップショットは保存されているが、修正履歴の追跡機能がない。予想の上方修正パターンは「飛躍の兆候」として極めて重要なシグナル。

2. **株価テクニカル指標**: DailyQuoteにOHLCVが蓄積されているが、移動平均や出来高分析が皆無。ファンダメンタル+テクニカルの複合スクリーニングができない。

3. **過去データバックフィル戦略**: 「6期連続増収増益」のスクリーニングに最低6年分の完全なデータが必要だが、体系的なバックフィル計画がない。

4. **データカバレッジ分析**: DataIntegrityCheckJobは整合性チェックに特化しているが、「何年分のデータがあるか」「どのフィールドが欠損しているか」のカバレッジ分析がない。データが不十分な企業で信頼性の低い分析結果が出るリスク。

5. **EDINET XBRLデータの拡充**: 基本的なP/L・B/S・C/F項目は抽出済みだが、セグメント情報・従業員数・研究開発費・減価償却費（EBITDA精緻化）など、深い分析に必要なデータの抽出計画がない。

## 作成したTODO（5件）

| ファイル | TYPE | 概要 |
|---------|------|------|
| `20260319_1500_dev_forecast_revision_tracking_DEVELOP_pending.md` | DEVELOP | 業績予想修正履歴の追跡。forecast_revisionsテーブル新設、修正率算出 |
| `20260319_1501_dev_stock_technical_indicators_DEVELOP_pending.md` | DEVELOP | 株価テクニカル指標（移動平均・出来高分析・ゴールデンクロス検出） |
| `20260319_1502_plan_historical_data_backfill_PLAN_pending.md` | PLAN | EDINET/JQUANTSの過去データを体系的にバックフィルする戦略立案 |
| `20260319_1503_improve_data_coverage_analysis_DEVELOP_pending.md` | DEVELOP | 企業別データカバレッジ可視化、ギャップ検出rakeタスク |
| `20260319_1504_plan_edinet_xbrl_enrichment_PLAN_pending.md` | PLAN | セグメント・従業員・R&D・減価償却など追加XBRL要素の抽出計画 |

## 推奨実装順序（前回THINKの推奨順序と統合）

前回THINKの推奨に今回の5件を組み込んだ全体の優先順位:

1. **Phase 1（データ基盤の信頼性確保）**
   - dev_analysis_query_layer + dev_job_scheduling（並行）
   - improve_data_coverage_analysis（データの信頼性を早期に把握）

2. **Phase 2（指標拡張）**
   - dev_extend_financial_health_metrics + dev_sector_analysis_foundation（並行）
   - dev_forecast_revision_tracking（予想修正追跡は早めに着手）

3. **Phase 3（データ拡充）**
   - plan_historical_data_backfill → バックフィル実行
   - plan_edinet_xbrl_enrichment → XBRL拡張実装

4. **Phase 4（インフラ・出力）**
   - dev_job_monitoring_notification + dev_data_export_cli（並行）
   - dev_stock_technical_indicators（分析の幅を広げる）

5. **Phase 5（UI層）**
   - plan_web_api → plan_web_dashboard → 実装
   - plan_trend_turning_point_detection → 実装

## 考えたこと

- 前回THINKがインフラ寄りのTODOに集中していたため、今回は「分析の質」に焦点を当てた
- 特にデータカバレッジ分析は、他の分析機能（連続増収増益スクリーニングなど）の信頼性に直結するため、早期に実装すべき
- 業績予想修正追跡は「飛躍前の変化を調べる」というユースケースへの重要なインプットとなる
- テクニカル指標は優先度としてはやや低いが、ファンダメンタルのみでは見落とすシグナルをキャッチするために将来的に有用
- EDINET XBRLの拡充は減価償却費の取得によりEBITDAの精緻化につながり、EV/EBITDA指標の信頼性向上に寄与する
