# WEBダッシュボード検索: Condition Type 解説

## 概要

ダッシュボードのスクリーニング検索では、6つの **condition type** を用いて企業を絞り込む。
各typeは「検索対象データの性質」と「フィルタリング手法の違い」によって分類されている。

| condition type | 日本語名 | データ格納場所 | フィルタ方式 |
|---|---|---|---|
| `metric_range` | 指標(数値) | `financial_metrics` テーブル専用カラム | SQL WHERE |
| `data_json_range` | 指標(詳細) | `financial_metrics.data_json` (JSON) | Rubyレベルpost-filter |
| `metric_boolean` | 指標(フラグ) | `financial_metrics` テーブル専用カラム | SQL WHERE |
| `company_attribute` | 企業属性 | `companies` テーブル | SQL WHERE (JOIN) |
| `trend_filter` | トレンド分類 | `financial_metrics.data_json` (JSON) | Rubyレベルpost-filter |
| `temporal` | 時間軸条件 | `financial_metrics` 複数期間履歴 | 専用Evaluator |

---

## 各 condition type の詳細

### 1. 指標(数値) — `metric_range`

#### ルール

- `financial_metrics` テーブルに **専用のDBカラム** として存在する数値指標が対象
- DBカラムであるためSQLレベルで効率的にフィルタリングできる
- min/max の範囲指定でフィルタする
- DBインデックスの恩恵を受けられる指標はここに属する

#### 現在のフィールド（13件）

| カテゴリ | フィールド | 日本語名 |
|---|---|---|
| 成長性(YoY) | `revenue_yoy` | 売上高成長率(YoY) |
| | `operating_income_yoy` | 営業利益成長率(YoY) |
| | `ordinary_income_yoy` | 経常利益成長率(YoY) |
| | `net_income_yoy` | 純利益成長率(YoY) |
| | `eps_yoy` | EPS成長率(YoY) |
| 収益性 | `roe` | ROE(自己資本利益率) |
| | `roa` | ROA(総資産利益率) |
| | `operating_margin` | 営業利益率 |
| | `ordinary_margin` | 経常利益率 |
| | `net_margin` | 純利益率 |
| キャッシュフロー | `free_cf` | フリーキャッシュフロー |
| 連続性 | `consecutive_revenue_growth` | 連続増収期数 |
| | `consecutive_profit_growth` | 連続増益期数 |

#### 条件構造

```json
{ "type": "metric_range", "field": "revenue_yoy", "min": 0.15, "max": 0.50 }
```

#### 今後追加が想定される検索軸

- `ebitda_margin` (EBITDAマージン): 業種横断の収益力比較で有用
- `roic` (投下資本利益率): 資本効率の本質的指標
- `equity_ratio` (自己資本比率): 財務健全性の基本指標（頻繁に検索されるならDBカラム昇格が妥当）
- `total_assets_yoy`, `net_assets_yoy`: バランスシートの成長性
- `operating_cf`, `investing_cf`: キャッシュフロー個別の金額（free_cfと同様に専用カラム化）

---

### 2. 指標(詳細) — `data_json_range`

#### ルール

- `financial_metrics.data_json` (JSON型カラム) に格納されるデータが対象
- SQLレベルのインデックスが効かないため、Rubyレベルでpost-filterを適用する
- 検索対象としての重要度がmetric_rangeほど高くない、あるいは将来的にスキーマ拡張が多く見込まれる指標が属する
- バリュエーション指標、財務健全性指標、効率性指標、スコア、CAGR、配当分析、成長加速度など多数の指標を柔軟に管理

#### 現在のフィールド（29件）

