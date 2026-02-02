#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# CLI Adapter - マルチAI CLIの統一インターフェース
# ═══════════════════════════════════════════════════════════════════════════════
# 対応CLI（コーディングエージェント）:
#   - claude: Claude Code CLI (Anthropic) - OpenAI互換バックエンド対応
#   - codex: OpenAI Codex CLI - OpenAI互換バックエンド対応
#   - crush: Charm Crush CLI - OpenAI互換バックエンド対応
#   - goose: Block Goose CLI - OpenAI互換バックエンド対応
#   - copilot: GitHub Copilot CLI
#   - gemini: Google Gemini CLI
#
# 軍目付（検分役 - 指揮系統とは独立）:
#   - coderabbit: 工兎（こうと）- 検分専門の監察役
#
# OpenAI互換バックエンド（GLM等）:
#   claude, codex, crush, goose で backend 設定により使用可能
#
# 使用方法:
#   source lib/cli_adapter.sh
#   cli_type=$(get_cli_type "karo" "config/settings.yaml")
#   cli_command=$(build_cli_command "karo" "$cli_type" "config/settings.yaml")
# ═══════════════════════════════════════════════════════════════════════════════

# サポートされているCLIタイプ（コーディングエージェント）
SUPPORTED_CLI_TYPES="claude codex crush goose copilot gemini"

# OpenAI互換バックエンドをサポートするCLI
OPENAI_COMPAT_CLI_TYPES="claude codex crush goose"

# ═══════════════════════════════════════════════════════════════════════════════
# YAMLパーサー経由でCLI設定を取得
# ═══════════════════════════════════════════════════════════════════════════════
# 引数:
#   $1: settings.yamlのパス
#   $2: エージェント名
#   $3: キー ("type" or "default")
# 出力: 値（存在しない場合は空）
get_cli_config_value() {
    local yaml_config="$1"
    local agent_name="$2"
    local key="$3"
    local value=""

    if [ ! -f "$yaml_config" ]; then
        echo ""
        return 0
    fi

    if command -v python3 &>/dev/null; then
        value=$(python3 - "$yaml_config" "$agent_name" "$key" << 'PY'
import sys

path, agent, key = sys.argv[1:4]
try:
    import yaml
except Exception:
    sys.exit(2)

try:
    with open(path, 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f) or {}
except Exception:
    sys.exit(1)

if not isinstance(data, dict):
    data = {}

cli = data.get('cli', {}) if isinstance(data.get('cli', {}), dict) else {}

if key == "default":
    val = cli.get('default') if isinstance(cli, dict) else None
else:
    agents = cli.get('agents', {}) if isinstance(cli, dict) else {}
    val = None
    if isinstance(agents, dict):
        agent_cfg = agents.get(agent, {})
        if isinstance(agent_cfg, dict):
            val = agent_cfg.get('type')

if isinstance(val, (str, int, float, bool)):
    sys.stdout.write(str(val))
PY
)
        if [ $? -eq 0 ]; then
            echo "$value"
            return 0
        fi
    fi

    if command -v yq &>/dev/null; then
        # mikefarah/yq と kislyuk/yq (jq wrapper) の両方に対応
        # mikefarah/yq は --arg をサポートしないため、直接パスを埋め込む
        if [ "$key" = "default" ]; then
            value=$(yq -r '.cli.default // ""' "$yaml_config" 2>/dev/null)
        else
            # mikefarah/yq 用の構文（変数展開で直接パスを構築）
            value=$(yq -r ".cli.agents.${agent_name}.type // \"\"" "$yaml_config" 2>/dev/null)
        fi
        echo "$value"
        return 0
    fi

    echo ""
    return 0
}

