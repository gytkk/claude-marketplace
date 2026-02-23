---
description: >-
  Codex 기반 코드/계획/임의 콘텐츠 검증 및 피드백 제공.
  코드 변경사항, 계획, 또는 임의의 텍스트가 요청에 부합하는지 독립적으로 검증합니다.
argument-hint: "<원래 사용자 요청 또는 검증 대상 설명>"
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - mcp__codex__codex
  - mcp__codex__codex-reply
---

# Codex Critic

Codex MCP 도구를 사용하여 코드 변경사항(diff), 계획, 또는 임의의 콘텐츠가
원래 사용자 요청에 부합하는지 독립적으로 검증하고 구조화된 피드백을 제공합니다.

## Invocation

```text
/codex:critic <원래 사용자 요청 또는 검증 대상 설명>
```

## Execution Steps

아래 단계를 순서대로 실행한다. 각 단계에서 에러가 발생하면 사용자에게 보고하고 중단한다.

### Step 1: 전제 조건 확인

codex CLI가 설치되어 있는지 Bash로 확인한다. 실패하면 에러 메시지를 사용자에게 전달하고 중단한다.

```bash
command -v codex >/dev/null 2>&1 || { echo "ERROR: codex CLI not found. Install: npm install -g @openai/codex"; exit 1; }
```

**인증**: `codex login`으로 사전 인증이 필요하다. 인증 실패는 MCP 도구 실행 시 자체적으로 보고된다.

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

### Step 4: 초기 분석 실행 (Iteration 1)

#### 4a. Agent persona 읽기

Read 도구로 `${CLAUDE_PLUGIN_ROOT}/agents/codex-critic-agents.md`를 읽어 `AGENT_PERSONA` 내용을 확보한다.

#### 4b. 프롬프트 구성

아래 템플릿에서 `{USER_REQUEST}`, `{CONTENT_SECTION}`, `{ITERATION}`, `{AGENT_PERSONA}`를 치환하여 프롬프트 문자열을 구성한다.

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
{AGENT_PERSONA}

---

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

#### 4c. Codex MCP 호출

`mcp__codex__codex` 도구를 호출하여 구성한 프롬프트를 `prompt` 파라미터로 전달한다.

응답에서 `threadId`를 저장하고, 응답 텍스트에서 JSON 결과를 파싱한다.

#### 4d. 결과 검증

JSON이 유효한지 확인한다. 유효하지 않으면 에러를 보고하고 중단한다.

`verdict`와 `score` 값을 파악한다.

### Step 5: 반복 개선 루프

**중단 조건**: 다음 중 하나라도 충족되면 반복을 중단하고 Step 6으로 진행한다:

- `verdict == "pass"`
- `score >= 8`
- 반복 횟수가 `CRITIC_MAX_ITER` (기본값: 5)에 도달

**계속 조건**: 중단 조건이 충족되지 않으면 `mcp__codex__codex-reply`로 개선을 요청한다.

#### 개선 메시지 템플릿

`mcp__codex__codex-reply` 도구에 `threadId`와 아래 `message`를 전달한다.
Codex가 이전 컨텍스트를 기억하므로 원본 콘텐츠를 다시 보낼 필요가 없다.

```text
Review your prior analysis (iteration {PREV_ITERATION}) and refine it.

## Refinement Instructions
1. Re-examine each issue: remove false positives, add missed problems.
2. Recalibrate the score based on your refined understanding.
3. Ensure the checklist is comprehensive.
4. If your previous analysis was already thorough and accurate, you may keep
   it largely unchanged but update the iteration number.

Respond with ONLY valid JSON (same schema as before).
Set "iteration" to {ITERATION}.
Output ONLY the JSON object, no markdown fences, no explanation before or after.
```

응답 텍스트에서 JSON 결과를 파싱하고, `verdict`와 `score`를 재확인한다.

**에러 폴백**: MCP 호출이 실패하면 이전 iteration의 결과를 최종 결과로 사용한다.

### Step 6: 최종 결과 저장

최종 JSON 결과를 `~/.ai/critic-{SESSION_ID}-result.json`에 저장한다:

```bash
cat > ~/.ai/critic-${SESSION_ID}-result.json << 'RESULT_EOF'
{FINAL_RESULT_JSON}
RESULT_EOF
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

## Notes

- Codex MCP 도구를 통해 분석을 수행하며, thread 기반 대화로 반복 개선이 가능합니다.
- 결과는 `~/.ai/critic-{SESSION_ID}-result.json`에 저장됩니다.
- `~/.ai/` 디렉토리에 런타임 출력물을 저장합니다 (프로젝트 디렉토리를 오염시키지 않음).
