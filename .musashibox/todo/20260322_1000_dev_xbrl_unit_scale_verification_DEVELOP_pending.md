# XBRL単位・スケール検証と補正

## 概要

EdinetXbrlParserがXBRL要素の`decimals`属性および`unitRef`属性を検証せずに数値を抽出している問題を修正する。
現在は全ての値を円単位と仮定しているが（`parse_numeric`メソッド L243）、XBRL仕様では要素ごとに異なるスケールファクターが指定される場合がある。
JQUANTSから取得した値と単位が不一致の場合、YoY計算やバリュエーション指標が静かに破綻するリスクがある。

## 背景

- `EdinetXbrlParser#parse_numeric` は単純に文字列を整数変換しており、`decimals`属性を考慮していない
- XBRL仕様では `decimals="-6"` は百万円単位を意味し、`decimals="0"` は円単位を意味する
- JQUANTSは百万円単位（一部項目は円単位）でデータを提供する可能性がある
- 同一企業・同一期間のFinancialValueに対しJQUANTSとEDINETの両方からデータが格納されるため、単位不一致は深刻な問題になる

## 作業内容

### 1. XBRL要素の単位属性を調査

- 実際のEDINET XBRLファイルをサンプルとして取得し、主要要素の`decimals`属性と`unitRef`属性を確認
- 企業規模（大型/中小型）で異なるパターンがないか複数社で検証
- JQUANTSのAPIドキュメントで各フィールドの単位を確認

### 2. EdinetXbrlParserの改修

- `find_element_value`メソッドで`decimals`属性と`unitRef`属性を読み取る
- `decimals`属性に基づいて値を円単位に正規化するロジックを追加
- `parse_numeric`を拡張し、スケール変換をサポート

### 3. 既存データの検証

- 既にインポート済みのデータについて、JQUANTS由来の値とEDINET由来の値で桁数が大きく異なるレコードがないか検出するスクリプトを作成
- 問題が見つかった場合の修正手順を用意

### 4. テスト

- `EdinetXbrlParser`のテストに`decimals`属性パターンのテストケースを追加
- 単位正規化のテストケースを追加

## 対象ファイル

- `app/lib/edinet_xbrl_parser.rb`
- `spec/lib/edinet_xbrl_parser_spec.rb`

## 優先度

高 - データの正確性に直接影響する基盤的な問題
