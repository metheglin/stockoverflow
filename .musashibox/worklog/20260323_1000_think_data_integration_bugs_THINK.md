# WORKLOG: データ連携・モデル設計の具体的バグ分析

**作業日時**: 2026-03-23 10:00

## 作業の概要

TODO_TYPE=THINK として、コードベースを精読し、既存145件以上のTODOでカバーされていない具体的なバグ・設計不整合を5件特定してTODOファイルを作成した。

## 考えたこと・作業の内容

### 分析アプローチ

過去のTHINKセッション（28件のworklog）は主に「機能不足」「メトリクス追加」「インフラ改善」に焦点を当てていた。今回は異なるアプローチとして、**実際のコードを行単位で精読し、データフローの不整合や論理バグ**を探した。

### 調査対象

以下のファイルを精読:
- 全7ジョブ（SyncCompaniesJob, ImportDailyQuotesJob, ImportJquantsFinancialDataJob, ImportEdinetDocumentsJob, CalculateFinancialMetricsJob, DataIntegrityCheckJob）
- 全モデル（Company, FinancialReport, FinancialValue, FinancialMetric, DailyQuote, ApplicationProperty）
- JsonAttribute concern
- 全3 APIクライアント + XBRLパーサー
- db/schema.rb

### 発見した問題

#### 1. jquants_sync の ApplicationProperty が3ジョブで共有（高優先度）

SyncCompaniesJob、ImportDailyQuotesJob、ImportJquantsFinancialDataJob がすべて `kind: :jquants_sync` を使用。株価ジョブが last_synced_date を更新すると、財務データジョブが古い日付をスキップする。逆も同様。インクリメンタル同期の正確性を損なう根本的な設計ミス。

#### 2. EDINET四半期の fiscal_year_end 不整合（高優先度）

ImportEdinetDocumentsJob が四半期報告書の fiscal_year_end に periodEnd（四半期末日）を使用。JQUANTS は CurFYEn（決算期末日）を使用。例: EDINET Q1 → fiscal_year_end=2024-06-30、JQUANTS Q1 → fiscal_year_end=2025-03-31。ユニークキーが不一致のため EDINET データが JQUANTS データを補完できず、重複レコードが生成される。

#### 3. SyncCompaniesJob のページネーション部分失敗（高優先度）

JquantsApi#load_all_pages のページネーションが途中で失敗すると、取得済み企業のみが synced_codes に入り、残りが誤って listed=false に更新される。全件失敗時（synced_codes.empty?）は early return で安全だが、部分失敗は検知されない。

#### 4. EDINET XBRL の per-share データ未抽出（中優先度）

EdinetXbrlParser が EPS, BPS, 発行済株式数を抽出していない。EDINET のみの FinancialValue ではバリュエーション指標が算出不能。また、parse_numeric が整数変換を試みるため、EPS=66.76 が 66 に切り捨てられるバグも発見。

#### 5. FinancialReport の has_one :financial_value が不正（中優先度）

1つの FinancialReport に連結・個別の2つの FinancialValue が紐づくが、has_one アソシエーションのため片方しか返されない。現時点で直接呼び出すコードはないが、今後の孤立レポート検出やデータ分析で問題となる。

### 既存TODOとの差分確認

各発見について既存TODO 145件以上を grep で重複チェック済み。いずれも新規の指摘であることを確認。

## 成果物

- `.musashibox/todo/20260323_1000_bugfix_jquants_sync_kind_shared_by_three_jobs_DEVELOP_pending.md`
- `.musashibox/todo/20260323_1001_bugfix_edinet_quarterly_fiscal_year_end_mismatch_DEVELOP_pending.md`
- `.musashibox/todo/20260323_1002_bugfix_sync_companies_marks_unlisted_on_partial_pagination_DEVELOP_pending.md`
- `.musashibox/todo/20260323_1003_dev_edinet_xbrl_per_share_data_extraction_DEVELOP_pending.md`
- `.musashibox/todo/20260323_1004_bugfix_financial_report_has_one_should_be_has_many_DEVELOP_pending.md`
