# dotfiles-linux

旧 `dotfiles` の後継。Ubuntu、Fedora、WSLで、最小シェル環境から開発環境まで同じリポジトリで構築する。

旧リポジトリは移行完了後にlegacyとして固定し、このリポジトリをLinux環境の唯一の正本にする。

## 対応環境

- Ubuntu
- Fedora
- WSL上のUbuntu
- x86-64 Linuxを主対象

macOSや他ディストリビューションは現在対象外。

## プロファイル

| プロファイル | 内容 | 主な用途 |
|---|---|---|
| `shell` | Zsh、Starship、Sheldon、zsh-abbr、Git | 最小CLI環境 |
| `server` | `shell` + fzf、ripgrep、tmux、Fastfetch | Ubuntu/Fedoraのサーバー |
| `development` | `server` + Node.js、uv、gh、Neovim、Stylua、開発用略語、Codex設定 | ネイティブLinux開発環境 |
| `wsl-development` | `development`と同等。Windows interop依存は含めない | WSL開発環境 |

この構成では、UbuntuのLLM処理用PCとFedoraの常時稼働サーバーは基本的に`server`、WSLは`wsl-development`を使う。開発作業を行うサブPCだけ`development`へ上げる。

通常プロファイルはsystemd等の常駐サービスを追加しない。StarshipとSheldonの処理は主に対話シェルの起動時とプロンプト描画時に限られる。Starship設定はNerd Font記号を使うため、SSH先ではなくWindows TerminalやVS Codeなど表示側のフォントをNerd Fontにする。

`development`が配置するのはCodexの設定であり、Codexクライアント本体はインストールしない。VS Code拡張や既存の導入方法をそのまま使う。

## 導入

まず実行内容を確認する。

```bash
git clone git@github.com:muray0196/dotfiles-linux.git ~/dotfiles-linux
cd ~/dotfiles-linux
./install.sh --profile server --dry-run --plan
```

問題がなければ適用する。

```bash
./install.sh --profile server --set-shell
```

WSL開発環境は次を使う。

```bash
./install.sh --profile wsl-development --set-shell
```

Windows interopを有効にしており、従来のwin32yankが必要な場合だけ明示的に追加する。

```bash
./install.sh --module win32yank
```

引数なしの`./install.sh`は、安全側として`./install.sh --profile shell`と同じ動作をする。

## 個別モジュール

プロファイルを使わず、必要な機能だけ追加できる。依存関係と必要パッケージも解決される。

```bash
./install.sh --module starship
./install.sh --module tmux --module fastfetch
```

一覧:

```bash
./install.sh --list
```

## パッケージ管理

OSと密接なパッケージは`apt`または`dnf`、ユーザー向けCLIはLinuxbrewで管理する。

- `apt` / `dnf`: Zsh、Git、Stow、tmux、ビルド依存
- Linuxbrew: Starship、Sheldon、fzf、ripgrep、Fastfetch、Neovim、Node.js、uv、gh、Stylua

Linuxbrew側はモジュール別のBrewfileで管理する。更新時にGitHub Releasesを手で追う必要はない。

```bash
./update.sh --profile server
./update.sh --profile development
```

`update.sh`は選択範囲のHomebrewパッケージとSheldonプラグインだけを更新する。`apt upgrade`や`dnf upgrade`は実行しない。

## 設定ファイルの配置

GNU Stowを使い、`modules/<name>`からホームディレクトリへシンボリックリンクを張る。

既存ファイルや旧`~/dotfiles`へのシンボリックリンクが衝突する場合、削除せず次へ退避する。

```text
~/.local/state/dotfiles-linux/backups/YYYYMMDD-HHMMSS-PID/
```

リンクだけ外す場合:

```bash
./install.sh --profile server --unstow
```

パッケージとバックアップは削除されない。

## ローカル差分

Git管理しないマシン固有のZsh設定は次へ置く。

```text
~/.zshrc.local
```

Git設定は`~/.gitconfig.local`を最後に読み込む。ホストごとの署名鍵やURL書き換えなどをここで上書きできる。

## 検証

```bash
./doctor.sh --profile server
./tests/smoke.sh
```

## 明示的に分離した副作用

以下は通常のプロファイル導入では実行しない。

```bash
# GitHub CLIを追加後、ログイン・SSH鍵登録・origin設定
./install.sh --module github
./scripts/setup-github.sh

# Docker Engine。Ubuntu/Fedora対応
./scripts/setup-docker.sh

# SearXNG + Crawl4AI
./scripts/setup-search-stack.sh
```

システム全体のアップグレード、GitHub認証、SSH鍵生成、Docker導入、systemdサービス有効化を、dotfileのリンク処理に混ぜない。

## 構造

```text
profiles/       モジュールの組み合わせ
manifests/      モジュールの依存・パッケージ・Stow・action定義
packages/       apt/dnfパッケージ群とBrewfile
modules/        ホームディレクトリへStowする設定（機能単位）
lib/            インストーラー実装
scripts/        明示実行する追加セットアップ
services/       任意サービスのテンプレート
tests/          静的検査と解決テスト
```

移行手順は[`MIGRATION.md`](MIGRATION.md)を参照。
