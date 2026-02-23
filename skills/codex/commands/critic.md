---
description: >-
  Codex 기반 코드/계획/임의 콘텐츠 검증 및 피드백 제공.
  코드 변경사항, 계획, 또는 임의의 텍스트가 요청에 부합하는지 독립적으로 검증합니다.
argument-hint: "<원래 사용자 요청 또는 검증 대상 설명>"
allowed-tools:
  - Bash
  - Read
  - Write
  - WebFetch
  - WebSearch
---

Set up Codex Critic environment:

```!
CRITIC_HOME="$HOME/.codex-critic"
mkdir -p "$CRITIC_HOME" "$HOME/.ai"
cp "${CLAUDE_PLUGIN_ROOT}/agents/codex-critic-agents.md" "$CRITIC_HOME/AGENTS.md" 2>/dev/null
cp "${CLAUDE_PLUGIN_ROOT}/references/critic-schema.json" "$CRITIC_HOME/critic-schema.json" 2>/dev/null
cp "${CLAUDE_PLUGIN_ROOT}/scripts/stream-progress.sh" "$HOME/.ai/stream-progress.sh" 2>/dev/null
chmod +x "$HOME/.ai/stream-progress.sh" 2>/dev/null
ln -sf "$HOME/.codex/config.toml" "$CRITIC_HOME/config.toml" 2>/dev/null
ln -sf "$HOME/.codex/auth.json" "$CRITIC_HOME/auth.json" 2>/dev/null
echo "Codex Critic home ready: $CRITIC_HOME"
```

# Codex Critic

OpenAI Codex CLI의 비대화형 모드(`codex exec`)를 사용하여, 코드 변경사항(diff),
계획, 또는 임의의 콘텐츠가 원래 사용자 요청에 부합하는지 독립적으로 검증하고
구조화된 피드백을 제공합니다.

## Invocation

```text
/codex:critic <원래 사용자 요청 또는 검증 대상 설명>
```

## Execution Steps

아래 단계를 순서대로 실행한다. 각 단계에서 에러가 발생하면 사용자에게 보고하고 중단한다.

### Step 1: 전제 조건 확인

codex CLI가 설치되어 있는지 Bash로 확인한다. 실패하면 에러 메시지를 사용자에게 전달하고 중단한다.

```bash
command -v codex >/dev/null 2>&1 || echo "ERROR: codex CLI not found. Install: npm install -g @openai/codex"
```

**인증**: `codex login`으로 사전 인증이 필요하다. 인증 실패는 codex exec 실행 시 자체적으로 보고된다.

### Step 2: 입력 결정

다음 우선순위에 따라 검증 대상 콘텐츠를 결정한다.

#### 모드 A: 명시적 콘텐츠 (임의 입력)

사용자가 다음 중 하나를 제공한 경우 해당 내용을 `REVIEW_CONTENT`로 사용한다:

- 파일 경로를 지정 → Read 도구로 읽어서 내용 수집
- 텍스트 블록을 직접 전달 → 그대로 사용
- 구현 계획이나 설계 문서 → 해당 내용을 수집

`CONTENT_TYPE`을 `"arbitrary"`로 설정한다.

#### 모드 B: Git Diff (기본 모드)

명시적 콘텐츠가 없으면 git diff를 수집한다. 아래 순서로 cascade하여 첫 번째 비어있지 않은 결과를 사용한다:

```bash
# 1. Staged changes
git diff --staged 2>/dev/null

# 2. Working tree changes
git diff 2>/dev/null

# 3. Last commit
git diff HEAD~1 HEAD 2>/dev/null
```

diff가 존재하면 `CONTENT_TYPE`을 `"diff"`로 설정한다.

**Truncation**: 환경변수 `CRITIC_MAX_DIFF_LINES` (기본값: 500) 초과 시
처음 N줄만 사용하고 `[... truncated ...]` 표시를 추가한다.

#### 모드 C: 대화 컨텍스트 폴백

모드 A, B 모두 콘텐츠가 없으면, 현재 대화 컨텍스트에서 가장 최근 작업 내용
(코드 변경, 계획 등)을 추론하여 사용한다. 추론할 수 없으면 사용자에게 검증 대상을
명시해달라고 요청하고 중단한다.

### Step 3: 세션 ID 생성 및 출력 디렉토리 준비

