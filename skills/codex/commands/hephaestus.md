---
description: >-
  Codex 기반 자율적 딥 워커. 복잡한 구현 작업을 Codex MCP 도구를 통해 위임하여
  탐색 → 계획 → 실행 → 검증을 자율적으로 수행합니다.
argument-hint: "<작업 목표 설명>"
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - mcp__codex__codex
  - mcp__codex__codex-reply
---

# Codex Hephaestus

Codex MCP 도구를 사용하여 복잡한 구현 작업을 자율적으로 수행합니다.
Hephaestus(그리스 신화의 대장장이 신)처럼 목표를 받으면 탐색, 계획, 실행,
검증까지 독립적으로 완료합니다.

## Invocation

```text
/codex:hephaestus <작업 목표 설명>
```

## Execution Steps

아래 단계를 순서대로 실행한다. 각 단계에서 에러가 발생하면 사용자에게 보고하고 중단한다.

### Step 1: 전제 조건 확인

codex CLI가 설치되어 있는지 Bash로 확인한다.

```bash
command -v codex >/dev/null 2>&1 || { echo "ERROR: codex CLI not found. Install: npm install -g @openai/codex"; exit 1; }
```

이 명령이 실패(exit 1)하면 즉시 사용자에게 설치 안내를 보고하고 **스킬 실행을 중단**한다.
이후 단계를 절대 진행하지 않는다.

### Step 2: 컨텍스트 수집

작업에 필요한 컨텍스트를 수집한다. 다음을 포함한다:

1. **사용자 요청**: 스킬 호출 시 전달된 작업 목표
2. **프로젝트 구조**: 관련 파일/디렉토리 목록 (Glob/Grep으로 수집)
3. **관련 코드**: 작업과 직접 관련된 파일 내용 (Read로 수집)
4. **기존 패턴**: 프로젝트의 코드 스타일, 구조 패턴

수집 기준:
- 사용자가 특정 파일을 언급했으면 해당 파일을 Read
- 작업 영역이 명확하면 해당 디렉토리를 Glob으로 탐색
- 작업 영역이 불명확하면 Grep으로 관련 코드 검색
- 컨텍스트는 최대 300줄로 제한 (초과 시 핵심 부분만 발췌)

수집한 컨텍스트를 `TASK_CONTEXT` 변수에 저장한다.

### Step 3: 세션 ID 생성 및 출력 디렉토리 준비

세션별 고유 ID를 생성하고 이후 모든 출력 파일명에 사용한다.

```bash
SESSION_ID=$(date +%Y%m%d-%H%M%S)
mkdir -p ~/.ai
echo "Session ID: $SESSION_ID"
```

`SESSION_ID` 값을 기억하여 이후 모든 파일 경로에 사용한다.

### Step 4: 초기 실행 (Iteration 1)

#### 4a. Agent persona 읽기

Read 도구로 `${CLAUDE_PLUGIN_ROOT}/agents/codex-hephaestus-agents.md`를 읽어 `AGENT_PERSONA` 내용을 확보한다.

#### 4b. 프롬프트 구성

아래 템플릿에서 `{USER_REQUEST}`, `{TASK_CONTEXT}`, `{ITERATION}`, `{AGENT_PERSONA}`를 치환하여 프롬프트 문자열을 구성한다.

**프롬프트 템플릿**:

```text
{AGENT_PERSONA}

---

You are Hephaestus, an autonomous deep worker. Complete the following task
end-to-end. Do NOT ask questions. Do NOT stop early. Execute until done.

## Task
{USER_REQUEST}

## Project Context
{TASK_CONTEXT}

## Execution Rules
1. EXPLORE: Read all relevant files first. Understand existing patterns.
2. PLAN: Determine the exact changes needed (file-by-file).
3. EXECUTE: Make precise, surgical changes. Follow existing code style exactly.
4. VERIFY: Re-read every modified file. Check for syntax errors and logical mistakes.

If verification fails, return to step 1 and try a different approach (max 3 attempts).
After 3 failures, revert and report what went wrong.

## Hard Constraints
- Follow existing codebase patterns exactly
- Never suppress type errors (as any, @ts-ignore, # type: ignore)
- Never leave code in a broken state
- Never delete tests to make things pass
- Never add TODOs — complete the work now
- Never introduce commented-out code

## Output Requirements
After completing your work, respond with ONLY valid JSON matching this structure:
{
  "status": "complete" | "partial" | "failed",
  "summary": "<one paragraph of what was accomplished>",
  "approach": "<description of approach taken>",
  "files_modified": [
    {"path": "<relative path>", "action": "create|modify|delete", "description": "<what changed>"}
  ],
  "verification": {
    "syntax_check": true|false,
    "build_check": true|false,
    "test_check": true|false,
    "notes": "<verification details>"
  },
  "issues": [
    {"severity": "critical|major|minor", "description": "<issue>", "resolution": "<how resolved or why unresolved>"}
  ],
  "next_steps": ["<remaining work if any>"],
  "iteration": {ITERATION}
}

Output ONLY the JSON object, no markdown fences, no explanation before or after.
```

