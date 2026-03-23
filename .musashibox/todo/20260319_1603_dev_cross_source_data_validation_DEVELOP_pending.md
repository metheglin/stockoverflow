# EDINET/JQUANTSクロスソースデータ検証

## 概要

同一企業・同一決算期について、EDINETとJQUANTSの両方からインポートされた財務データの整合性を検証するロジックを `DataIntegrityCheckJob` に追加する。

## 背景

- `ImportJquantsFinancialDataJob` は JQUANTS API から財務データを取得し `financial_values` に保存
- `ImportEdinetDocumentsJob` は EDINET XBRL から財務データを解析し、既存の `financial_values.data_json` を補完
- 同一企業・同一期間のレコードに対して両ソースのデータが混在する場合があるが、主要指標（売上高、営業利益、純利益等）の一致確認が行われていない

## 実装内容

### 1. クロスバリデーションメソッドの追加

`FinancialValue` にクラスメソッドを追加:

```ruby
# JQUANTS由来のカラム値とEDINET由来のdata_json値を比較
# 乖離率が閾値を超えるレコードを返す
def self.get_cross_source_discrepancies(threshold_rate: 0.05)
  # financial_valuesのうちdata_jsonにEDINET由来データが存在するものを対象
  # net_sales (JQUANTS) vs data_json.net_sales (EDINET) 等を比較
  # 乖離率 = |a - b| / [max(|a|, |b|)] が threshold_rate を超えるものを検出
end
```

### 2. 比較対象フィールド

以下のフィールドをクロスチェック:
- `net_sales` (売上高)
- `operating_income` (営業利益)
- `ordinary_income` (経常利益)
- `net_income` (当期純利益)
- `total_assets` (総資産)
- `net_assets` (純資産)

### 3. DataIntegrityCheckJob への統合

- 新しいチェック項目「クロスソース整合性チェック」を追加
- 乖離が検出されたレコードの一覧をログ出力
- 結果サマリを `application_properties` の `data_integrity` に含める

### 4. テスト

- `FinancialValue.get_cross_source_discrepancies()` のユニットテスト
- 乖離なし / 軽微な乖離（閾値以下）/ 重大な乖離（閾値超過）のケース
- 片方のソースのみの場合（比較不要）のケース

## 注意事項

- EDINET由来データは `data_json` 内に格納されているため、JSONフィールドのキー名とカラム名の対応を正確にマッピングすること
- 単位の違い（千円/百万円/円）に注意。EdinetXbrlParser の出力単位と JQUANTS の出力単位を確認する
- 乖離の原因として、決算修正や会計基準の違いがありうるため、乖離＝エラーとは限らない。検出結果は参考情報として扱う
