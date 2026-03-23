# WORKLOG: バリュエーション精度とスクリーニング網羅性の分析

**作業日時**: 2026-03-22 18:00

## 元TODO

TODO_TYPE=THINK（プロンプト指示による自律的なギャップ分析）

## 作業概要

プロジェクト全体のコード・DB設計・既存TODO（140件）・WORKLOG（25件）を精読し、既存のTHINKセッションでカバーされていない重要な問題を特定した。

## 分析アプローチ

過去のTHINKセッション（25回分）の傾向を分析したところ、以下のパターンを認識:

- 2026-03-19〜20: 分析機能拡張（Piotroski, DuPont, DCF等）の大量発見フェーズ
- 2026-03-21: 運用基盤・インフラ系のギャップ発見フェーズ
- 2026-03-22: コードレベルの実装バグ発見フェーズ（処理順序バグ、型変換等）

本セッションでは、上記フェーズを経て残っている「実際にスクリーニングを動作させたときに初めて気づく問題」に焦点を当てた。つまり、個別のメトリクス算出ロジックは正しくても、データパイプライン全体を通したときに発生する不整合や、スクリーニング結果の品質に影響する系統的な問題を探索した。

## 考えたこと

### 1. バリュエーション指標の株式分割問題

`CalculateFinancialMetricsJob.load_stock_price`（行110-116）を精読中に発見。`adjusted_close`（分割調整済み）を取得しているが、`get_valuation_metrics` で使う `fv.eps` / `fv.bps` は財務諸表の未調整値。株式分割が発生した企業では PER/PBR が桁違いに不正確な値になる。

これは既存TODOのどれとも異なる問題。`20260322_1603_dev_daily_quote_adjusted_price_methods` はDailyQuoteにメソッドを追加するものであり、CalculateFinancialMetricsJobの「どの価格を使うか」の選択問題は扱っていない。

### 2. 非連結企業のスクリーニング不可視化

分析クエリレイヤーTODO（`20260312_1000`）を精読したところ、全てのQueryObjectが `scope: :consolidated` を前提としていた。子会社を持たない企業は連結決算を公表しないため、これらの企業はスクリーニング対象から完全に排除される。東証上場企業の15-20%が該当すると推定。

### 3. パイプライン実行順序とバリュエーション指標の永久欠損

`build_target_scope`（行22-34）のロジックを読み、DailyQuoteが後からインポートされた場合にバリュエーション指標が永久にnilのまま放置される問題を発見。FinancialValue.updated_atをトリガーとする設計のため、DailyQuoteの追加はトリガーにならない。

### 4. データカバレッジの非均一性

スクリーニング結果の信頼性を考えたとき、「consecutive_revenue_growth = 5」が「5期分のデータしかない企業で実質全期間成長」なのか「20期分のデータがある企業で直近5期だけ成長」なのかは意味が全く異なる。企業ごとのデータカバレッジ評価が必要。

### 5. XBRL data_json内の原価構造データの未活用

`FinancialValue.data_json` に `cost_of_sales`, `gross_profit`, `sga_expenses` が格納されているにもかかわらず、メトリクス算出で一切使われていない。営業利益率の内訳分析（原価率と販管費率の分解）は、ユースケース3（飛躍直前の変化分析）に直接貢献する。

## 作成したTODO

| ファイル名 | 種別 | 内容 |
|-----------|------|------|
| `20260322_1800_bugfix_valuation_split_adjustment_mismatch_DEVELOP_pending.md` | DEVELOP/bugfix | PER/PBR算出で分割調整済み株価と未調整EPS/BPSを混在使用している問題の修正 |
| `20260322_1801_dev_scope_fallback_for_screening_DEVELOP_pending.md` | DEVELOP | 連結/個別スコープのフォールバック。非連結企業のスクリーニング対応 |
| `20260322_1802_bugfix_valuation_metric_stale_on_late_quote_import_DEVELOP_pending.md` | DEVELOP/bugfix | DailyQuote後追いインポート時にバリュエーション指標が永久にnilとなる問題の修正 |
| `20260322_1803_dev_company_data_coverage_assessment_DEVELOP_pending.md` | DEVELOP | 企業別データカバレッジ評価。スクリーニング結果の信頼度付加 |
| `20260322_1804_dev_cost_structure_breakdown_metrics_DEVELOP_pending.md` | DEVELOP | 原価率・売上総利益率・販管費率の算出。収益構造分解メトリクスの追加 |

## 既存TODOとの重複確認

- 各TODOに「関連TODO」セクションを設け、関連する既存TODOとの差分を明記済み
- 140件の既存TODOのタイトル・内容を確認し、上記5件はいずれも既存TODOと対象・解決策が異なることを確認

## 今後に向けて

- 本セッションで発見した5件はいずれも「スクリーニングの実用化」に直結する問題
- 特に bugfix 2件（#1, #3）は、スクリーニング結果の正確性に直接影響するため、`20260322_1703_plan_minimum_viable_screening_path` の Phase 0（バグ修正フェーズ）に含めることを推奨
- `dev_scope_fallback_for_screening`（#2）は `dev_analysis_query_layer`（20260312_1000）の実装時に合わせて対応するのが効率的
