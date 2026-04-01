# WORKLOG: WEBダッシュボード検索 condition type レポート作成

作業日時: 2026-04-01 19:23

元TODO: `20260401_1923_report_web_dashboard_search_condition_type_DEVELOP`

## 作業概要

ダッシュボード検索で使用される6つの condition type について調査し、設計ルール・現在のフィールド一覧・今後の拡張想定を含むレポートを作成した。

## 作業内容

### 調査対象ファイル

- `app/models/screening_preset/condition_executor.rb` — 条件実行エンジン、各typeの定義定数
- `app/models/screening_preset/multi_period_condition_evaluator.rb` — 時間軸条件の評価器
- `app/models/financial_metric.rb` — data_jsonスキーマ定義、TREND_LABELS
- `app/helpers/dashboard_helper.rb` — UI向けオプション生成
- `config/locales/metrics.ja.yml` — I18nラベル定義
- `db/schema.rb` — テーブル構造

### 考えたこと

- 6つのtypeは「データの格納場所」「フィルタリング性能」「値の性質」の3軸で自然に分類されている
- SQL → Ruby post-filter → Temporal evaluation の3段階パイプラインは性能上合理的な設計
- data_json内にはフィルタ未公開のフィールドが多数存在する（DuPont分解、パーセンタイル、サプライズ指標、CAGR加速度など）。これらは将来的に `data_json_range` や `trend_filter` に追加可能
- `metric_range` へのフィールド追加はDBマイグレーションを伴うため慎重に判断する必要がある。検索頻度が高くインデックスが効果的なフィールドのみ昇格させるべき

### 成果物

- `docs/dashboard_search_condition_types.md` — レポート本体