| カテゴリ | フィールド | 日本語名 |
|---|---|---|
| バリュエーション | `per` | PER(株価収益率) |
| | `pbr` | PBR(株価純資産倍率) |
| | `psr` | PSR(株価売上高倍率) |
| | `dividend_yield` | 配当利回り |
| | `ev_ebitda` | EV/EBITDA |
| 財務健全性 | `current_ratio` | 流動比率 |
| | `debt_to_equity` | D/Eレシオ |
| | `net_debt_to_equity` | ネットD/Eレシオ |
| 効率性 | `asset_turnover` | 総資産回転率 |
| | `gross_margin` | 売上総利益率 |
| | `sga_ratio` | 販管費率 |
| スコア | `growth_score` | 成長スコア |
| | `quality_score` | 品質スコア |
| | `value_score` | バリュースコア |
| | `composite_score` | 総合スコア |
| CAGR | `revenue_cagr_3y` | 売上高CAGR(3年) |
| | `revenue_cagr_5y` | 売上高CAGR(5年) |
| | `operating_income_cagr_3y` | 営業利益CAGR(3年) |
| | `operating_income_cagr_5y` | 営業利益CAGR(5年) |
| | `net_income_cagr_3y` | 純利益CAGR(3年) |
| | `net_income_cagr_5y` | 純利益CAGR(5年) |
| | `eps_cagr_3y` | EPS CAGR(3年) |
| | `eps_cagr_5y` | EPS CAGR(5年) |
| 配当 | `payout_ratio` | 配当性向 |
| | `dividend_growth_rate` | 配当成長率 |
| | `consecutive_dividend_growth` | 連続増配期数 |
| 成長加速度 | `revenue_growth_acceleration` | 売上高成長加速度 |
| | `operating_income_growth_acceleration` | 営業利益成長加速度 |
| | `net_income_growth_acceleration` | 純利益成長加速度 |
| | `eps_growth_acceleration` | EPS成長加速度 |

#### 条件構造

```json
{ "type": "data_json_range", "field": "pbr", "min": 0.8, "max": 1.5 }
```

#### 今後追加が想定される検索軸

- `pcfr` (株価キャッシュフロー倍率): CF重視の投資家向けバリュエーション指標
- `dividend_on_equity` (DOE): 自己資本配当率
- `interest_coverage_ratio`: 利払い能力
- `quick_ratio` (当座比率): より厳密な短期支払能力
- `dupont_net_margin`, `dupont_asset_turnover`, `dupont_equity_multiplier`: DuPont分解要素での絞り込み（data_json上に存在するが未公開）
- `sector_percentile_*`, `market_percentile_*`: パーセンタイルランクでの絞り込み（data_json上に存在するが未公開）
- `revenue_surprise`, `operating_income_surprise`, `net_income_surprise`, `eps_surprise`: 決算サプライズ指標（data_json上に存在するが未公開）
- 各種CAGR加速度 (`cagr_acceleration_*`): CAGR自体の変化率（data_json上に存在するが未公開）

---

### 3. 指標(フラグ) — `metric_boolean`

#### ルール

- `financial_metrics` テーブル上の **boolean型カラム** が対象
- 数値の大小ではなく、ある状態が「成立しているか否か」でフィルタする
- SQLレベルで処理されるため高速
- キャッシュフローの正負判定のように、二値で表現できる定性的状態がここに属する

#### 現在のフィールド（3件）

| フィールド | 日本語名 | 意味 |
|---|---|---|
| `operating_cf_positive` | 営業CF正 | 営業キャッシュフローがプラスか |
| `investing_cf_negative` | 投資CF負 | 投資キャッシュフローがマイナスか（投資活動中） |
| `free_cf_positive` | FCF正 | フリーキャッシュフローがプラスか |

#### 条件構造

```json
{ "type": "metric_boolean", "field": "operating_cf_positive", "value": true }
```

#### 今後追加が想定される検索軸

- `dividend_paid`: 配当実施中かどうか
- `buyback_active`: 自社株買い実施中
- `net_cash_positive`: ネットキャッシュがプラスか（実質無借金経営）
- `profit_positive`: 最終損益が黒字か
- `revenue_growing`: 増収かどうか（YoY > 0の簡易フラグ）

---

### 4. 企業属性 — `company_attribute`

#### ルール