# CLIタイプを取得（エージェント名から）
# 引数:
#   $1: エージェント名 (karo, busho, ashigaru1-8)
#   $2: settings.yamlのパス
# 出力: CLIタイプ
get_cli_type() {
    local agent_name="$1"
    local yaml_config="$2"
    local agent_type=""
    local default_type=""

    # ファイルが存在しない場合はデフォルト
    if [ ! -f "$yaml_config" ]; then
        echo "claude"
        return 0
    fi

    # YAMLパーサーでエージェント固有のCLIタイプを取得
    agent_type=$(get_cli_config_value "$yaml_config" "$agent_name" "type")

    if [ -n "$agent_type" ]; then
        # バリデーション: サポートされているCLIのみ許可
        if echo "$SUPPORTED_CLI_TYPES" | grep -qw "$agent_type"; then
            echo "$agent_type"
        else
            echo "claude"  # 不正値の場合はデフォルト
        fi
    else
        # デフォルトCLIタイプを取得
        default_type=$(get_cli_config_value "$yaml_config" "$agent_name" "default")

        # バリデーション
        if echo "$SUPPORTED_CLI_TYPES" | grep -qw "$default_type"; then
            echo "$default_type"
        else
            echo "claude"  # 不正値またはデフォルト
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# バックエンド設定があるかチェック
# ═══════════════════════════════════════════════════════════════════════════════
has_backend_config() {
    local agent_name="$1"
    local yaml_config="$2"

    if [ ! -f "$yaml_config" ]; then
        return 1
    fi

    local has_backend=$(awk -v agent="$agent_name" '
        /^cli:/ { in_cli=1; next }
        in_cli && /^  agents:/ { in_agents=1; next }
        in_agents && $0 ~ "^    " agent ":" { in_target=1; next }
        in_target && /^      backend:/ { print "yes"; exit }
        in_target && /^    [a-z]/ { exit }
        /^[a-z]/ { exit }
    ' "$yaml_config")

    [ "$has_backend" = "yes" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# バックエンド設定を取得
# ═══════════════════════════════════════════════════════════════════════════════
get_backend_config() {
    local agent_name="$1"
    local config_key="$2"
    local yaml_config="$3"

    if [ ! -f "$yaml_config" ]; then
        return 0
    fi

    awk -v agent="$agent_name" -v key="$config_key" '
        /^cli:/ { in_cli=1; next }
        in_cli && /^  agents:/ { in_agents=1; next }
        in_agents && $0 ~ "^    " agent ":" { in_target=1; next }
        in_target && /^      backend:/ { in_backend=1; next }
        in_backend && $0 ~ "^        " key ":" { gsub(/^        [^:]+: */, ""); print; exit }
        in_backend && /^      [a-z]/ { exit }
        in_target && /^    [a-z]/ { exit }
        /^[a-z]/ { exit }
    ' "$yaml_config" | tr -d '"' | tr -d "'"
}

# ═══════════════════════════════════════════════════════════════════════════════
# バックエンド設定を適用（env_vars / options を更新）
# 引数:
#   $1: エージェント名
#   $2: settings.yamlのパス
#   $3: env_vars の変数名
#   $4: options の変数名
# ═══════════════════════════════════════════════════════════════════════════════
_apply_backend_config() {
    local agent_name="$1"
    local yaml_config="$2"
    local env_vars_name="$3"
    local options_name="$4"
    local backend_url backend_key backend_model

    backend_url=$(get_backend_config "$agent_name" "base_url" "$yaml_config")
    backend_key=$(get_backend_config "$agent_name" "api_key_env" "$yaml_config")
    backend_model=$(get_backend_config "$agent_name" "model" "$yaml_config")

    if [ -n "$backend_url" ]; then
        printf -v "$env_vars_name" '%s OPENAI_BASE_URL="%s"' "${!env_vars_name}" "$backend_url"
    fi
    if [ -n "$backend_key" ]; then
        printf -v "$env_vars_name" '%s OPENAI_API_KEY="\${%s}"' "${!env_vars_name}" "$backend_key"
    fi
    if [ -n "$backend_model" ]; then
        printf -v "$options_name" '%s --model "%s"' "${!options_name}" "$backend_model"
    fi
}

# エージェント用のCLIコマンドを構築
# 引数:
#   $1: エージェント名 (karo, busho, ashigaru1-8)
#   $2: CLIタイプ
#   $3: settings.yamlのパス
# 出力: 実行可能なコマンド文字列
build_cli_command() {
    local agent_name="$1"
    local cli_type="$2"
    local yaml_config="$3"

    local base_cmd=""
    local options=""
    local env_vars=""

    # バックエンド設定のチェック（OpenAI互換バックエンド）
    local use_backend=false
    if has_backend_config "$agent_name" "$yaml_config"; then
        if echo "$OPENAI_COMPAT_CLI_TYPES" | grep -qw "$cli_type"; then
            use_backend=true
        fi
    fi

    case "$cli_type" in
        claude)
            # ─────────────────────────────────────────────────────────────────
            # Claude Code CLI
            # インストール: npm install -g @anthropic-ai/claude-code
            # OpenAI互換バックエンド対応
            # ─────────────────────────────────────────────────────────────────
            base_cmd="claude"
            env_vars=$(get_agent_env "$agent_name" "$yaml_config")

            if [ "$use_backend" = true ]; then
                _apply_backend_config "$agent_name" "$yaml_config" env_vars options
            else
                local model
                model=$(get_agent_model "$agent_name" "$yaml_config")
                if [ -n "$model" ]; then
                    options="--model \"$model\""
                fi
            fi

            options="$options --dangerously-skip-permissions"
            ;;

        codex)
            # ─────────────────────────────────────────────────────────────────
            # OpenAI Codex CLI
            # インストール: npm install -g @openai/codex
            # OpenAI互換バックエンド対応
            # ─────────────────────────────────────────────────────────────────
            base_cmd="codex"
            env_vars=$(get_agent_env "$agent_name" "$yaml_config")

            if [ "$use_backend" = true ]; then
                _apply_backend_config "$agent_name" "$yaml_config" env_vars options
            else
                local model
                model=$(get_agent_model "$agent_name" "$yaml_config")
                if [ -n "$model" ]; then
                    options="--model \"$model\""
                fi
            fi

            options="$options --approval-mode full-auto"
            ;;

        crush)
            # ─────────────────────────────────────────────────────────────────
            # Charm Crush CLI
            # インストール: brew install charmbracelet/tap/crush
            #           または npm install -g @charmland/crush
            # OpenAI互換バックエンド対応
            # ─────────────────────────────────────────────────────────────────
            base_cmd="crush"
            env_vars=$(get_agent_env "$agent_name" "$yaml_config")

            if [ "$use_backend" = true ]; then
                _apply_backend_config "$agent_name" "$yaml_config" env_vars options
            else
                local model
                model=$(get_agent_model "$agent_name" "$yaml_config")
                if [ -n "$model" ]; then
                    options="--model \"$model\""
                fi
            fi

            # YOLOモード（自動承認）
            options="$options --yolo"
            ;;

        goose)
            # ─────────────────────────────────────────────────────────────────
            # Block Goose CLI
            # インストール: curl -fsSL https://github.com/block/goose/raw/main/download_cli.sh | bash
            # OpenAI互換バックエンド対応
            # ─────────────────────────────────────────────────────────────────
            base_cmd="goose"
            env_vars=$(get_agent_env "$agent_name" "$yaml_config")

            if [ "$use_backend" = true ]; then
                _apply_backend_config "$agent_name" "$yaml_config" env_vars options
            else
                local model
                model=$(get_agent_model "$agent_name" "$yaml_config")
                if [ -n "$model" ]; then
                    options="--model \"$model\""
                fi
            fi
            ;;

        copilot)
            # ─────────────────────────────────────────────────────────────────
            # GitHub Copilot CLI
            # インストール: https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli
            # バックエンド変更不可（GitHub認証）
            # ─────────────────────────────────────────────────────────────────
            base_cmd="copilot"
            env_vars=$(get_agent_env "$agent_name" "$yaml_config")
            # 全ツールを自動承認（シェルコマンド、ファイル書き込み等）
            options="--allow-all-tools"

            # モデル設定（settings.yamlから読み込み）
            local model
            model=$(get_agent_model "$agent_name" "$yaml_config")
            if [ -n "$model" ]; then
                options="$options --model $model"
            fi
            ;;

        gemini)
            # ─────────────────────────────────────────────────────────────────
            # Google Gemini CLI
            # インストール: npm install -g @google/gemini-cli
            # バックエンド変更不可（Google認証）
            # ─────────────────────────────────────────────────────────────────
            base_cmd="gemini"
            env_vars=$(get_agent_env "$agent_name" "$yaml_config")

            local model
            model=$(get_agent_model "$agent_name" "$yaml_config")
            if [ -n "$model" ]; then
                options="--model \"$model\""
            fi

            # YOLOモード（自動承認）
            options="$options --yolo"
            ;;

        *)
            echo "Error: Unknown CLI type: $cli_type" >&2
            return 1
            ;;
    esac

    # 環境変数 + コマンド + オプション
    if [ -n "$env_vars" ]; then
        echo "${env_vars} ${base_cmd} ${options}"
    else
        echo "${base_cmd} ${options}"
    fi
}

