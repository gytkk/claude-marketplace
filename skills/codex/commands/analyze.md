---
description: >-
  Codex 기반 범용 심층 분석. 코드, 로그, 에러, 성능 등 임의의 대상을
  분석하여 구조화된 인사이트를 제공합니다.
argument-hint: "<분석 대상 설명>"
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - WebFetch
  - WebSearch
---

Set up Codex Analyze environment:

```!
ANALYZE_HOME="$HOME/.codex-analyze"
mkdir -p "$ANALYZE_HOME" "$HOME/.ai"
cp "${CLAUDE_PLUGIN_ROOT}/agents/codex-analyze-agents.md" "$ANALYZE_HOME/AGENTS.md" 2>/dev/null
cp "${CLAUDE_PLUGIN_ROOT}/references/analyze-schema.json" "$ANALYZE_HOME/analyze-schema.json" 2>/dev/null
cp "${CLAUDE_PLUGIN_ROOT}/scripts/stream-progress.sh" "$HOME/.ai/stream-progress.sh" 2>/dev/null
chmod +x "$HOME/.ai/stream-progress.sh" 2>/dev/null
ln -sf "$HOME/.codex/config.toml" "$ANALYZE_HOME/config.toml" 2>/dev/null
ln -sf "$HOME/.codex/auth.json" "$ANALYZE_HOME/auth.json" 2>/dev/null
echo "Codex Analyze home ready: $ANALYZE_HOME"
```

# Codex Analyze

Description: OpenAI Codex CLI의 비대화형 모드(codex exec)를 사용하여 코드, 로그, 에러, 성능 등
임의의 대상을 심층 분석하고 구조화된 인사이트를 제공합니다.

## Invocation

```text
/codex:analyze <분석 대상 설명>
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

### Step 2: 입력 결정

다음 3단계 cascade로 분석 대상을 결정한다.

#### 모드 A: 명시적 콘텐츠

사용자가 파일 경로, 디렉토리, 텍스트 블록을 명시적으로 제공하면 해당 내용을 수집해 `ANALYSIS_CONTENT`로 사용한다.

- 파일 경로: Read 도구로 내용 읽기
- 디렉토리: Glob으로 파일 목록 수집 후 핵심 파일 Read
- 텍스트 블록: 그대로 사용

`CONTENT_TYPE`을 `"explicit"`로 설정한다.

#### 모드 B: 프로젝트 구조 (기본 모드)

명시적 콘텐츠가 없으면 프로젝트 구조를 수집하여 `ANALYSIS_CONTENT`로 사용한다.

수집 항목:
- 파일 구조(예: `find`, `ls` 등 동등 명령)
- 핵심 파일 내용(README, 설정 파일, 엔트리 포인트)
- 분석 대상 파악에 필요한 주요 모듈 샘플

`CONTENT_TYPE`을 `"project"`로 설정한다.

#### 모드 C: 대화 컨텍스트 폴백

모드 A, B 모두 충분한 입력이 없으면 현재 대화 컨텍스트에서 분석 대상을 추론해 사용한다.
추론할 수 없으면 사용자에게 분석 대상을 명시해달라고 보고하고 중단한다.

**Truncation**: 환경변수 `ANALYZE_MAX_CONTENT_LINES` (기본값: 1000) 초과 시
처음 N줄만 사용하고 `[... truncated ...]` 표시를 추가한다.

### Step 3: 세션 ID 생성 및 출력 디렉토리 준비

세션별 고유 ID를 생성하고 이후 모든 출력 파일명에 사용한다.

```bash
SESSION_ID=$(date +%Y%m%d-%H%M%S)
mkdir -p ~/.ai
echo "Session ID: $SESSION_ID"
```

`SESSION_ID` 값을 기억하여 이후 모든 파일 경로에 사용한다.
출력 파일 패턴: `~/.ai/analyze-{SESSION_ID}-iter-{N}.json`

### Step 4: 초기 분석 실행 (Iteration 1)

#### 4a. 프롬프트 작성

Write 도구를 사용하여 `/tmp/analyze-prompt.txt`에 프롬프트를 작성한다.
아래 템플릿에서 `{USER_REQUEST}`, `{CONTENT_SECTION}`, `{ITERATION}` 을 치환한다.

**`CONTENT_TYPE`이 `"explicit"`인 경우** `{CONTENT_SECTION}`을 다음으로 구성한다:

````text
## Analysis Target
```
{ANALYSIS_CONTENT}
```
````

**`CONTENT_TYPE`이 `"project"`인 경우** `{CONTENT_SECTION}`을 다음으로 구성한다:

````text
## Project Structure
```
{ANALYSIS_CONTENT}
```
````

**초기 분석 프롬프트 템플릿**:

```text
You are a systematic, evidence-based analyst. Your task is to perform a deep
analysis of the provided content and produce structured, actionable insights.

