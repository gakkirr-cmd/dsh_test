#!/usr/bin/env bash
#
# 安装 GitHub CLI (gh) —— 由 /wizard 生成的一次性向导。
# 官方来源：https://cli.github.com/
#
# 下面 "STAGES" 标记以上是向导库（与其它向导完全一致，不要手改）。
# 需要改的只有标记以下的各个 stage。

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────
# Wizard library: delightful, consistent UX, identical across every wizard.
# ──────────────────────────────────────────────────────────────────────────

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
  BOLD=$(tput bold); DIM=$(tput dim); RESET=$(tput sgr0)
  BLUE=$(tput setaf 4); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3)
else
  BOLD=""; DIM=""; RESET=""; BLUE=""; GREEN=""; YELLOW=""
fi

# Author sets this at the top of the stages section.
TOTAL_STAGES=0

_STAGE_INDEX=0
ENV_FILE="${ENV_FILE:-.env}"
WRITTEN_ENV=()    # KEYs written to ENV_FILE this run
WRITTEN_SECRET=() # secret NAMEs set this run
SKIPPED=()        # things we couldn't do (e.g. gh missing)

# _clear wipes the terminal so only the current step is on screen. No-op when
# output isn't a terminal, so piped logs stay readable.
_clear() {
  [[ -t 1 ]] || return 0
  if command -v tput >/dev/null 2>&1 && tput clear 2>/dev/null; then return 0; fi
  printf '\033[2J\033[3J\033[H'
}

# banner "Title" shows the opening frame: what this wizard does.
banner() {
  _clear
  printf '\n%s%s  %s%s\n' "$BOLD" "$BLUE" "$1" "$RESET"
  printf '%s  %s stages%s\n\n' "$DIM" "$TOTAL_STAGES" "$RESET"
  printf '%s  You drive the browser; this wizard tells you exactly what to do and\n' "$DIM"
  printf '  captures the values you copy back. Stop any time with Ctrl-C and re-run\n'
  printf '  later, since it remembers values already saved.%s\n' "$RESET"
  pause "Ready to start?"
}

# stage "Name" clears the screen, then announces a stage and shows progress.
# Clearing keeps only the current step on screen.
stage() {
  _clear
  _STAGE_INDEX=$((_STAGE_INDEX + 1))
  printf '\n%s%s▸ Stage %s/%s · %s%s\n' \
    "$BOLD" "$BLUE" "$_STAGE_INDEX" "$TOTAL_STAGES" "$1" "$RESET"
}

# say "..." prints a plain instruction line.
say()  { printf '  %s\n' "$1"; }
# step "..." is a numbered-feeling action the human takes in the browser.
step() { printf '  %s•%s %s\n' "$BLUE" "$RESET" "$1"; }
note() { printf '  %s%s%s\n' "$DIM" "$1" "$RESET"; }
warn() { printf '  %s⚠ %s%s\n' "$YELLOW" "$1" "$RESET"; }

# open_url URL opens it in the human's browser, cross-platform incl. WSL.
open_url() {
  local url="$1"
  printf '  %s↗ opening%s %s\n' "$GREEN" "$RESET" "$url"
  { if   command -v wslview     >/dev/null 2>&1; then wslview "$url"
    elif command -v explorer.exe >/dev/null 2>&1; then explorer.exe "$url"
    elif command -v xdg-open    >/dev/null 2>&1; then xdg-open "$url"
    elif command -v open        >/dev/null 2>&1; then open "$url"
    else false; fi
  } >/dev/null 2>&1 || warn "couldn't open a browser, so visit it manually: $url"
}

# pause "msg" waits for the human to confirm they've done the manual part.
pause() {
  printf '  %s%s%s ' "$DIM" "${1:-Press Enter to continue}" "$RESET"
  read -r _ || true
}

# confirm "question" is a y/N gate; returns success on yes.
confirm() {
  local reply=""
  printf '  %s? %s [y/N] ' "$YELLOW" "$1"
  read -r reply || true
  [[ "$reply" =~ ^[Yy] ]]
}

