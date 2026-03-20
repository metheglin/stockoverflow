# WORKLOG: THINK - スクリーニング検証と分析深化のギャップ分析

**作業日時**: 2026-03-20 16:00

**元TODO**: N/A (THINK タスク)

---

## 作業概要

プロジェクト全体の現状を精査し、既存の40件のpending TODOがカバーしていない領域を特定し、5件の新規TODOを作成した。

## 分析プロセス

### 1. 現状把握

プロジェクトの実装状況を確認:

- **データパイプライン**: 完成（EDINET/JQUANTS両方からの取り込み、6つのジョブ稼働）
- **データモデル**: 6テーブル（companies, financial_reports, financial_values, financial_metrics, daily_quotes, application_properties）
- **指標計算**: YoY成長率、収益性指標（ROE/ROA/各利益率）、CF指標、連続成長カウンター、バリュエーション（PER/PBR/PSR）、サプライズ指標
- **テスト**: RSpecで12ファイル、主要ロジックをカバー

### 2. 既存TODO（40件pending）のカテゴリ分析

| カテゴリ | 件数 | 主な内容 |
|---------|------|---------|
| 財務指標拡張 | 13 | Piotroski, ROIC, DuPont, CAGR, 営業レバレッジ, 配当, CCC等 |
| 分析基盤 | 4 | クエリ層, セクター分析, 複合スコア, テクニカル指標 |
| データ品質 | 5 | クロスソース検証, カバレッジ分析, 耐障害性, SQLite最適化, 監視 |
| 運用基盤 | 4 | Rakeタスク, FactoryBot, ジョブスケジューリング, データエクスポート |
| 設計/計画 | 8 | Web API, ダッシュボード, スクリーニング, 転換点検出, バックフィル等 |
| 企業ライフサイクル | 2 | ライフサイクル追跡, 予想修正追跡 |
| バリュエーション | 4 | 日次バリュエーション, PEG, 業績品質, 季節性 |

### 3. 特定したギャップ

3つの主要ユースケースに照らして、以下のギャップを特定:

#### ユースケース1: 条件スクリーニング
- **ギャップ**: 個別指標は充実しているが、「その企業がセクター/市場内でどの位置にいるか」というパーセンタイル情報が欠落
- **ギャップ**: スクリーニング条件が本当に有効かを過去データで検証する仕組みがない

#### ユースケース2: 履歴トレンド分析
- **ギャップ**: YoY変化率はあるが、「改善中/悪化中/転換点」といったトレンドの方向性ラベルがない
- **ギャップ**: 1社の全期間データを時系列で俯瞰するビューがない

#### ユースケース3: ブレイクスルー前パターン調査
- **ギャップ**: 数値の大幅変動が「本質的改善」か「一時的要因（特別損益等）」かを区別する仕組みがない

### 4. 他TODOとの重複チェック

各候補について既存TODOとの重複を精査:

- `dev_company_financial_timeline_view` → `dev_analysis_query_layer` はクエリ実行層で目的が異なる。`plan_pre_breakthrough_pattern_analysis` はパターン認識で、タイムラインデータの生成自体は含まない。**重複なし**
- `dev_metric_percentile_ranking` → `dev_sector_analysis_foundation` はセクター統計（平均値等）で、個社のパーセンタイル順位算出は含まない。**重複なし**
- `dev_metric_trend_classification` → `plan_trend_turning_point_detection` は高度な転換点検出の設計で、本TODOは基本的なトレンド方向分類の実装。**補完関係**
- `plan_backtest_screening_simulation` → `plan_watchlist_screening_preset` は条件保存、`plan_screening_state_change_detection` は状態変化検出で、過去データでの検証フレームワークは含まない。**重複なし**
- `dev_financial_anomaly_detection` → `dev_earnings_quality_analysis` は利益の質（CF裏付け）を見るもので、統計的異常値や特殊項目検出は含まない。**補完関係**

## 成果物

以下の5件のTODOファイルを作成:

1. `20260320_1600_dev_company_financial_timeline_view_DEVELOP_pending.md`
   - 1社の全期間財務データを時系列構造化して出力するサービス
   - ブレイクスルー前パターン調査の基盤データ

2. `20260320_1601_dev_metric_percentile_ranking_DEVELOP_pending.md`
   - 主要指標のセクター内/市場全体パーセンタイル順位算出
   - 「上位N%」型スクリーニングを実現

3. `20260320_1602_dev_metric_trend_classification_DEVELOP_pending.md`
   - 指標の時系列トレンド方向分類（improving/deteriorating/turning_up等）
   - 転換点検出の基盤ロジック

4. `20260320_1603_plan_backtest_screening_simulation_PLAN_pending.md`
   - スクリーニング条件の過去データ検証フレームワーク設計
   - 条件の有効性を定量評価

5. `20260320_1604_dev_financial_anomaly_detection_DEVELOP_pending.md`
   - 統計的異常値・特殊項目・決算期異常の自動検出
   - スクリーニング結果のノイズ除去

## 所感

過去6回のTHINKセッションで40件のTODOが蓄積されているが、その多くは「個別指標の追加」に集中している。今回は視点を変え、「指標の使い方・活用方法」「分析結果の信頼性検証」「データの解釈支援」という観点からギャップを特定した。特にバックテストフレームワークと異常値検出は、スクリーニング結果の品質に直結する重要な機能である。
