# WORKLOG: EDINET XBRLデータの拡充計画

**作業日時**: 2026-03-24

## 作業概要

`20260319_1504_plan_edinet_xbrl_enrichment_PLAN_inprogress.md` の指示に基づき、EDINET XBRLデータの拡充に関する詳細調査と開発計画の策定をおこなった。

## 調査内容

### 1. EdinetXbrlParser の現状分析

現行パーサーの構造を詳細に調査:
- jppfs_cor 名前空間のみ対応（19要素: 固定カラム11 + 拡張8）
- P/L: 売上高、営業利益、経常利益、純利益
- B/S: 総資産、純資産、流動/固定資産・負債、株主資本
- C/F: 営業/投資/財務CF、現金同等物
- P/L詳細: 売上原価、売上総利益、販管費
- コンテキストパターンで連結/個別、当期/前期を区別
- 要素候補の配列による企業ごとの勘定科目差異への対応

### 2. XBRLタクソノミの分析

#### jppfs_cor（財務諸表本体）で追加可能な要素
- **P/L**: 営業外損益、支払利息、特別損益、税前利益、法人税等（7要素）
- **B/S**: 有利子負債3要素（短期借入金、長期借入金、社債）、負債合計、利益剰余金、棚卸資産、売掛金、買掛金、のれん、無形固定資産（10要素）
- **C/F**: 減価償却費（1要素）

#### jpcrp_cor（企業報告）で追加可能な要素
- 研究開発費、設備投資額、減価償却費（経営指標）、従業員数（4要素）
- register_namespaces の拡張で jpcrp_cor 名前空間を追加登録する必要あり

#### IFRSタクソノミ
- 約250社がIFRS採用。ifrs-full 名前空間の要素マッピングが別途必要
- 日本基準と大きく異なる概念あり（経常利益なし、営業利益は任意開示等）
- 独立したPLAN TODOとして切り出し

### 3. データ格納設計

#### 判断結果: 既存の data_json を拡張

以下の理由から、新テーブルは作成せず FinancialValue の data_json スキーマを拡張する方針を採用:
- 追加要素はいずれも「1企業・1期間に1つの値」であり、FinancialValue と1:1の関係
- 検索条件としてWHERE句に使うことは想定しない（指標計算の入力値として使用）
- data_json はJsonAttribute concern により getter/setter が自動生成され、固定カラムと同様にアクセス可能
- ImportEdinetDocumentsJob の supplement_with_xbrl / create_from_xbrl が xbrl_values[:extended] を動的処理するため、ジョブの変更不要

#### セグメント情報について
セグメント情報は構造が根本的に異なる（1企業に複数セグメント、セグメント名は企業ごとに異なる）ため、既存の `20260321_2105_plan_edinet_segment_data_extraction_PLAN_pending.md` で別途設計する。

### 4. パーサー拡張の設計方針

- 既存の EXTENDED_ELEMENT_MAPPING への追加で対応（jppfs_cor 要素）
- jpcrp_cor 要素については register_namespaces の拡張と EXTENDED_ELEMENT_MAPPING への追加
- DURATION_KEYS / INSTANT_KEYS への要素追加で正しいコンテキスト割当を維持
- find_element_value のロジックは変更不要（namespace を mapping から読み取る設計済み）

## 成果物

### 作成したDEVELOP TODO（3件）

1. **`20260324_1000_dev_xbrl_jppfs_element_expansion_DEVELOP_pending.md`**
   - jppfs_cor の P/L・B/S・C/F 追加要素（18要素）の実装
   - 優先度: 高

2. **`20260324_1001_dev_xbrl_jpcrp_namespace_support_DEVELOP_pending.md`**
   - jpcrp_cor 名前空間対応と R&D・設備投資・従業員数（4要素）の実装
   - 優先度: 中（jppfs_cor拡張の後に実施）

3. **`20260324_1002_dev_xbrl_enrichment_derived_metrics_DEVELOP_pending.md`**
   - 拡張データを活用した新指標: EBITDA精緻化、CCC、R&D集約度、従業員生産性等
   - 優先度: 中（XBRL要素拡張の完了後に実施）

### 作成したPLAN TODO（1件）

4. **`20260324_1003_plan_xbrl_ifrs_taxonomy_mapping_PLAN_pending.md`**
   - IFRS企業のタクソノミ対応の調査・設計
   - 優先度: 低（jppfs_cor/jpcrp_cor拡張の完了後に着手）

### 関連する既存TODO

- `20260323_1003_dev_edinet_xbrl_per_share_data_extraction_DEVELOP_pending.md` — EPS・BPS・発行済株式数の抽出。今回のスコープとは独立だが、parse_numeric のDecimal対応は共通の課題
- `20260321_2105_plan_edinet_segment_data_extraction_PLAN_pending.md` — セグメント情報の抽出。構造が異なるため別系統として管理

## 実装順序の推奨

```
1. dev_edinet_xbrl_per_share_data_extraction (parse_numeric修正含む)
   ↓
2. dev_xbrl_jppfs_element_expansion (jppfs_cor 18要素追加)
   ↓
3. dev_xbrl_jpcrp_namespace_support (jpcrp_cor 4要素追加)
   ↓
4. dev_xbrl_enrichment_derived_metrics (新指標の算出ロジック)
   ↓
5. plan_xbrl_ifrs_taxonomy_mapping (IFRS対応の設計)
```