- `companies` テーブルのカラムが対象
- 財務指標ではなく、企業そのものの **属性・分類** による絞り込み
- SQLレベルでJOINして処理
- 複数値を指定し「いずれかに一致」（IN句）でフィルタする

#### 現在のフィールド（4件）

| フィールド | 日本語名 | 説明 |
|---|---|---|
| `sector_17_code` | セクター(17分類) | 東証17業種分類コード |
| `sector_33_code` | セクター(33分類) | 東証33業種分類コード |
| `market_code` | 市場区分 | プライム・スタンダード・グロース等 |
| `scale_category` | 規模区分 | 大型・中型・小型等 |

#### 条件構造

```json
{
  "type": "company_attribute",
  "field": "sector_33_code",
  "values": ["1710", "1720", "1730"]
}
```

#### 今後追加が想定される検索軸

- `listing_date` (上場日): 上場年数での絞り込み（IPO銘柄の発見など）
- `fiscal_month` (決算月): 特定の決算月の企業を抽出
- `headquarters_prefecture` (本社所在地): 地域別分析
- `consolidated_subsidiary_count` (連結子会社数): グループ規模
- `employee_count` (従業員数): 企業規模の別軸

---

### 5. トレンド分類 — `trend_filter`

#### ルール

- `financial_metrics.data_json` 内の **トレンドラベル** (文字列) が対象
- 数値レンジではなく、あらかじめ算出されたカテゴリラベルでフィルタする
- 6つのラベル値 (`improving`, `deteriorating`, `stable`, `turning_up`, `turning_down`, `volatile`) から1つを指定
- Rubyレベルでpost-filter処理

#### 現在のフィールド（8件）

| フィールド | 日本語名 |
|---|---|
| `trend_revenue` | 売上高トレンド |
| `trend_operating_income` | 営業利益トレンド |
| `trend_net_income` | 純利益トレンド |
| `trend_eps` | EPSトレンド |
| `trend_operating_margin` | 営業利益率トレンド |
| `trend_roe` | ROEトレンド |
| `trend_roa` | ROAトレンド |
| `trend_free_cf` | フリーCFトレンド |

#### トレンドラベル定義

| ラベル | 日本語名 | 意味 |
|---|---|---|
| `improving` | 改善 | 継続的に良化している |
| `deteriorating` | 悪化 | 継続的に悪化している |
| `stable` | 安定 | 大きな変動なく推移 |
| `turning_up` | 上昇転換 | 悪化から改善に転じた |
| `turning_down` | 下降転換 | 改善から悪化に転じた |
| `volatile` | 変動 | 一定の方向性なく変動 |

#### 条件構造

```json
{ "type": "trend_filter", "field": "trend_revenue", "value": "improving" }
```

#### 今後追加が想定される検索軸

- `trend_dividend_yield`: 配当利回りのトレンド
- `trend_debt_to_equity`: D/Eレシオのトレンド
- `trend_per`, `trend_pbr`: バリュエーション指標のトレンド
- `trend_gross_margin`, `trend_sga_ratio`: コスト構造のトレンド
- `trend_current_ratio`: 流動比率のトレンド
- `acceleration_consistency`: 成長加速度の一貫性ラベル（`accelerating`, `decelerating`, `mixed`）— data_jsonに既に存在するがフィルタ未公開

---

### 6. 時間軸条件 — `temporal`

#### ルール

- 単一期間ではなく **複数期間の履歴データ** を参照して判定する条件
- 専用の `MultiPeriodConditionEvaluator` で処理される
- 対象企業の過去の `financial_metrics` レコードをバッチロードし、時系列で評価する
- 他のtypeで絞り込んだ結果に対して最後に適用される（コストが高いため）
- 5つの temporal_type サブタイプを持つ

#### temporal_type サブタイプ

##### 6.1 N期中M期達成 — `at_least_n_of_m`

直近M期のうちN期以上で閾値を満たすか判定。