# エージェント固有のモデル設定を取得
# 引数:
#   $1: エージェント名
#   $2: settings.yamlのパス
# 出力: モデル名（なければ空文字）
get_agent_model() {
    local agent_name="$1"
    local yaml_config="$2"

    if [ ! -f "$yaml_config" ]; then
        return 0
    fi

    awk -v agent="$agent_name" '
        /^cli:/ { in_cli=1; next }
        in_cli && /^  agents:/ { in_agents=1; next }
        in_agents && $0 ~ "^    " agent ":" { in_target=1; next }
        in_target && /^      model:/ { print $2; exit }
        in_target && /^    [a-z]/ { exit }
        /^[a-z]/ { exit }
    ' "$yaml_config" | tr -d '"' | tr -d "'"
}

# エージェント固有の設定値を取得
# 引数:
#   $1: エージェント名
#   $2: 設定キー (base_url, api_key_env など)
#   $3: settings.yamlのパス
# 出力: 設定値（なければ空文字）
get_agent_config() {
    local agent_name="$1"
    local config_key="$2"
    local yaml_config="$3"

    if [ ! -f "$yaml_config" ]; then
        return 0
    fi

    awk -v agent="$agent_name" -v key="$config_key" '
        /^cli:/ { in_cli=1; next }
        in_cli && /^  agents:/ { in_agents=1; next }
        in_agents && $0 ~ "^    " agent ":" { in_target=1; next }
        in_target && $0 ~ "^      " key ":" { print $2; exit }
        in_target && /^    [a-z]/ { exit }
        /^[a-z]/ { exit }
    ' "$yaml_config" | tr -d '"' | tr -d "'"
}