#### 4c. Codex MCP 호출

`mcp__codex__codex` 도구를 호출하여 구성한 프롬프트를 `prompt` 파라미터로 전달한다.

응답에서 `threadId`를 저장하고, 응답 텍스트에서 JSON 결과를 파싱한다.

#### 4d. 결과 검증

JSON이 유효한지 확인한다. 유효하지 않으면 에러를 보고하고 중단한다.

`status`와 `issues` 값을 파악한다.

### Step 5: 반복 개선 루프

**중단 조건**: 다음 중 하나라도 충족되면 반복을 중단하고 Step 6으로 진행한다:

- `status == "complete"` 이고 `issues`에 critical/major 이슈가 없음
- 반복 횟수가 `HEPHAESTUS_MAX_ITER` (기본값: 3)에 도달

**계속 조건**: 중단 조건이 충족되지 않으면 `mcp__codex__codex-reply`로 개선을 요청한다.

#### 개선 메시지 템플릿

`mcp__codex__codex-reply` 도구에 `threadId`와 아래 `message`를 전달한다.
Codex가 이전 컨텍스트를 기억하므로 원본 콘텐츠를 다시 보낼 필요가 없다.

```text
The previous iteration was incomplete or had issues. Continue the work.

## Previous Result Summary
- Status: {PREV_STATUS}
- Issues: {PREV_ISSUES_SUMMARY}

## Instructions
1. If status was "partial": complete the remaining work.
2. If status was "failed": try a different approach entirely.
3. If there were critical/major issues: fix them.
4. Verify ALL changes (both previous and new).

Respond with ONLY valid JSON (same schema as before).
Set "iteration" to {ITERATION}.
Output ONLY the JSON object, no markdown fences, no explanation before or after.
```

응답 텍스트에서 JSON 결과를 파싱하고, `status`와 `issues`를 재확인한다.

**에러 폴백**: MCP 호출이 실패하면 이전 iteration의 결과를 최종 결과로 사용한다.

### Step 6: 최종 결과 저장

최종 JSON 결과를 `~/.ai/hephaestus-{SESSION_ID}-result.json`에 저장한다:

```bash
cat > ~/.ai/hephaestus-${SESSION_ID}-result.json << 'RESULT_EOF'
{FINAL_RESULT_JSON}
RESULT_EOF
```

### Step 7: 변경사항 검증

Claude Code가 Codex의 작업 결과를 독립적으로 검증한다:

1. `git diff`로 실제 변경사항 확인
2. 변경된 파일들을 Read로 읽어 내용 확인
3. JSON 결과의 `files_modified`와 실제 git diff를 대조
4. 구문 오류, 논리적 문제, 기존 패턴 위반 여부 검토

검증에서 문제가 발견되면 사용자에게 보고한다.

### Step 8: 결과 보고

JSON 결과를 다음 형식으로 정리하여 사용자에게 보고한다:

```text
## Hephaestus 실행 결과

**Status**: {status} | **Iterations**: {iteration}

### Summary
{summary}

### Approach
{approach}

### Files Modified ({파일 수}개)
| Action | Path | Description |
|--------|------|-------------|
| ... | ... | ... |

### Verification
- Syntax: {syntax_check}
- Build: {build_check}
- Tests: {test_check}
- Notes: {notes}

### Issues ({이슈 수}건)
| Severity | Description | Resolution |
|----------|-------------|------------|
| ... | ... | ... |

### Next Steps
- {next_steps}
```

### Step 9: 후속 조치 제안

- `status`가 `complete`이고 이슈 없음: 변경사항을 사용자에게 보여주고 커밋 여부를 묻는다.
- `status`가 `complete`이지만 minor 이슈 존재: 이슈 목록과 함께 수정 여부를 제안한다.
- `status`가 `partial`: 미완료 부분을 설명하고, Claude Code가 직접 완료할지 재실행할지 제안한다.
- `status`가 `failed`: 실패 원인을 분석하고 대안을 제안한다.

수정 작업은 사용자 승인 후에만 진행한다.

## Configuration

| 환경변수 | 기본값 | 설명 |
|----------|--------|------|
| `HEPHAESTUS_MAX_ITER` | 3 | 최대 반복 횟수 |

## Notes

- Codex MCP 도구를 통해 작업을 수행하며, thread 기반 대화로 반복 개선이 가능합니다.
- 결과는 `~/.ai/hephaestus-{SESSION_ID}-result.json`에 저장됩니다.
- `~/.ai/` 디렉토리에 런타임 출력물을 저장합니다 (프로젝트 디렉토리를 오염시키지 않음).
- Codex 완료 후 Claude Code가 독립적으로 변경사항을 검증합니다 (Step 7).