```json
{
  "type": "temporal",
  "temporal_type": "at_least_n_of_m",
  "field": "roe",
  "threshold": 0.10,
  "comparison": "gte",
  "n": 4,
  "m": 5
}
```

##### 6.2 N期連続改善 — `improving`

直近N期連続で値が前期比改善しているか判定。

```json
{
  "type": "temporal",
  "temporal_type": "improving",
  "field": "operating_margin",
  "n": 3
}
```

##### 6.3 N期連続悪化 — `deteriorating`

直近N期連続で値が前期比悪化しているか判定。

```json
{
  "type": "temporal",
  "temporal_type": "deteriorating",
  "field": "roe",
  "n": 2
}
```

##### 6.4 プラス転換 — `transition_positive`

ブーリアンフィールドが前期false→当期trueに転換したか判定。

```json
{
  "type": "temporal",
  "temporal_type": "transition_positive",
  "field": "free_cf_positive"
}
```

##### 6.5 マイナス転換 — `transition_negative`

ブーリアンフィールドが前期true→当期falseに転換したか判定。

```json
{
  "type": "temporal",
  "temporal_type": "transition_negative",
  "field": "operating_cf_positive"
}
```

#### 対象フィールド

- 数値フィールド（`at_least_n_of_m`, `improving`, `deteriorating`用）: `roe`, `roa`, `operating_margin`, `net_margin`, `revenue_yoy`, `operating_income_yoy`, `net_income_yoy`, `eps_yoy`
- ブーリアンフィールド（`transition_positive`, `transition_negative`用）: `free_cf_positive`, `operating_cf_positive`

#### 今後追加が想定される検索軸

- **新temporal_type**:
  - `peak_comparison`: 過去N期のピーク値との比較（最高益更新の検出など）
  - `range_narrowing` / `range_widening`: 変動幅の縮小・拡大（ボラティリティ変化の検出）
  - `acceleration`: N期連続で改善幅が拡大（成長が加速している企業の検出）
  - `mean_reversion`: 長期平均から大きく乖離した後に回帰し始めた状態の検出
- **新対象フィールド**:
  - `ordinary_margin`, `free_cf`: 現在の数値フィールド群への追加
  - `investing_cf_negative`: ブーリアンフィールドへの追加
  - `gross_margin`, `sga_ratio`, `debt_to_equity`: data_json上の数値指標をtemporal評価対象に追加

---

## Condition Type の設計原則まとめ

### なぜ6つに分かれているか

1. **データ格納場所の違い**: DBカラム vs JSON vs 別テーブル
2. **フィルタリング性能の違い**: SQL(高速) vs Ruby post-filter vs 複数期間ロード(高コスト)
3. **値の性質の違い**: 連続数値(range) vs 二値(boolean) vs カテゴリ(label/code) vs 時系列(temporal)

### 実行順序と性能への配慮

```
Phase 1: SQL WHERE (metric_range, metric_boolean, company_attribute)
    ↓ DBで効率的に候補を絞り込む
Phase 2: Ruby post-filter (data_json_range, trend_filter, turning_point)
    ↓ JSON内の値をRubyで評価
Phase 3: Temporal evaluation (temporal)
    ↓ 残った候補の履歴を一括ロードし時系列評価
最終結果
```

この3段階パイプラインにより、高コストな処理の対象を段階的に絞り込み、効率的な検索を実現している。

### 新しいフィールドをどの type に配置するかの判断基準

| 判断条件 | 推奨type |
|---|---|
| DBカラムとして存在 + 数値range検索が主 | `metric_range` |
| DBカラムとして存在 + 二値判定が主 | `metric_boolean` |
| data_json内に格納 + 数値range検索 | `data_json_range` |
| data_json内に格納 + カテゴリラベル | `trend_filter` |
| companiesテーブルの属性 | `company_attribute` |
| 複数期間の履歴が必要 | `temporal` |
| 検索頻度が非常に高い data_json フィールド | DBカラムへの昇格を検討し `metric_range` へ |
