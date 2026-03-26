# bugfix_import_daily_quotes_job_infinite_loop

以下のコマンドを実行すると、無限ループとなってずっとおなじ期間のインポートが繰り返され終わっていない疑いがある。実際にそうであるか確認のうえ、修正して。

```
ImportDailyQuotesJob.perform_now(full: true)
```

