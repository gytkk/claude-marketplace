---
description: >-
  Codex 기반 범용 심층 분석. 코드, 로그, 에러, 성능 등 임의의 대상을
  분석하여 구조화된 인사이트를 제공합니다.
argument-hint: "<분석 대상 설명>"
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - WebFetch
  - WebSearch
  - mcp__codex__codex
  - mcp__codex__codex-reply
---

# Codex Analyze

Codex MCP 도구를 사용하여 코드, 로그, 에러, 성능 등 임의의 대상을 심층 분석하고
구조화된 인사이트를 제공합니다.

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

### Step 4: 초기 분석 실행 (Iteration 1)

#### 4a. Agent persona 읽기

Read 도구로 `${CLAUDE_PLUGIN_ROOT}/agents/codex-analyze-agents.md`를 읽어 `AGENT_PERSONA` 내용을 확보한다.

#### 4b. 프롬프트 구성

아래 템플릿에서 `{USER_REQUEST}`, `{CONTENT_SECTION}`, `{ITERATION}`, `{AGENT_PERSONA}`를 치환하여 프롬프트 문자열을 구성한다.

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
{AGENT_PERSONA}

---

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

#### 4c. Codex MCP 호출

`mcp__codex__codex` 도구를 호출하여 구성한 프롬프트를 `prompt` 파라미터로 전달한다.

응답에서 `threadId`를 저장하고, 응답 텍스트에서 JSON 결과를 파싱한다.

#### 4d. 결과 검증

JSON이 유효한지 확인한다. 유효하지 않으면 에러를 보고하고 중단한다.

`status`, `findings` 값을 파악한다.

### Step 5: 반복 개선 루프

**중단 조건**: 다음 중 하나라도 충족되면 반복을 중단하고 Step 6으로 진행한다:

- `status == "complete"` 이고 `findings`에 critical 이슈가 없음
- 반복 횟수가 `ANALYZE_MAX_ITER` (기본값: 3)에 도달

**계속 조건**: 중단 조건이 충족되지 않으면 `mcp__codex__codex-reply`로 개선을 요청한다.

#### 개선 메시지 템플릿

`mcp__codex__codex-reply` 도구에 `threadId`와 아래 `message`를 전달한다.
Codex가 이전 컨텍스트를 기억하므로 원본 콘텐츠를 다시 보낼 필요가 없다.

```text
Continue refining your analysis from iteration {PREV_ITERATION}.

## Refinement Instructions
1. Validate previous findings: keep accurate findings, correct weak ones.
2. Search for missed patterns, correlations, and root causes.
3. Improve quantification and evidence quality.
4. Re-prioritize findings and recommendations by impact and effort.
5. If analysis is already complete, keep structure and update iteration only.

Respond with ONLY valid JSON (same schema as before).
Set "iteration" to {ITERATION}.
Output ONLY the JSON object, no markdown fences, no explanation before or after.
```

응답 텍스트에서 JSON 결과를 파싱하고, `status`와 `findings`를 재확인한다.

**에러 폴백**: MCP 호출이 실패하면 이전 iteration의 결과를 최종 결과로 사용한다.

### Step 6: 최종 결과 저장

최종 JSON 결과를 `~/.ai/analyze-{SESSION_ID}-result.json`에 저장한다:

```bash
cat > ~/.ai/analyze-${SESSION_ID}-result.json << 'RESULT_EOF'
{FINAL_RESULT_JSON}
RESULT_EOF
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

## Notes

- Codex MCP 도구를 통해 분석을 수행하며, thread 기반 대화로 반복 개선이 가능합니다.
- 결과는 `~/.ai/analyze-{SESSION_ID}-result.json`에 저장됩니다.
- `~/.ai/` 디렉토리에 런타임 출력물을 저장합니다.
