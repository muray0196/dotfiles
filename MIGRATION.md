# Legacy `dotfiles` からの移行

## 1. 旧リポジトリを固定する

旧環境に未コミット変更がないことを確認し、最終タグを付ける。

```bash
cd ~/dotfiles
git status
git tag legacy-final
git push origin main --tags
```

この段階ではGitHub上でArchiveにしない。新リポジトリでWSLを再現できるまで、旧リポジトリは参照用として残す。

## 2. 新リポジトリを用意する

GitHubに空の`muray0196/dotfiles-linux`を作成し、このリポジトリをpushする。

```bash
cd ~/dotfiles-linux
git remote add origin git@github.com:muray0196/dotfiles-linux.git
git push -u origin main
```

GitHub CLIを使う場合:

```bash
gh repo create muray0196/dotfiles-linux \
  --public \
  --source=. \
  --remote=origin \
  --push
```

## 3. WSLで事前確認する

```bash
cd ~/dotfiles-linux
./install.sh --profile wsl-development --dry-run --plan
```

表示されたバックアップ対象、aptパッケージ、Brewfile、Stow先を確認する。

## 4. WSLへ適用する

```bash
./install.sh --profile wsl-development --set-shell
./doctor.sh --profile wsl-development
```

旧`~/dotfiles`を参照するシンボリックリンクは、適用時にバックアップへ移される。旧リポジトリ自体は削除されない。

win32yankはWindows interop依存のため、`wsl-development`には含めていない。必要な環境だけ次を追加する。

```bash
./install.sh --module win32yank
```

Neovimを初回起動し、Lazy.nvimの取得と既存設定の動作も確認する。

## 5. サブPCへ適用する

UbuntuのLLMノード:

```bash
./install.sh --profile server --dry-run --plan
./install.sh --profile server --set-shell
./doctor.sh --profile server
```

Fedoraの常時稼働サーバーも同じ`server`を使う。

```bash
./install.sh --profile server --dry-run --plan
./install.sh --profile server --set-shell
./doctor.sh --profile server
```

## 6. legacy化する

WSL、Ubuntu、Fedoraで問題がないことを確認した後、GitHubの旧`dotfiles`をArchiveする。ローカルの旧リポジトリも、すぐ削除せず一定期間残す。

移行後の変更先は`dotfiles-linux`だけにする。