## Analysis Request
{USER_REQUEST}

{CONTENT_SECTION}

## Instructions
1. Thoroughly examine the provided content.
2. Identify patterns, issues, and opportunities across all relevant dimensions.
3. For code: check architecture, patterns, complexity, dependencies, quality, security, performance.
4. For logs: check patterns, anomalies, error frequency, correlations.
5. For any content: identify root causes, not just symptoms.
6. Quantify findings where possible (counts, percentages, complexity scores).
7. Prioritize findings by severity and impact.
8. Provide actionable, specific recommendations with estimated effort.

## Output Requirements
Respond with ONLY valid JSON matching this structure:
{
  "status": "complete" | "partial",
  "summary": "<one paragraph summary of analysis>",
  "scope": "<what was analyzed>",
  "findings": [
    {
      "category": "<e.g., architecture, security, performance, quality, dependency, pattern>",
      "severity": "critical" | "major" | "minor" | "info",
      "title": "<short title>",
      "description": "<detailed description>",
      "evidence": "<file:line reference or data evidence>",
      "recommendation": "<specific actionable recommendation>"
    }
  ],
  "metrics": {
    "<metric_name>": <value>,
    ...
  },
  "recommendations": [
    {
      "priority": "high" | "medium" | "low",
      "title": "<short title>",
      "description": "<detailed description with expected impact>",
      "effort": "trivial" | "small" | "medium" | "large"
    }
  ],
  "iteration": {ITERATION}
}

Be thorough and evidence-based. Every finding must reference specific files, lines, or data.
Output ONLY the JSON object, no markdown fences, no explanation before or after.
```

#### 4b. Codex 실행

```bash
JSONL_LOG="$HOME/.ai/analyze-${SESSION_ID}-events.jsonl"
touch "$JSONL_LOG"
tail -f "$JSONL_LOG" | "$HOME/.ai/stream-progress.sh" &
TAIL_PID=$!

CODEX_HOME="$HOME/.codex-analyze" codex exec \
  --json \
  --sandbox "${ANALYZE_SANDBOX:-workspace-read}" \
  --output-schema "$HOME/.codex-analyze/analyze-schema.json" \
  --output-last-message ~/.ai/analyze-${SESSION_ID}-iter-1.json \
  - < /tmp/analyze-prompt.txt \
  >> "$JSONL_LOG"

sleep 1
kill $TAIL_PID 2>/dev/null
wait $TAIL_PID 2>/dev/null
```

실패 시 에러를 사용자에게 보고하고 중단한다.

#### 4c. 결과 읽기 및 검증

Read 도구로 `~/.ai/analyze-{SESSION_ID}-iter-1.json`을 읽는다.

JSON이 유효하지 않으면 Bash로 추출을 시도한다:

```bash
jq . ~/.ai/analyze-${SESSION_ID}-iter-1.json
```

jq도 실패하면 에러를 보고하고 중단한다.

`status`, `findings` 값을 파악한다.

### Step 5: 반복 개선 루프

**중단 조건**: 다음 중 하나라도 충족되면 반복을 중단하고 Step 6으로 진행한다:

- `status == "complete"` 이고 `findings`에 critical 이슈가 없음
- 반복 횟수가 `ANALYZE_MAX_ITER` (기본값: 3)에 도달

**계속 조건**: 중단 조건이 충족되지 않으면 개선 프롬프트를 작성하여 다시 실행한다.

#### 개선 프롬프트 템플릿

Write 도구로 `/tmp/analyze-prompt.txt`를 다음 내용으로 덮어쓴다:

```text
You are continuing a deep analysis from a previous iteration. Review the prior
results, identify missed patterns or blind spots, and produce a refined,
more complete analysis.