세션별 고유 ID를 생성하고 이후 모든 출력 파일명에 사용한다.

```bash
SESSION_ID=$(date +%Y%m%d-%H%M%S)
mkdir -p ~/.ai
echo "Session ID: $SESSION_ID"
```

`SESSION_ID` 값을 기억하여 이후 모든 파일 경로에 사용한다.
출력 파일 패턴: `~/.ai/critic-{SESSION_ID}-iter-{N}.json`

### Step 4: 초기 분석 실행 (Iteration 1)

#### 4a. 프롬프트 작성

Write 도구를 사용하여 `/tmp/critic-prompt.txt`에 프롬프트를 작성한다.
아래 템플릿에서 `{USER_REQUEST}`, `{CONTENT_SECTION}`, `{ITERATION}` 을 치환한다.

**`CONTENT_TYPE`이 `"diff"`인 경우** `{CONTENT_SECTION}`을 다음으로 구성한다:

````text
## Code Changes (Diff)
```diff
{REVIEW_CONTENT}
```
````

**`CONTENT_TYPE`이 `"arbitrary"`인 경우** `{CONTENT_SECTION}`을 다음으로 구성한다:

````text
## Content Under Review
```
{REVIEW_CONTENT}
```
````

**초기 분석 프롬프트 템플릿**:

```text
You are a meticulous code reviewer and critic. Your task is to evaluate whether
the provided content correctly and completely fulfills the original user request.

## Original User Request
{USER_REQUEST}

{CONTENT_SECTION}

## Instructions
1. Analyze the content against the original request.
2. Check for: correctness, completeness, security, style consistency, edge cases, and potential bugs.
3. For code diffs, also check: error handling, performance, and testing coverage.
4. For plans or designs, check: feasibility, completeness, potential risks, and missing considerations.
5. Produce a structured JSON review.

## Output Requirements
Respond with ONLY valid JSON matching this structure:
{
  "verdict": "pass" | "warn" | "fail",
  "score": <0-10>,
  "summary": "<one paragraph summary>",
  "issues": [
    {
      "severity": "critical" | "major" | "minor" | "info",
      "category": "<category>",
      "file": "<file path if applicable>",
      "line": <line number if applicable>,
      "description": "<what the issue is>",
      "suggestion": "<how to fix>"
    }
  ],
  "checklist": [
    {
      "item": "<what was checked>",
      "passed": true | false,
      "note": "<additional context>"
    }
  ],
  "iteration": {ITERATION}
}

Be thorough but fair. Only flag real issues, not stylistic preferences unless they violate project conventions.
Output ONLY the JSON object, no markdown fences, no explanation before or after.
```

#### 4b. Codex 실행

```bash
JSONL_LOG="$HOME/.ai/critic-${SESSION_ID}-events.jsonl"
touch "$JSONL_LOG"
tail -f "$JSONL_LOG" | "$HOME/.ai/stream-progress.sh" &
TAIL_PID=$!

CODEX_HOME="$HOME/.codex-critic" codex exec \
  --json \
  --sandbox "${CRITIC_SANDBOX:-workspace-write}" \
  --output-schema "$HOME/.codex-critic/critic-schema.json" \
  --output-last-message ~/.ai/critic-${SESSION_ID}-iter-1.json \
  - < /tmp/critic-prompt.txt \
  >> "$JSONL_LOG"

sleep 1
kill $TAIL_PID 2>/dev/null
wait $TAIL_PID 2>/dev/null
```

실패 시 에러를 사용자에게 보고하고 중단한다.

#### 4c. 결과 읽기 및 검증

Read 도구로 `~/.ai/critic-{SESSION_ID}-iter-1.json`을 읽는다.

JSON이 유효하지 않으면 Bash로 추출을 시도한다:

```bash
jq . ~/.ai/critic-${SESSION_ID}-iter-1.json
```

jq도 실패하면 에러를 보고하고 중단한다.

`verdict`와 `score` 값을 파악한다.

### Step 5: 반복 개선 루프

**중단 조건**: 다음 중 하나라도 충족되면 반복을 중단하고 Step 6으로 진행한다:

- `verdict == "pass"`
- `score >= 8`
- 반복 횟수가 `CRITIC_MAX_ITER` (기본값: 5)에 도달

**계속 조건**: 중단 조건이 충족되지 않으면 개선 프롬프트를 작성하여 다시 실행한다.

