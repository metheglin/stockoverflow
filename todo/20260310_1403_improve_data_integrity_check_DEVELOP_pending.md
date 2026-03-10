# DEVELOP: データ整合性チェック・モニタリング

## 背景

データ取り込みジョブは個別レコードの失敗を rescue してバッチ全体を止めない設計になっている。これはバッチ運用上正しい判断だが、取り込み漏れやデータ不整合を検知する仕組みがないと、分析結果の信頼性に影響する。

## 実装内容

### 1. データ整合性チェックジョブ

日次または週次で実行し、データの整合性をチェックするジョブを作成する。

チェック項目:
- `financial_values` に対応する `financial_metrics` が存在するか（算出漏れ検出）
- 上場企業（`companies.listed = true`）に対して直近の `daily_quotes` が存在するか（株価取り込み漏れ検出）
- `financial_metrics` の `consecutive_revenue_growth` / `consecutive_profit_growth` が正しく連番になっているか
- `application_properties` の `last_synced_date` が古すぎないか（同期停止検出）

### 2. 集計・サマリーレポート

`ApplicationProperty` に以下のサマリー情報を保存し、現在のデータ状態を把握できるようにする。

- 上場企業数
- financial_values レコード数（期間別）
- financial_metrics 算出済みレコード数
- daily_quotes の最新取得日
- 各ソース（EDINET/JQUANTS）からの取り込みレコード数

### 3. ログの構造化

現在ジョブ内で `Rails.logger.error` で出力しているエラーログを、後から集計・検索しやすい形式に整理する。

## テスト

- チェックロジックのモデルメソッドとして切り出し、ユニットテストを記述する
- ジョブの稼働テストは記述しない（テスティング規約準拠）

## 成果物

- `app/jobs/data_integrity_check_job.rb` - 整合性チェックジョブ
- 関連するモデルメソッド
- テスト
