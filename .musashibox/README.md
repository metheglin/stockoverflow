# musashibox

musashiboxは、Dockerコンテナ上でclaude全権限付与モードで起動する開発ツール

## Project Management

musashiboxは `config/project-management.md` に記載されたルールでプロジェクトマネジメントをおこなう。  
このファイルを `${PROJECT_DIR}/.claude/rules/` 以下にコピー配置する必要がある。

## Install & Running

### Requirements

- Docker
- Claude(Anthropic) Account
  - API_KEY or OAUTH_TOKEN

### Install

- `.env`
- `project-management.md`
- `ssh-keys/`

```bash
cd .musashibox

# ============
# SSH Keyの生成
# ============
# git repository管理のためのSSH Key
./setup-keys.sh
```

### Run

```bash
cd .musashibox
./run.sh
```

## cron

```bash
0 */2 * * * /path/to/project/.musashibox/run.sh >> /path/to/project/.musashibox/log/musashibox.log 2>&1
```

- cronが起動するか・しているかの確認は毎分実行で `say "Hello"` コマンドでのデバッグ推奨
- OS設定でスリープしない設定追加
  - MacMiniとMacBookではスリープまわりの設定メニューがどうやら異なる点に注意（MacMiniは電源接続を前提とするため）
  - `sudo pmset -a sleep 0`
- `run.sh` はDockerをよびだすが、cron起動の場合でもDockerのパスが通っている必要がある。必要に応じて `run.sh` ファイル内のPATH宣言を書き換えること
- `cron` プロセスにフルディスクアクセスを許可
  - 設定 > プライバシーとセキュリティ > フルディスクアクセス > `/usr/sbin/cron` を追加
  - 追加しても表示されないバグあるケースがある
