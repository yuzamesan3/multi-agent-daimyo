#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════════════════════════
# 足軽再起動スクリプト（マルチCLI対応）
# settings.yaml から元のCLIタイプを取得し、同じCLIで再起動する
# ═══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_ROOT/config/settings.yaml"
CLI_ADAPTER="$PROJECT_ROOT/lib/cli_adapter.sh"

PANE_ID="$1"
TASK_MESSAGE="$2"
TIMEOUT=30

# 引数チェック
if [ -z "$PANE_ID" ]; then
  echo "Usage: $0 <pane_id> [task_message]"
  echo ""
  echo "Examples:"
  echo "  $0 multiagent:0.2                          # 足軽2を再起動"
  echo "  $0 multiagent:0.5 'タスクを実行せよ'          # 足軽5を再起動し指示送信"
  exit 1
fi

# CLI Adapterをロード
if [ -f "$CLI_ADAPTER" ]; then
  source "$CLI_ADAPTER"
else
  echo "❌ CLI Adapter が見つかりません: $CLI_ADAPTER"
  exit 1
fi

# ペインIDからエージェント名を取得
# multiagent:0.0 → busho, multiagent:0.1 → ashigaru-daisho, multiagent:0.2-8 → ashigaru2-8
get_agent_name_from_pane() {
  local pane_id="$1"
  local pane_num="${pane_id##*.}"  # multiagent:0.X → X
  
  case "$pane_num" in
    0) echo "busho" ;;
    1) echo "ashigaru-daisho" ;;
    2|3|4|5|6|7|8) echo "ashigaru${pane_num}" ;;
    *) echo "" ;;
  esac
}

# CLIタイプに応じた終了コマンドを取得
get_exit_command() {
  local cli_type="$1"
  case "$cli_type" in
    claude)   echo "/exit" ;;
    crush)    echo "/exit" ;;
    copilot)  echo "/exit" ;;
    gemini)   echo "/exit" ;;
    codex)    echo "/exit" ;;
    goose)    echo "/exit" ;;
    *)        echo "/exit" ;;
  esac
}

# CLIタイプに応じた起動完了判定パターンを取得
get_ready_pattern() {
  local cli_type="$1"
  case "$cli_type" in
    claude)   echo "bypass permissions" ;;
    crush)    echo "" ;;  # Crushは表示領域依存のため固定時間待機
    copilot)  echo "Type @ to mention" ;;
    gemini)   echo "Tips for getting started|/help for more" ;;
    codex)    echo ">" ;;
    goose)    echo ">" ;;
    *)        echo ">|❯|\$" ;;
  esac
}

# エージェント名を取得
AGENT_NAME=$(get_agent_name_from_pane "$PANE_ID")
if [ -z "$AGENT_NAME" ]; then
  echo "❌ 無効なペインID: $PANE_ID"
  echo "   有効なペイン: multiagent:0.0 (busho), multiagent:0.1 (ashigaru-daisho), multiagent:0.2-8 (ashigaru2-8)"
  exit 1
fi

# CLIタイプを取得
CLI_TYPE=$(get_cli_type "$AGENT_NAME" "$CONFIG_FILE")
CLI_ICON=$(get_cli_icon "$CLI_TYPE" 2>/dev/null || echo "🤖")
CLI_NAME=$(get_cli_display_name "$CLI_TYPE" 2>/dev/null || echo "$CLI_TYPE")

echo "🔄 足軽再起動開始: $PANE_ID ($AGENT_NAME)"
echo "   CLI: $CLI_NAME $CLI_ICON"

# 1. 現在のCLI終了
echo "  → 現在のCLIを終了中..."
tmux send-keys -t "$PANE_ID" C-c
sleep 1
EXIT_CMD=$(get_exit_command "$CLI_TYPE")
tmux send-keys -t "$PANE_ID" "$EXIT_CMD"
tmux send-keys -t "$PANE_ID" Enter
sleep 2

# 2. CLI起動コマンドを構築
CLI_CMD=$(build_cli_command "$AGENT_NAME" "$CLI_TYPE" "$CONFIG_FILE")
echo "  → $CLI_NAME 起動中..."
tmux send-keys -t "$PANE_ID" "$CLI_CMD"
tmux send-keys -t "$PANE_ID" Enter

# 3. 起動完了待機
READY_PATTERN=$(get_ready_pattern "$CLI_TYPE")
echo "  → 起動完了を待機中（最大${TIMEOUT}秒）..."

if [ "$CLI_TYPE" = "crush" ]; then
  # Crushは表示領域に依存するため、固定時間待機
  sleep 5
  echo "  ✅ 起動完了（固定待機5秒, Crush）"
else
  for i in $(seq 1 $TIMEOUT); do
    # ペイン出力をキャプチャ（-S - で履歴全体）
    PANE_OUTPUT=$(tmux capture-pane -t "$PANE_ID" -p -S - -E - 2>/dev/null)
    
    if echo "$PANE_OUTPUT" | grep -q -E "$READY_PATTERN"; then
      echo "  ✅ 起動完了（${i}秒）"
      break
    fi
    if [ $i -eq $TIMEOUT ]; then
      echo "  ⚠️  タイムアウト: 起動完了を検出できませんでしたが続行します"
    fi
    sleep 1
  done
fi

# 4. 指示送信（指定時のみ）
if [ -n "$TASK_MESSAGE" ]; then
  echo "  → 指示を送信中..."
  tmux send-keys -t "$PANE_ID" "$TASK_MESSAGE"
  tmux send-keys -t "$PANE_ID" Enter
  echo "  ✅ 指示送信完了"
fi

echo "🎉 足軽再起動完了: $PANE_ID ($AGENT_NAME, $CLI_NAME)"
