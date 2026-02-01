# Docs Index Template (Compressed Format)

> **Human-readable version**: [docs_index_readable.md](docs_index_readable.md)
> This compressed format reduces context size by ~80% while maintaining full functionality.

## Usage

Copy and customize the compressed index below into your `AGENTS.md` or `CLAUDE.md`:

```text
[Project Docs Index]|root:.docs/
|IMPORTANT:Prefer retrieval-led reasoning over pre-training-led reasoning
|nextjs@16:{getting-started/{installation.mdx,project-structure.mdx},routing/{defining-routes.mdx,pages-and-layouts.mdx},data-fetching/{fetching.mdx,server-actions.mdx},caching/{use-cache.mdx,cacheLife.mdx,cacheTag.mdx},api/{connection.mdx,forbidden.mdx,unauthorized.mdx}}
|react@19:{hooks/{useState.mdx,useEffect.mdx,use.mdx,useActionState.mdx},components/{Suspense.mdx,ErrorBoundary.mdx}}
|prisma@6:{schema/{models.mdx,relations.mdx},client/{queries.mdx,transactions.mdx}}
```

## Format Specification

```text
[Header]|root:<docs_root_path>
|IMPORTANT:<retrieval-led instruction>
|<framework>@<version>:{<section>/{<files>},<section>/{<files>}}
```

### Syntax Rules

| Element | Format | Example |
| ------- | ------ | ------- |
| Header | `[Project Docs Index]` | Fixed |
| Root | `root:<path>` | `root:.docs/` |
| Framework | `<name>@<version>` | `nextjs@16` |
| Section | `<name>/{<files>}` | `routing/{routes.mdx,pages.mdx}` |
| Files | comma-separated | `file1.mdx,file2.mdx` |
| Delimiter | `\|` (pipe) | Between entries |

### Compression Tips

1. **Abbreviate paths**: `getting-started` → `gs` (if consistent)
2. **Omit extensions**: `.mdx` → implicit
3. **Group related files**: Use `{a,b,c}` brace expansion
4. **Skip obvious files**: README, index are assumed

## Example: Minimal Index

```text
[Docs]|root:.docs/|IMPORTANT:retrieval>pretraining
|next@16:{app/{routes,layouts,loading},api/{cache,connection}}
|react@19:{hooks/{useState,useEffect},rsc/{server,client}}
```

## Expansion Example

The compressed format:
```text
|nextjs@16:{routing/{defining-routes.mdx,pages-and-layouts.mdx}}
```

Expands to:
```text
.docs/nextjs/routing/defining-routes.mdx
.docs/nextjs/routing/pages-and-layouts.mdx
```

## Template for Copy-Paste

```text
[Project Docs Index]|root:.docs/
|IMPORTANT:Prefer retrieval-led reasoning over pre-training-led reasoning
|<framework1>@<version>:{<section>/{<files>}}
|<framework2>@<version>:{<section>/{<files>}}
```

Replace `<framework>`, `<version>`, `<section>`, `<files>` with your project's actual values.