#### 개선 프롬프트 템플릿

Write 도구로 `/tmp/critic-prompt.txt`를 다음 내용으로 덮어쓴다:

```text
You are refining a previous code review. Review your prior analysis, identify
any missed issues or false positives, and produce an improved version.

## Original User Request
{USER_REQUEST}

{CONTENT_SECTION}

## Previous Analysis (Iteration {PREV_ITERATION})
{PREVIOUS_RESULT_JSON}

## Refinement Instructions
1. Re-examine each issue: remove false positives, add missed problems.
2. Recalibrate the score based on your refined understanding.
3. Ensure the checklist is comprehensive.
4. If your previous analysis was already thorough and accurate, you may keep
   it largely unchanged but update the iteration number.

## Output Requirements
Respond with ONLY valid JSON (same schema as before).
Set "iteration" to {ITERATION}.
Output ONLY the JSON object, no markdown fences, no explanation before or after.
```

실행 명령 (iteration 번호에 맞게 출력 파일 변경):

```bash
JSONL_LOG="$HOME/.ai/critic-${SESSION_ID}-events.jsonl"
touch "$JSONL_LOG"
tail -f "$JSONL_LOG" | "$HOME/.ai/stream-progress.sh" &
TAIL_PID=$!

CODEX_HOME="$HOME/.codex-critic" codex exec \
  --json \
  --sandbox "${CRITIC_SANDBOX:-workspace-write}" \
  --output-schema "$HOME/.codex-critic/critic-schema.json" \
  --output-last-message ~/.ai/critic-${SESSION_ID}-iter-{N}.json \
  - < /tmp/critic-prompt.txt \
  >> "$JSONL_LOG"

sleep 1
kill $TAIL_PID 2>/dev/null
wait $TAIL_PID 2>/dev/null
```

**에러 폴백**: `codex exec`가 실패하면 이전 iteration의 결과를 최종 결과로 사용한다.

### Step 6: 최종 결과 저장

마지막 iteration의 결과 파일을 `~/.ai/critic-{SESSION_ID}-result.json`으로 복사한다:

```bash
cp ~/.ai/critic-${SESSION_ID}-iter-{LAST_N}.json ~/.ai/critic-${SESSION_ID}-result.json
```

임시 프롬프트 파일을 정리한다:

```bash
rm -f /tmp/critic-prompt.txt
```

### Step 7: 결과 보고

JSON 결과를 다음 형식으로 정리하여 사용자에게 보고한다:

```text
## Codex Critic 결과

**Verdict**: {verdict} | **Score**: {score}/10 | **Iterations**: {iteration}

### Summary
{summary}

### Issues ({이슈 수}건)
| Severity | Category | File | Description | Suggestion |
|----------|----------|------|-------------|------------|
| ... | ... | ... | ... | ... |

### Checklist
- [x/  ] {item}: {note}
```

### Step 8: 후속 조치 제안

- `verdict`가 `fail`이면: 이슈별 수정 계획을 제안한다.
- `verdict`가 `warn`이면: 주요 이슈에 대한 수정 여부를 사용자에게 제안한다.
- `verdict`가 `pass`이면: 결과만 보고하고 완료한다.

수정 작업은 사용자 승인 후에만 진행한다.

## Configuration

| 환경변수                | 기본값    | 설명                                             |
| ----------------------- | --------- | ------------------------------------------------ |
| `CRITIC_MAX_ITER`       | 5         | 최대 반복 횟수                                   |
| `CRITIC_MAX_DIFF_LINES` | 500       | diff 최대 줄 수                                  |
| `CRITIC_SANDBOX`        | workspace-write | Codex sandbox 모드                          |

## Notes

- Codex는 workspace-write sandbox에서 실행되어 워크스페이스 내 파일 수정이 가능합니다.
- 결과는 `~/.ai/critic-{SESSION_ID}-result.json`에 저장되며, 반복(iteration) 결과는 `~/.ai/critic-{SESSION_ID}-iter-{N}.json`에 보존됩니다.
- `~/.ai/` 디렉토리에 런타임 출력물을 저장합니다 (프로젝트 디렉토리를 오염시키지 않음).
- 프롬프트는 Write 도구로 파일에 작성 후 stdin redirect로 전달합니다 (shell metacharacter 안전).
