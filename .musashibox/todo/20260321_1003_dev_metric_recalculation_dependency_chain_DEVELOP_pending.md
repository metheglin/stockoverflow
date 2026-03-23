# メトリクス再計算の依存チェーン管理

## 概要

FinancialValueが追加・更新された際に、その期間のFinancialMetricだけでなく、YoY計算や連続成長カウンターを通じて影響を受ける隣接期間のメトリクスも正しく再計算されるよう、依存関係を追跡する仕組みを実装する。

## 背景・動機

### 現状の問題

`CalculateFinancialMetricsJob` は以下の条件で再計算対象を判定している:
- FinancialMetricが存在しない FinancialValue
- FinancialValue の updated_at が FinancialMetric の updated_at より新しいもの

しかし、この判定では以下のケースで不整合が発生する:

1. **過去データの遅延取り込み**: 2024年3月期のデータが後から取り込まれた場合、2025年3月期のYoY計算（revenue_yoy等）は更新されない（2025年3月期のFinancialValueは変更されていないため）
2. **連続成長カウンターの波及**: 2023年3月期のデータ修正により consecutive_revenue_growth の値が変わると、2024年・2025年のカウンター値も全て影響を受ける
3. **サプライズ指標の逆方向依存**: 予想値（forecast_*）は前期のFinancialValueに格納されるため、前期データの修正が当期のサプライズ計算に影響する

### import_metric_cascade_automation (20260320_1900) との違い

そのTODOは「インポート後にメトリクス計算をトリガーする」ことにフォーカス。
本TODOは「どの期間のメトリクスを再計算すべきかを正確に特定する」依存関係解析にフォーカス。

## 実装方針

### 影響範囲の特定ロジック

```ruby
class FinancialMetric::DependencyResolver
  # 変更されたFinancialValueから影響を受ける全FinancialValueのIDを返す
  def get_affected_financial_value_ids(changed_financial_value)
    affected = Set.new
    affected << changed_financial_value.id

    # 次期のFinancialValue（YoY計算に影響）
    next_fv = find_next_period(changed_financial_value)
    affected << next_fv.id if next_fv

    # 連続成長カウンターの波及（後続の全期間）
    propagate_consecutive_impact(changed_financial_value, affected)

    affected.to_a
  end
end
```

### CalculateFinancialMetricsJob への統合

- `recalculate_for` オプションを追加: 指定された FinancialValue ID のみを再計算
- DependencyResolver の結果を `recalculate_for` に渡す

### 再計算キューイング

- FinancialValue の after_save コールバック（または明示的な呼び出し）で DependencyResolver を実行
- 影響を受ける FinancialValue の ID リストを ApplicationProperty に記録
- 次回の CalculateFinancialMetricsJob 実行時にキューを消化

## 備考

- 依存関係の深さに上限を設ける（連続成長カウンターの波及は最大10期程度で十分）
- パフォーマンスへの影響を考慮し、フル再計算（recalculate: true）時はこの機構をスキップ
