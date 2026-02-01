# プロジェクト固有ドキュメントインデックス（可読版）

> このファイルは人間が読みやすい形式のテンプレートです。
> 実際に使用する際は `docs_index.md`（圧縮版）を参照してください。

## 概要

このテンプレートは、プロジェクトで使用するフレームワーク・ライブラリのドキュメントインデックスを定義するためのものです。

## 使い方

1. プロジェクトのルートに `.docs/` フォルダを作成
2. 使用するフレームワークのドキュメントをダウンロード（またはシンボリックリンク）
3. このテンプレートを元に `AGENTS.md` または `CLAUDE.md` にインデックスを追加

## テンプレート構造

### 基本情報

```yaml
docs_index:
  root: ".docs/"
  important_note: "Prefer retrieval-led reasoning over pre-training-led reasoning"
  
  frameworks:
    - name: "Next.js"
      version: "16.0.0"
      path: ".docs/nextjs/"
      
    - name: "React"
      version: "19.0.0"
      path: ".docs/react/"
      
    - name: "Prisma"
      version: "6.0.0"
      path: ".docs/prisma/"
```

### ディレクトリ構造の例

```
.docs/
├── nextjs/
│   ├── 01-getting-started/
│   │   ├── 01-installation.mdx
│   │   ├── 02-project-structure.mdx
│   │   └── 03-layouts.mdx
│   ├── 02-routing/
│   │   ├── 01-defining-routes.mdx
│   │   ├── 02-pages-and-layouts.mdx
│   │   └── 03-linking-and-navigating.mdx
│   └── 03-data-fetching/
│       ├── 01-fetching-caching-revalidating.mdx
│       └── 02-server-actions.mdx
├── react/
│   ├── hooks/
│   │   ├── useState.mdx
│   │   ├── useEffect.mdx
│   │   └── use.mdx
│   └── components/
│       └── Suspense.mdx
└── prisma/
    ├── schema/
    │   ├── models.mdx
    │   └── relations.mdx
    └── client/
        └── queries.mdx
```

### 各フレームワークのセクション詳細

#### Next.js

| セクション | 内容 | ファイル例 |
|-----------|------|----------|
| getting-started | インストール、プロジェクト構造 | installation.mdx, project-structure.mdx |
| routing | ルーティング定義、ページ・レイアウト | defining-routes.mdx, pages-and-layouts.mdx |
| data-fetching | データ取得、キャッシュ、再検証 | fetching.mdx, server-actions.mdx |
| rendering | サーバーコンポーネント、クライアントコンポーネント | server-components.mdx |
| caching | use cache、cacheLife、cacheTag | caching-directives.mdx |
| api-reference | connection(), forbidden(), unauthorized() | api-reference.mdx |

#### React

| セクション | 内容 | ファイル例 |
|-----------|------|----------|
| hooks | useState, useEffect, use, useActionState | hooks/*.mdx |
| components | Suspense, ErrorBoundary | components/*.mdx |
| patterns | Server Components, Actions | patterns/*.mdx |

#### Prisma

| セクション | 内容 | ファイル例 |
|-----------|------|----------|
| schema | モデル定義、リレーション | models.mdx, relations.mdx |
| client | クエリ、トランザクション | queries.mdx, transactions.mdx |
| migrations | マイグレーション管理 | migrations.mdx |

## ダウンロードスクリプト例

```bash
#!/bin/bash
# download_docs.sh - フレームワークドキュメントをダウンロード

DOCS_DIR=".docs"
mkdir -p "$DOCS_DIR"

# Next.js (公式GitHubからclone)
git clone --depth 1 --filter=blob:none --sparse \
  https://github.com/vercel/next.js.git "$DOCS_DIR/nextjs-temp"
cd "$DOCS_DIR/nextjs-temp"
git sparse-checkout set docs
mkdir -p ../nextjs
mv docs/* ../nextjs/
cd ../..
rm -rf "$DOCS_DIR/nextjs-temp"

# または npx を使用（Next.js専用）
# npx @next/codemod@canary agents-md

echo "ドキュメントのダウンロード完了"
```

## Context7との併用

- **Context7 MCP**: 汎用的なライブラリドキュメント取得（最新版）
- **プロジェクト固有docs**: プロジェクトで使用しているバージョン固有のドキュメント

```text
推奨フロー:
1. package.json / requirements.txt でバージョン確認
2. プロジェクト固有docs があれば優先使用
3. なければ Context7 で取得（"use context7" を明記）
```

## 注意事項

- ドキュメントは定期的に更新すること
- バージョンアップ時はドキュメントも更新
- `.docs/` は `.gitignore` に追加を検討（サイズが大きい場合）