# エージェント固有の環境変数を取得
# 引数:
#   $1: エージェント名
#   $2: settings.yamlのパス
# 出力: 環境変数の設定文字列（例: "MAX_THINKING_TOKENS=0"）
get_agent_env() {
    local agent_name="$1"
    local yaml_config="$2"

    if [ ! -f "$yaml_config" ]; then
        return 0
    fi

    # エージェント設定ブロックを抽出
    local env_str=""
    local in_agent=false
    local in_env=false

    while IFS= read -r line; do
        # エージェントセクション開始（厳密なインデントチェック）
        if echo "$line" | grep -q "^    ${agent_name}:"; then
            in_agent=true
            continue
        fi

        # 次のエージェントセクション開始（終了）
        if [ "$in_agent" = true ] && echo "$line" | grep -q "^    [a-z]"; then
            break
        fi

        # env セクション開始
        if [ "$in_agent" = true ] && echo "$line" | grep -q "^      env:"; then
            in_env=true
            continue
        fi

        # env の値を取得
        if [ "$in_agent" = true ] && [ "$in_env" = true ]; then
            if echo "$line" | grep -q "^        [A-Z_]"; then
                local key=$(echo "$line" | awk '{print $1}' | tr -d ':')
                local value=$(echo "$line" | awk '{print $2}' | tr -d '"' | tr -d "'")

                # 環境変数の置換（${VAR_NAME} 形式）
                if echo "$value" | grep -q '^\${.*}$'; then
                    local var_name=$(echo "$value" | sed 's/\${//g' | sed 's/}//g')
                    value="${!var_name}"
                fi

                if [ -n "$env_str" ]; then
                    env_str="$env_str "
                fi
                env_str="${env_str}${key}=${value}"
            elif echo "$line" | grep -q "^      [a-z]"; then
                # env セクション終了
                break
            fi
        fi
    done < "$yaml_config"

    echo "$env_str"
}

