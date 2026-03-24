# 株価テクニカル指標の算出基盤 - 作業ログ

作業日時: 2026-03-24

## 作業概要

DailyQuoteモデルにテクニカル指標の算出メソッドを追加し、企業スクリーニング用のQueryObjectを作成した。

## 実装内容

### 1. DailyQuoteモデルへのクラスメソッド追加（app/models/daily_quote.rb）

以下の5つのクラスメソッドを追加した。すべてDBには保存せず都度計算する純粋な関数として設計。

- `get_moving_averages(quotes, windows:)` - 各ウィンドウ幅の単純移動平均を算出。adjusted_closeを優先し、なければclose_priceを使用。
- `get_volume_average(quotes, window:)` - 出来高移動平均を算出。整数で返却。
- `get_price_position(price, ma_short, ma_long)` - 株価と移動平均の乖離率を算出。正の値=MA上方、負の値=MA下方。
- `detect_cross(quotes, short_window:, long_window:)` - ゴールデンクロス/デッドクロスを検出。直近日と前日のMA位置関係の変化を判定。
- `detect_volume_spikes(quotes, window:, threshold:, lookback:)` - 直近lookback日間の出来高急増を検出。各日のwindow日平均比で判定。

### 2. DailyQuote::TechnicalScreeningQuery（app/models/daily_quote/technical_screening_query.rb）

Company::SectorComparisonQueryと同様のQueryObjectパターンで実装。

- 3種のスクリーニング: `:golden_cross`, `:dead_cross`, `:volume_spike`
- 上場企業全体を対象にDailyQuoteを一括ロードし、各企業に対してDailyQuoteのクラスメソッドで検出
- `execute`メソッドで結果をHashの配列として返却（company, traded_on, close_price, 各種詳細情報）
- スクリーニング種別に応じたソートを実施

### 3. テスト（spec/models/daily_quote_spec.rb）

27件の新規テストを追加:

- `.get_moving_averages`: 正常系、データ不足、空配列、adjusted_close nil時のフォールバック、close_price nil時のスキップ（5件）
- `.get_volume_average`: 正常系、データ不足、空配列、nil含有、整数返却（5件）
- `.get_price_position`: 正/負の乖離率、0、nil/0でのスキップ（7件）
- `.detect_cross`: ゴールデンクロス、デッドクロス、クロスなし、データ不足（4件）
- `.detect_volume_spikes`: 急増検出、閾値未満、複数スパイク、データ不足、空配列、nil出来高（6件）

全194テスト合格（5件はAPI key未設定によるpending）

## 設計上の判断

- **data_json拡張（セクション3）は見送り**: TODOで「オプション」とされており、DailyQuoteのレコード数（全上場企業×営業日数）を考慮すると事前計算のコスト/効果を見極めてから着手すべきと判断
- **テクニカル指標はDBに保存しない設計**: FinancialMetricとは異なり、株価は日次更新されるためメモリ上で都度計算する方針。今後パフォーマンス問題が発生した場合にdata_json拡張を検討
- **検出メソッドをDailyQuoteのクラスメソッドとして配置**: FinancialMetricの計算メソッドと同パターンで、テストしやすい純粋関数として実装
- **QueryObjectはCompanyではなくDailyQuote配下に配置**: スクリーニング対象がDailyQuoteデータであり、DailyQuoteの責務に近いため

## 成果物

- `app/models/daily_quote.rb` - テクニカル指標クラスメソッド5つ追加
- `app/models/daily_quote/technical_screening_query.rb` - 新規作成
- `spec/models/daily_quote_spec.rb` - テスト27件追加
