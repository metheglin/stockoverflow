# dev_company_financial_timeline_view

## 概要

特定企業の全期間にわたる財務データを時系列で統合し、1つの構造化されたデータとして出力するサービスを実装する。

## 背景・目的

プロジェクトの主要ユースケースである「ある企業の業績が飛躍し始める直前にどのような決算・財務上の変化があったかを調べる」を実現するには、1社について全期間の財務値・指標・成長率・バリュエーション・CF分析を時系列に並べて俯瞰できるデータ構造が必要である。

現状、financial_values と financial_metrics は個別レコードとして存在するが、1社分をまとめて時系列ビューとして提供する仕組みがない。

## 実装内容

- `app/models/company` または `app/jobs/` 配下に、企業IDを受け取り、その企業の全期間の財務データを時系列構造で返すクラス/メソッドを実装する
- 出力構造のイメージ:
  - 企業基本情報（company attributes）
  - 期間ごとの配列（fiscal_year_end 昇順）:
    - financial_values の主要カラム
    - financial_metrics の全指標
    - daily_quotes から期末日付近の株価
    - 前期比での変化量・変化率
- consolidated / non_consolidated を選択可能にする
- period_type (annual / quarterly) をフィルタ可能にする

## テスト

- 複数期間のfinancial_value/financial_metricが存在する企業に対して、正しい時系列順でデータが返ることを検証
- データが存在しない期間がある場合にエラーにならず、nilまたはスキップされることを検証

## 関連TODO

- `dev_analysis_query_layer` - クエリ層が本ビューを内部的に利用する可能性
- `plan_pre_breakthrough_pattern_analysis` - ブレイクスルー分析の基盤データ
