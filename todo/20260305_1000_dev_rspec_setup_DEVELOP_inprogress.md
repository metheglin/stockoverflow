# RSpec導入・テスト基盤の構築

## 概要

テスティング規約で指定されている RSpec を導入し、テスト基盤を整備する。
現状はRails標準の minitest (`test/`) ディレクトリ構成になっているため、RSpecへの切り替えが必要。

## 作業内容

1. Gemfile に `rspec-rails` を追加し、`bundle install` を実行する
2. `rails generate rspec:install` を実行して初期ファイルを生成する
3. `spec/rails_helper.rb` を適切に設定する
4. 不要な `test/` ディレクトリを削除する（minitest関連のテストファイル）
5. 基本的な動作確認として `rspec` コマンドが正常に動作することを確認する

## 備考

- factory_bot 等のテスト支援ツールの導入は、モデル実装と合わせて検討するため、この段階では最低限の構成にとどめる