# _existing KEY: current value of KEY in ENV_FILE, if any, with write_env's single
# quotes or a plain dotenv double-quoted value undone.
_existing() {
  [[ -f "$ENV_FILE" ]] || return 1
  local line value sq="'\\''"; line=$(grep -E "^${1}=" "$ENV_FILE" | tail -n1) || return 1
  value="${line#*=}"
  if [[ "$value" == \'*\' ]]; then value="${value:1:${#value}-2}"; value="${value//"$sq"/\'}"
  elif [[ "$value" == \"*\" ]]; then
    value="${value:1:${#value}-2}"
    [[ "$value" == *[\\\$\"]* ]] && return 1   # escapes, $ or ": can't decode safely; ask again
  fi
  printf '%s' "$value"
}

# ask KEY "Prompt" reads a value into $KEY. Offers the existing .env value as
# a default on re-runs (Enter keeps it). Visible input (non-secret), edited
# with Readline. Fails at EOF with no input.
ask() {
  local key="$1" prompt="$2" current input s=$'\001' e=$'\002' p rc=0
  current=$(_existing "$key" || true)
  # Readline needs the colour codes wrapped in \001..\002 to place the cursor.
  p="  $s$BOLD$e$prompt$s$RESET$e "
  [[ -n "$current" ]] && p+="$s$DIM$e[Enter keeps current]$s$RESET$e "
  read -e -r -p "$p" input || rc=1
  if (( rc )) && [[ -z "$input" ]]; then return 1; fi
  [[ -z "$input" && -n "$current" ]] && input="$current"
  printf -v "$key" '%s' "$input"
}

# ask_secret KEY "Prompt" is like ask, but input is hidden.
ask_secret() {
  local key="$1" prompt="$2" current input rc=0
  current=$(_existing "$key" || true)
  if [[ -n "$current" ]]; then
    printf '  %s%s%s %s[Enter keeps current]%s ' "$BOLD" "$prompt" "$RESET" "$DIM" "$RESET"
  else
    printf '  %s%s%s ' "$BOLD" "$prompt" "$RESET"
  fi
  read -rs input || rc=1
  printf '\n'
  if (( rc )) && [[ -z "$input" ]]; then return 1; fi
  [[ -z "$input" && -n "$current" ]] && input="$current"
  printf -v "$key" '%s' "$input"
}

# write_env KEY VALUE upserts KEY='VALUE' into ENV_FILE (replaces any existing
# line) and sets $KEY. Idempotent. Creates ENV_FILE at mode 0600; writes through
# a symlink and keeps an existing file's mode.
write_env() {
  local key="$1" value="$2" tmp sq="'\\''"
  [[ -e "$ENV_FILE" ]] || (umask 077 && : > "$ENV_FILE")
  tmp=$(mktemp)
  grep -vE "^${key}=" "$ENV_FILE" > "$tmp" || true
  printf "%s='%s'\n" "$key" "${value//\'/$sq}" >> "$tmp"
  cat "$tmp" > "$ENV_FILE"
  rm -f "$tmp"
  printf -v "$key" '%s' "$value"
  WRITTEN_ENV+=("$key")
  printf '  %s✓ wrote%s %s → %s\n' "$GREEN" "$RESET" "$key" "$ENV_FILE"
}

# set_secret NAME VALUE sets a GitHub Actions repo secret via gh. Falls back
# to a warning (and records it) if gh is unavailable or unauthenticated.
set_secret() {
  local name="$1" value="$2"
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    if printf '%s' "$value" | gh secret set "$name" >/dev/null 2>&1; then
      WRITTEN_SECRET+=("$name")
      printf '  %s✓ set%s GitHub secret %s\n' "$GREEN" "$RESET" "$name"
      return
    fi
  fi
  SKIPPED+=("GitHub secret $name (set it manually: gh secret set $name)")
  warn "skipped GitHub secret $name: gh not ready; set it later"
}

# set_var NAME VALUE sets a GitHub Actions repo variable (non-secret).
set_var() {
  local name="$1" value="$2"
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    if gh variable set "$name" --body "$value" >/dev/null 2>&1; then
      printf '  %s✓ set%s GitHub variable %s\n' "$GREEN" "$RESET" "$name"
      return
    fi
  fi
  SKIPPED+=("GitHub variable $name")
  warn "skipped GitHub variable $name, gh not ready; set it later"
}

# finish clears, then shows a closing summary of everything configured.
finish() {
  _clear
  printf '\n%s%s  ✓ Setup complete%s\n' "$BOLD" "$GREEN" "$RESET"
  (( ${#WRITTEN_ENV[@]} ))    && note "wrote ${#WRITTEN_ENV[@]} value(s) to $ENV_FILE: ${WRITTEN_ENV[*]}"
  (( ${#WRITTEN_SECRET[@]} )) && note "set ${#WRITTEN_SECRET[@]} GitHub secret(s): ${WRITTEN_SECRET[*]}"
  if (( ${#SKIPPED[@]} )); then
    printf '\n'; warn "still to do by hand:"
    for s in "${SKIPPED[@]}"; do note "  - $s"; done
  fi
  printf '\n'
}

# ──────────────────────────────────────────────────────────────────────────
# STAGES: author this section. One stage() per step the human takes.
# Keep every stage inside run_wizard and the last line as is: bash then parses
# the whole file before the first prompt, so an edit mid-run can't break it.
# ──────────────────────────────────────────────────────────────────────────

run_wizard() {

# 运行状态固定放在脚本旁边，重跑一次就接着上次的进度走。
# 注意：上面模板库已把 ENV_FILE 默认成 .env，这里不能再写 ${ENV_FILE:-...}：
# 那样默认分支永远不生效，状态会跟着当前目录跑，还可能覆盖掉别人的 .env。
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="$SCRIPT_DIR/.gh-wizard.env"

TOTAL_STAGES=5

# MSI 的默认安装位置（stage 3 用它验证，因为新装的 PATH 对当前终端还不生效）。
GH_EXE="/c/Program Files/GitHub CLI/gh.exe"

banner "安装 GitHub CLI (gh)"

# ── Stage 1 ───────────────────────────────────────────────────────────────
stage "下载官方安装包"
say "用 GitHub 官方发布的 Windows 安装包 —— 和 cli.github.com 上点「Windows」得到的是同一份。"
open_url "https://cli.github.com/"
step "在页面上点「Windows」下载，得到 gh_<版本>_windows_amd64.msi。"
step "让文件留在「下载」文件夹里 —— 本向导会自动找最新的那个。"
note "如果页面把你带到了 releases 列表：选 gh_*_windows_amd64.msi，别选 _386（32 位）或 .zip（便携版）。"
note "已经装过 gh 的话，这一步等于覆盖升级，安装包会直接把旧版替掉。"
pause "下载完成后按回车"
printf '\n'

# 自动认领「下载」文件夹里最新的 amd64 安装包；回车即采纳，找不到就手动粘贴。
found=""
for d in "$HOME/Downloads" "$HOME/OneDrive/Downloads"; do
  newest=$(ls -t "$d"/gh_*_windows_amd64.msi 2>/dev/null | head -n1) || true
  [[ -n "$newest" ]] && found="$newest"
done
if [[ -n "$found" ]]; then
  write_env GH_MSI_PATH "$found"
else
  warn "「下载」文件夹里没找到 gh_*_windows_amd64.msi —— 请手动粘贴完整路径。"
fi
ask GH_MSI_PATH "MSI 路径:"

# 粘贴来的可能是 Windows 形式，也可能带「复制为路径」自动加的双引号。
GH_MSI_PATH="${GH_MSI_PATH%\"}"
GH_MSI_PATH="${GH_MSI_PATH#\"}"
case "$GH_MSI_PATH" in
  *_386.msi) warn "这是 32 位安装包，本机是 64 位 —— 请改用 gh_*_windows_amd64.msi。"; exit 1 ;;
  *.zip)     warn "这是便携 zip，本向导装的是 MSI。"; exit 1 ;;
esac
if command -v cygpath >/dev/null 2>&1; then
  GH_MSI_PATH=$(cygpath -u "$GH_MSI_PATH")
fi
if [[ ! -f "$GH_MSI_PATH" ]]; then
  warn "找不到这个文件：$GH_MSI_PATH"
  say "下载好之后再运行本向导即可，已填的值都还留着。"
  exit 1
fi
say "将安装：$GH_MSI_PATH"

# 要提权安装的东西，先确认是 GitHub 签过名的官方包。
# env -u PSModulePath：bash 继承来的那个变量会让 Security 模块加载失败。
ps=""
if command -v pwsh >/dev/null 2>&1; then ps="pwsh"
elif command -v powershell >/dev/null 2>&1; then ps="powershell"
fi
sig=""
if [[ -n "$ps" ]]; then
  sig=$(env -u PSModulePath "$ps" -NoProfile -NonInteractive -Command \
    "(Get-AuthenticodeSignature -LiteralPath '$(cygpath -w "$GH_MSI_PATH")').Status" 2>/dev/null \
    | tr -d '\r' | head -n1) || sig=""
fi
if [[ "$sig" == "Valid" ]]; then
  say "✓ 数字签名有效（GitHub 官方签名）"
elif [[ -n "$sig" ]]; then
  warn "签名校验结果：$sig（期望 Valid）—— 文件可能不完整或不是官方来源。"
  confirm "仍然继续安装？" || { say "已停止。"; exit 1; }
else
  note "这台机器上取不到签名状态，跳过签名校验。"
fi

# ── Stage 2 ───────────────────────────────────────────────────────────────
stage "安装（会弹一次 UAC）"
say 'MSI 会装到 C:\Program Files\GitHub CLI，并自动写进系统 PATH。'
note "Windows 会弹授权框 —— 点「是」。之后只有一条进度条，没有别的选项要选。"
if confirm "现在运行安装程序？"; then
  # MSYS 会把 /i 当成路径改写掉，所以用 //i（被转义成 /i）并传 Windows 形式路径。
  rc=0
  msiexec.exe //i "$(cygpath -w "$GH_MSI_PATH")" //passive || rc=$?
  if (( rc != 0 && rc != 3010 )); then
    warn "安装程序返回码 $rc（非 0/3010）。如果刚在 UAC 框点了取消，重跑本向导即可。"
  fi
  pause "安装窗口关闭后按回车"
else
  warn "跳过安装。如果这台机器上已经装过 gh，可以直接继续。"
fi

# ── Stage 3 ───────────────────────────────────────────────────────────────
stage "验证安装"
note "gh 已经写进系统 PATH，但当前这个终端是在安装之前打开的，还看不到它 —— 用绝对路径验证。"
if [[ -x "$GH_EXE" ]]; then
  say "✓ 找到 $GH_EXE"
elif command -v gh >/dev/null 2>&1; then
  GH_EXE=$(command -v gh)
  say "✓ 用 PATH 上的 gh：$GH_EXE"
else
  warn '没找到 C:\Program Files\GitHub CLI\gh.exe'
  say "说明安装没完成 —— 回到上一步重跑，或者装完再运行本向导。"
  exit 1
fi
GH_VERSION=$("$GH_EXE" --version | head -n1)
say "✓ $GH_VERSION"
write_env GH_VERSION "$GH_VERSION"

# ── Stage 4 ───────────────────────────────────────────────────────────────
stage "登录 GitHub"
say "gh 要拿到你的授权才能操作仓库，这一步只能在浏览器里亲手确认。"
note "gh 是 Go 程序，不读 Windows 的系统代理设置 —— 连不上时要单独给它指代理。"
say ""

# 登录用的是 github.com（device flow），必须单独测：这台机器上 api.github.com 通、github.com 不通。
code=$(curl -sS -m 15 -o /dev/null -w '%{http_code}' https://github.com 2>/dev/null) || code=""
if [[ "${code:-}" =~ ^[23] ]]; then
  say "✓ github.com 直连可达（HTTP $code）"
else
  proxy=$(reg query 'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings' //v ProxyServer 2>/dev/null \
          | sed -n 's/.*REG_SZ[[:space:]]*//p' | tr -d '\r') || proxy=""
  if [[ -n "${proxy:-}" ]]; then
    say "直连不通，套用系统里已配置的代理：$proxy"
    export HTTPS_PROXY="http://$proxy" HTTP_PROXY="http://$proxy"
    code=$(curl -sS -m 15 -o /dev/null -w '%{http_code}' https://github.com 2>/dev/null) || code=""
  fi
fi

if [[ "${code:-}" =~ ^[23] ]]; then
  say ""
  say "接着 gh 会问你三件事，按下面的选："
  step "What account do you want to log into?      →  GitHub.com（回车就是默认）"
  step "What is your preferred protocol for Git?    →  HTTPS（回车就是默认）"
  step "How would you like to authenticate?         →  Login with a web browser（回车）"
  step "屏幕会给一个 XXXX-XXXX 一次性码：复制它，粘到自动打开的浏览器页面里，点授权。"
  step "浏览器提示 Congratulations 后，回到这里等命令自己结束。"
  pause "按回车开始登录"
  "$GH_EXE" auth login || warn "登录命令返回非 0（可能按了取消）—— 之后可以单独运行 gh auth login。"
else
  warn "github.com 连不上（HTTP ${code:-000}），现在登录多半会卡在等浏览器授权那一步。"
  SKIPPED+=("完成 gh 登录：网络通了以后运行 gh auth login")
fi

# ── Stage 5 ───────────────────────────────────────────────────────────────
stage "收尾"
if "$GH_EXE" auth status >/dev/null 2>&1; then
  GH_LOGIN=$("$GH_EXE" api user --jq .login 2>/dev/null) || GH_LOGIN=""
  say "✓ 已登录：${GH_LOGIN:-（账号名没取到）}"
  if [[ -n "$GH_LOGIN" ]]; then write_env GH_LOGIN "$GH_LOGIN"; fi
else
  warn "还没登录成功。"
  SKIPPED+=("完成 gh 登录：gh auth login")
fi
if confirm "让 git 复用 gh 的凭据（gh auth setup-git，之后 git push 不用再单独输密码）？"; then
  "$GH_EXE" auth setup-git && say "✓ git 已改用 gh 凭据" || warn "setup-git 没成功，可以稍后手动跑一次。"
fi

finish
say "下一步："
step "新开一个 PowerShell 或 cmd 窗口，运行 gh --version 确认 PATH 已生效。"
step "然后就能用 gh repo list、gh pr list、gh issue list 了。"
say ""

}

run_wizard "$@"; exit
