# WORKLOG: 運用耐障害性とデータ連続性のギャップ分析

作業日時: 2026-03-22 19:00

## 作業概要

TODO_TYPE=THINK として、プロジェクトの現状を分析し、既存の135件のpending TODOではカバーされていない新たな課題を特定した。過去25回のTHINKセッションが主にデータ精度・指標計算・スクリーニング機能に注力していたのに対し、本セッションでは **運用耐障害性（operational resilience）** と **データ連続性（data continuity）** の観点から分析を行った。

## 分析アプローチ

1. 全ジョブの実装コードを精読し、障害発生時のデータ整合性リスクを洗い出した
2. 既存TODOとの重複を徹底的にチェックした（transaction, recovery, identity, dedup, merge, abort, credential 等のキーワードで検索）
3. ImportJquantsFinancialDataJob と ImportEdinetDocumentsJob の設計差異に着目し、片方にあって片方にない安全機構を特定した

## 考えたこと

### 観点1: トランザクション原子性の欠如

ソースコードを読んで気づいた最も基本的な問題。ActiveRecord::Base.transaction ブロックが一切使われていない。FinancialReport と FinancialValue は常にペアで存在すべきだが、両者の作成が独立した save!/create! で行われており、途中例外で孤立レコードが発生する。

特に ImportEdinetDocumentsJob では XBRL解析→レポート作成→値の作成 という3段階の処理があり、2段階目と3段階目の間で失敗するリスクが高い（XBRL解析結果が不完全な場合など）。

### 観点2: 同期カーソル管理の非対称性

ImportJquantsFinancialDataJob は `@last_successful_date` を追跡して ensure ブロックで記録する堅牢な実装だが、ImportEdinetDocumentsJob は `end_date` を無条件に記録する。同じプロジェクト内で2つのジョブが異なる安全性レベルで実装されている点は見落としやすいバグ。

失敗した日付のデータが永久に取り込まれないという影響は重大で、特にEDINET由来のXBRL拡張データ（売上原価、販管費等）はこの経路でしか取得できないため、欠損の影響が大きい。

### 観点3: 証券コード変更とデータ連続性

既存TODOに `company_listing_status_history`（上場/非上場の変遷追跡）はあるが、証券コード自体の変更は対象外。日本市場では年間数十件レベルでコード変更が発生しており（持株会社化、合併など）、ユースケース1（6期連続増収増益）の精度に直接影響する。

edinet_code は組織再編でも継続されることが多いため、edinet_code の一致を手がかりに承継候補を半自動検出できる可能性がある。

### 観点4: 長時間ジョブの無駄な実行

full モードのインポートは数時間かかるが、APIキーの失効やサービス障害時に延々とエラーを出し続ける。Faraday::TooManyRequestsError のみ特別扱いされているが、認証エラー(401)やサーバーエラー(500)は個別catchで吸収される。サーキットブレーカーパターンは既存のどのTODOにも含まれていなかった。

### 観点5: DataIntegrityCheckJob のカバレッジ

4つのチェック（missing_metrics, missing_daily_quotes, consecutive_growth, sync_freshness）は実装済みだが、最も基本的な「レポートに値がない」チェックが欠けている。観点1のトランザクション修正と合わせて、修正前に現状の孤立レコード数を把握できる検出機構を先に入れるべき。

## 成果物

以下の5件のTODOファイルを作成した:

| ファイル | 種別 | 概要 |
|---------|------|------|
| `20260322_1900_bugfix_import_job_transaction_atomicity_DEVELOP_pending.md` | bugfix | インポートジョブのトランザクション保護 |
| `20260322_1901_bugfix_edinet_sync_cursor_skips_failed_dates_DEVELOP_pending.md` | bugfix | EDINET同期カーソルの失敗日付スキップ修正 |
| `20260322_1902_dev_company_code_succession_tracking_DEVELOP_pending.md` | dev | 証券コード変更・承継関係の追跡 |
| `20260322_1903_improve_import_api_circuit_breaker_DEVELOP_pending.md` | improve | API障害時サーキットブレーカー |
| `20260322_1904_dev_orphaned_report_detection_integrity_check_DEVELOP_pending.md` | dev | 孤立FinancialReport検出の整合性チェック追加 |

## 既存TODOとの関連

- `20260322_1700_bugfix_metric_calculation_processing_order`: 本セッションの観点1（トランザクション）と組み合わせることで、データの生成と計算の両段階で整合性を担保できる
- `20260322_1701_dev_job_execution_lock_mechanism`: サーキットブレーカー（本セッション観点4）と組み合わせることで、並行実行制御+障害検知の両方が揃う
- `20260321_1003_dev_metric_recalculation_dependency_chain`: 証券コード承継（本セッション観点3）が実装された場合、依存チェーンの解析対象に承継元企業のデータも含める必要がある
