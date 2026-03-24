# PLAN: IFRS適用企業のXBRLタクソノミ対応設計

## 概要

IFRS（国際財務報告基準）を採用する日本上場企業のXBRL有価証券報告書に対応するため、IFRSタクソノミと日本基準タクソノミの差分を調査し、EdinetXbrlParserのマルチスタンダード対応設計を策定する。

## 背景・動機

### 現状

EdinetXbrlParser は `jppfs_cor`（日本基準の財務諸表）名前空間のみ対応している。しかし日本の上場企業の約250社（2025年時点）がIFRSを採用しており、これらの企業のXBRL有価証券報告書では `jppfs_cor` の要素が存在せず、代わりに `ifrs-full` 名前空間の要素が使用される。

### 影響

IFRSを採用している企業は時価総額上位の大企業が多く（トヨタ、ソニー、日立、ソフトバンク等）、これらの企業のXBRLデータが取得できないことは分析の大きな欠落となる。

### IFRS特有の勘定科目の違い

| 日本基準 (jppfs_cor) | IFRS (ifrs-full) | 備考 |
|---|---|---|
| NetSales | Revenue | IFRSでは「売上収益」 |
| OperatingIncome | — | IFRSでは「営業利益」は任意開示 |
| OrdinaryIncome | — | IFRSには「経常利益」概念なし |
| ProfitLossAttributableToOwnersOfParent | ProfitLossAttributableToOwnersOfParent | 同名 |
| Assets | Assets | 同名 |
| NetAssets | EquityAttributableToOwnersOfParent | IFRSでは「親会社の所有者に帰属する持分」 |

## 計画作成にあたり調査すべき事項

### 1. IFRSタクソノミの要素名調査

- EDINETのIFRS用XBRLファイルで使用される名前空間プレフィックスの確認
- 主要財務諸表項目のIFRS要素名リストの作成
- IFRSにおけるコンテキストIDパターンの差分確認

### 2. マルチスタンダード設計の方針

- 会計基準の判定方法（XBRLファイルの名前空間宣言から判定可能か）
- 会計基準別のマッピング定義の構造
- Company モデルへの会計基準カラム追加の要否

### 3. 日本基準→IFRS変更企業の取り扱い

- 過去は日本基準、現在はIFRSの企業の時系列比較方法
- 経常利益など IFRS に存在しない概念の扱い

## 成果物

- IFRS要素マッピング設計書
- EdinetXbrlParser マルチスタンダード対応の詳細仕様（DEVELOP TODO）

## 優先度

低。IFRS採用企業は約250社と少数だが、大型株に集中するため分析上の重要性は高い。ただしjppfs_corの拡張を完了した後に取り組むべき。

## 依存関係

- 先行: `dev_xbrl_jppfs_element_expansion`, `dev_xbrl_jpcrp_namespace_support`
- 関連: `plan_edinet_segment_data_extraction`（セグメントデータもIFRS対応が必要）
