# 市場インデックスベンチマークデータの取り込み

## 概要

TOPIX・日経225などの市場インデックスデータをJQUANTS APIから取得し、個別企業の株価パフォーマンスを市場全体と比較できるようにする。

## 背景・動機

- 個別銘柄の株価上昇が「市場全体の上昇」なのか「その企業固有の強さ」なのかを判別できない
- 相対パフォーマンス（α・超過リターン）の算出には市場ベンチマークデータが不可欠
- 今後予定されている以下の機能の前提条件となる:
  - 株価テクニカル指標（相対強度）
  - Earnings Price Reaction分析（市場全体の動きを排除した決算反応の測定）
  - バリュエーション分析（市場平均PER/PBRとの比較）

## 実装方針

### データソース

JQUANTS API の `indices` エンドポイントを利用

### テーブル設計

```
market_indices テーブル
- id
- index_code (string, e.g., "TOPIX", "N225")
- traded_on (date)
- open_price (decimal)
- high_price (decimal)
- low_price (decimal)
- close_price (decimal)
- volume (bigint)
- data_json (json)
- timestamps
- unique index: (index_code, traded_on)
```

### インポートジョブ

- `ImportMarketIndicesJob` を新設
- JQUANTS APIから TOPIX, 日経225 の日次データを取得
- daily_quotes と同じインクリメンタル同期パターンを採用
- ApplicationProperty (kind: market_index_sync) で同期状態を管理

### 分析用メソッド

- `MarketIndex.load_returns(index_code:, from:, to:)` - 期間リターンの取得
- `MarketIndex.get_relative_return(company_return:, market_return:)` - 超過リターンの算出

## 備考

- JQUANTS APIのインデックスデータ提供範囲を事前に確認する必要あり
- daily_quotes の既存インフラ（Faraday, リトライ, レート制限）を再利用する