# CLI が利用可能かチェック
# 引数:
#   $1: CLIタイプ
# 戻り値: 0=利用可能, 1=利用不可
validate_cli_availability() {
    local cli_type="$1"

    case "$cli_type" in
        claude)
            if ! command -v claude &>/dev/null; then
                echo "Error: Claude Code CLI が見つかりません" >&2
                echo "インストール: npm install -g @anthropic-ai/claude-code" >&2
                return 1
            fi
            return 0
            ;;

        codex)
            if ! command -v codex &>/dev/null; then
                echo "Error: Codex CLI が見つかりません" >&2
                echo "インストール: npm install -g @openai/codex" >&2
                return 1
            fi
            return 0
            ;;

        crush)
            if ! command -v crush &>/dev/null; then
                echo "Error: Crush CLI が見つかりません" >&2
                echo "インストール: brew install charmbracelet/tap/crush" >&2
                echo "または: npm install -g @charmland/crush" >&2
                return 1
            fi
            return 0
            ;;

        goose)
            if ! command -v goose &>/dev/null; then
                echo "Error: Goose CLI が見つかりません" >&2
                echo "インストール: curl -fsSL https://github.com/block/goose/raw/main/download_cli.sh | bash" >&2
                return 1
            fi
            return 0
            ;;

        copilot)
            if ! command -v copilot &>/dev/null; then
                echo "Error: GitHub Copilot CLI が見つかりません" >&2
                echo "インストール: https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli" >&2
                return 1
            fi
            return 0
            ;;

        gemini)
            if ! command -v gemini &>/dev/null; then
                echo "Error: Gemini CLI が見つかりません" >&2
                echo "インストール: npm install -g @google/gemini-cli" >&2
                echo "または: brew install gemini-cli" >&2
                return 1
            fi
            return 0
            ;;

        *)
            echo "Error: Unknown CLI type: $cli_type" >&2
            return 1
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# 工兎（こうと）- 軍目付（CodeRabbit統合）
# ═══════════════════════════════════════════════════════════════════════════════
# 工兎は「軍目付」として、コードの監察・検分を担う役職。
# 指揮系統（家老-部将-足軽）とは独立した監察役として横に配置。
# 汎用タスクはできず、検分専門。
#
# 組織図:
#   家老 → 部将 → 足軽（指揮系統）
#            │
#            ├── 工兎（軍目付）← 監察役（検分専門）
#
# 使用パターン（修正タスク再分配フロー）:
#   1. 足軽がコードを実装
#   2. 足軽が工兎殿にレビューを依頼（coderabbit --prompt-only、7-30分）
#   3. 工兎殿の検分結果を queue/reports/ に報告（部将への通知）
#   4. 部将が検分結果を分析し、修正タスクを分解
#   5. 部将が修正タスクを複数足軽に再分配（並列修正）
#
# このフローにより:
#   - 検分結果が膨大でも1人の足軽に負荷集中しない
#   - 修正タスクを複数足軽で並列処理可能
#   - 部将がボトルネックを防ぐ
# ═══════════════════════════════════════════════════════════════════════════════

# 工兎（軍目付）CLIが利用可能かチェック
# 戻り値: 0=利用可能, 1=利用不可
validate_coderabbit_availability() {
    if ! command -v coderabbit &>/dev/null; then
        echo "Error: 工兎（軍目付）CLI が見つかりません" >&2
        echo "インストール: curl -fsSL https://cli.coderabbit.ai/install.sh | sh" >&2
        echo "認証: coderabbit auth login" >&2
        return 1
    fi
    return 0
}