## Analysis Request
{USER_REQUEST}

{CONTENT_SECTION}

## Previous Analysis (Iteration {PREV_ITERATION})
{PREVIOUS_RESULT_JSON}

## Refinement Instructions
1. Validate previous findings: keep accurate findings, correct weak ones.
2. Search for missed patterns, correlations, and root causes.
3. Improve quantification and evidence quality.
4. Re-prioritize findings and recommendations by impact and effort.
5. If analysis is already complete, keep structure and update iteration only.

## Output Requirements
Respond with ONLY valid JSON (same schema as before).
Set "iteration" to {ITERATION}.
Output ONLY the JSON object, no markdown fences, no explanation before or after.
```

실행 명령 (iteration 번호에 맞게 출력 파일 변경):

```bash
JSONL_LOG="$HOME/.ai/analyze-${SESSION_ID}-events.jsonl"
touch "$JSONL_LOG"
tail -f "$JSONL_LOG" | "$HOME/.ai/stream-progress.sh" &
TAIL_PID=$!

CODEX_HOME="$HOME/.codex-analyze" codex exec \
  --json \
  --sandbox "${ANALYZE_SANDBOX:-workspace-read}" \
  --output-schema "$HOME/.codex-analyze/analyze-schema.json" \
  --output-last-message ~/.ai/analyze-${SESSION_ID}-iter-{N}.json \
  - < /tmp/analyze-prompt.txt \
  >> "$JSONL_LOG"

sleep 1
kill $TAIL_PID 2>/dev/null
wait $TAIL_PID 2>/dev/null
```

**에러 폴백**: `codex exec`가 실패하면 이전 iteration의 결과를 최종 결과로 사용한다.

### Step 6: 최종 결과 저장

마지막 iteration의 결과 파일을 `~/.ai/analyze-{SESSION_ID}-result.json`으로 복사한다:

```bash
cp ~/.ai/analyze-${SESSION_ID}-iter-{LAST_N}.json ~/.ai/analyze-${SESSION_ID}-result.json
```

임시 프롬프트 파일을 정리한다:

```bash
rm -f /tmp/analyze-prompt.txt
```

### Step 7: 결과 보고

JSON 결과를 다음 형식으로 정리하여 사용자에게 보고한다:

```text
## Codex Analyze 결과

**Status**: {status} | **Scope**: {scope} | **Iterations**: {iteration}

### Summary
{summary}

### Findings ({count}건)
| Severity | Category | Title | Description | Recommendation |
|----------|----------|-------|-------------|----------------|
| ... | ... | ... | ... | ... |

### Metrics
| Metric | Value |
|--------|-------|
| ... | ... |

### Recommendations ({count}건)
| Priority | Title | Effort | Description |
|----------|-------|--------|-------------|
| ... | ... | ... | ... |
```

### Step 8: 후속 조치 제안

- critical 이슈가 있으면: 즉시 대응을 위한 우선순위 액션 플랜을 제안한다.
- recommendations가 있으면: 우선순위/노력도 기반 구현 순서를 제안한다.
- 그 외에는: 분석 완료를 보고하고 종료한다.

## Configuration

| 환경변수                    | 기본값         | 설명                      |
| --------------------------- | -------------- | ------------------------- |
| `ANALYZE_MAX_ITER`          | 3              | 최대 반복 횟수            |
| `ANALYZE_MAX_CONTENT_LINES` | 1000           | 콘텐츠 최대 줄 수         |
| `ANALYZE_SANDBOX`           | workspace-read | Codex sandbox 모드        |

## Notes

- Codex는 workspace-read sandbox에서 실행되어 분석 전용(읽기만)입니다.
- 결과는 `~/.ai/analyze-{SESSION_ID}-result.json`에 저장됩니다.
- `~/.ai/` 디렉토리에 런타임 출력물을 저장합니다.