# 工兎（軍目付）検分コマンドを構築
# 引数:
#   $1: 検分モード (interactive, plain, prompt-only)
#   $2: 検分タイプ (all, committed, uncommitted)
#   $3: ベースブランチ（オプション）
# 出力: 実行可能なコマンド文字列
build_coderabbit_command() {
    local mode="${1:-prompt-only}"
    local review_type="${2:-uncommitted}"
    local base_branch="$3"

    local cmd="coderabbit"

    case "$mode" in
        interactive)
            # デフォルト（対話モード）
            ;;
        plain)
            cmd="$cmd --plain"
            ;;
        prompt-only)
            cmd="$cmd --prompt-only"
            ;;
    esac

    if [ -n "$review_type" ]; then
        cmd="$cmd --type $review_type"
    fi

    if [ -n "$base_branch" ]; then
        cmd="$cmd --base $base_branch"
    fi

    echo "$cmd"
}

# 工兎（軍目付）の表示情報
get_coderabbit_display_name() {
    echo "工兎（軍目付）"
}

get_coderabbit_icon() {
    echo "🐰"
}

# CLI用の指示書を生成
# 引数:
#   $1: エージェント名
#   $2: CLIタイプ
#   $3: 指示書ディレクトリ (instructions/)
#   $4: 出力先
generate_cli_instructions() {
    local agent_name="$1"
    local cli_type="$2"
    local instructions_dir="$3"
    local output_file="$4"

    # 足軽1-8の場合は ashigaru.md を使用
    local base_name="$agent_name"
    if [[ "$agent_name" =~ ^ashigaru[1-8]$ ]]; then
        base_name="ashigaru"
    fi

    local instruction_file="${instructions_dir}/${base_name}.md"

    if [ ! -f "$instruction_file" ]; then
        echo "Warning: Instruction file not found: $instruction_file" >&2
        return 1
    fi

    # 出力ディレクトリを作成
    mkdir -p "$(dirname "$output_file")"

    # 指示書をコピー
    cat "$instruction_file" > "$output_file"

    # グローバルコンテキストを追加（存在する場合）
    if [ -f "memory/global_context.md" ]; then
        echo "" >> "$output_file"
        echo "---" >> "$output_file"
        echo "" >> "$output_file"
        cat "memory/global_context.md" >> "$output_file"
    fi

    return 0
}

# CLIの表示名を取得
# 引数:
#   $1: CLIタイプ
# 出力: 表示名
get_cli_display_name() {
    local cli_type="$1"

    case "$cli_type" in
        claude)     echo "Claude Code" ;;
        codex)      echo "Codex CLI" ;;
        crush)      echo "Crush" ;;
        goose)      echo "Goose" ;;
        copilot)    echo "GitHub Copilot CLI" ;;
        gemini)     echo "Gemini CLI" ;;
        *)          echo "$cli_type" ;;
    esac
}

# CLIのアイコンを取得
# 引数:
#   $1: CLIタイプ
# 出力: アイコン
get_cli_icon() {
    local cli_type="$1"

    case "$cli_type" in
        claude)     echo "🧠" ;;
        codex)      echo "🤖" ;;
        crush)      echo "💘" ;;
        goose)      echo "🪿" ;;
        copilot)    echo "⚡" ;;
        gemini)     echo "💎" ;;
        *)          echo "🔧" ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# バックエンドの表示名を取得
# ═══════════════════════════════════════════════════════════════════════════════
get_backend_display_name() {
    local agent_name="$1"
    local yaml_config="$2"

    if ! has_backend_config "$agent_name" "$yaml_config"; then
        return 0
    fi

    local backend_url=$(get_backend_config "$agent_name" "base_url" "$yaml_config")

    # URLからバックエンド名を推測
    case "$backend_url" in
        *bigmodel.cn*) echo "GLM" ;;
        *deepseek*) echo "DeepSeek" ;;
        *openai*) echo "OpenAI" ;;
        *) echo "Custom" ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# エージェントのカテゴリを取得
# ═══════════════════════════════════════════════════════════════════════════════
get_agent_categories() {
    local agent_name="$1"
    local yaml_config="$2"

    if [ ! -f "$yaml_config" ]; then
        echo "ALL"
        return 0
    fi

    local categories=$(awk -v agent="$agent_name" '
        /^cli:/ { in_cli=1; next }
        in_cli && /^  agents:/ { in_agents=1; next }
        in_agents && $0 ~ "^    " agent ":" { in_target=1; next }
        in_target && /^      categories:/ { gsub(/^      categories: *\[?/, ""); gsub(/\].*$/, ""); print; exit }
        in_target && /^    [a-z]/ { exit }
        /^[a-z]/ { exit }
    ' "$yaml_config" | tr -d '"' | tr -d "'" | tr ',' ' ')

    if [ -n "$categories" ]; then
        echo "$categories"
    else
        echo "ALL"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 足軽名簿（agent_roster.md）を生成
# ═══════════════════════════════════════════════════════════════════════════════
generate_agent_roster() {
    local yaml_config="$1"
    local output_file="$2"

    mkdir -p "$(dirname "$output_file")"

    cat > "$output_file" << 'ROSTER_HEADER'
# 🎯 足軽名簿（部将参照用）

このファイルは起動時に自動生成されます。
各足軽の能力（カテゴリ）を確認し、適切なタスクを割り振ってください。

## カテゴリ凡例

| カテゴリ | 説明 |
|----------|------|
| `coding_advanced` | 高度なコーディング（設計、リファクタ、複雑なロジック） |
| `coding_standard` | 標準的なコーディング（機能実装、バグ修正） |
| `coding_simple` | 単純なコーディング（定型コード、ファイル作成） |
| `docs_technical` | 技術文書（API仕様、設計書） |
| `docs_general` | 一般文書（README、翻訳、コメント） |
| `review_code` | コードレビュー |
| `review_security` | セキュリティ監査 |
| `analysis_design` | 設計分析 |
| `analysis_debug` | デバッグ・問題調査 |
| `ALL` | 全カテゴリ対応（万能型） |

## 足軽一覧

| 足軽 | CLI | バックエンド | 対応カテゴリ |
|------|-----|-------------|-------------|
ROSTER_HEADER

    local agents=("ashigaru1" "ashigaru2" "ashigaru3" "ashigaru4" "ashigaru5" "ashigaru6" "ashigaru7" "ashigaru8")

    for agent in "${agents[@]}"; do
        local cli_type=$(get_cli_type "$agent" "$yaml_config")
        local cli_icon=$(get_cli_icon "$cli_type")
        local cli_name=$(get_cli_display_name "$cli_type")
        local backend=$(get_backend_display_name "$agent" "$yaml_config")
        local categories=$(get_agent_categories "$agent" "$yaml_config")

        if [ -n "$backend" ]; then
            backend="+$backend"
        else
            backend="-"
        fi

        # カテゴリをバッククォートで囲む
        local formatted_categories=""
        for cat in $categories; do
            if [ -n "$formatted_categories" ]; then
                formatted_categories="$formatted_categories, "
            fi
            formatted_categories="${formatted_categories}\`${cat}\`"
        done

        echo "| $agent | $cli_icon $cli_name | $backend | $formatted_categories |" >> "$output_file"
    done

    cat >> "$output_file" << 'ROSTER_FOOTER'

## 使用上の注意

1. **カテゴリ確認必須**: タスクを振る前に、必ず対応カテゴリを確認せよ
2. **万能型は温存**: `ALL` の足軽は高度なタスク用に温存し、特化型を優先せよ
3. **レビュー専用注意**: `review_*` のみの足軽にはコーディングタスクを振るな

## 更新日時

ROSTER_FOOTER

    echo "生成: $(date '+%Y-%m-%d %H:%M:%S')" >> "$output_file"
}

