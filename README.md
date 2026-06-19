# PlantIQ — Manufacturing Plant Productivity Hub

## Problem / Solution

Manufacturing plants operating under HQ-mandated FTE reduction targets have no systematic way to identify, evaluate, and act on productivity improvement opportunities at the station level. Plant managers rely on manual observation and institutional knowledge to propose initiatives, while HQ has no real-time visibility into whether plants are on track to meet targets. This creates a gap between the mandate and execution — ideas are slow to surface, lack cross-plant evidence, and require lengthy approval cycles.

**PlantIQ** closes this gap by placing AI at the point of signal. Raspberry Pi cameras on the shop floor continuously monitor for production anomalies (bin depletions, micro-stoppages, idle time). Each signal triggers a MuleSoft integration pipeline that ingests the event into Salesforce, where an Agentforce AI agent retrieves plant context, matches the signal to a curated Idea Library of proven interventions, scores recommendations against cross-plant benchmark evidence, and posts a grounded, evidence-backed recommendation to Slack for one-click approval. HQ sees live gap-to-target coverage on a dashboard; plant managers act in seconds rather than weeks.

---

## Architecture Overview

```
Raspberry Pi Camera
       │ HTTPS POST (JSON)
       ▼
Anypoint MQ (plantiq-edge-signals queue)
       │ MQ Connector
       ▼
MuleSoft Integration Flow (Anypoint Code Builder)
       │ HTTPS POST OAuth2
       ▼
Salesforce Apex REST (IngestEdgeSignalController)
       │ Record insert
       ▼
Record-Triggered Flow (Process_Edge_Signal)
       │ Invocable Apex chain
       ▼
Agentforce AI (Prompt Template + Einstein LLM)
       │ HTTP POST
       ▼
Slack #plant-productivity (Block Kit card)
       │ Button click → HTTPS POST
       ▼
SlackCallbackController → Status update in Salesforce
       │
       ▼
Reports & Dashboard (Gap-to-Target live coverage)
```

---

## Low Level Design

### 1. Raspberry Pi Camera Layer

- **Hardware:** Raspberry Pi 4B + Pi Camera Module v3, running Raspberry Pi OS Lite
- **Language:** Python 3.11 — libraries: `picamera2`, `opencv-python`, `boto3`, `requests`
- **Signal detection logic:**
  - **Bin-Depletion:** OpenCV captures frame every 30s → HSV mask on bin region → pixel fill ratio < 20% triggers event. `current_level` = fill %, `minutes_to_empty` = derived from depletion rate over last 5 readings
  - **Micro-Stoppage:** Frame differencing every 500ms → if delta < motion threshold for >90s → triggers event. `stoppages_per_hour` = counter reset every 60 min
  - **Idle-Time:** Same frame differencing with longer window (>5 min no motion)
- **Image upload:** Before publishing, Pi uploads JPEG frame to S3 bucket `plantiq-images` via `boto3`. S3 URL embedded in payload as `image_url`
- **Published JSON payload:**
```json
{
  "plant_code": "SHA",
  "station": "Station 4",
  "signal_type": "Bin-Depletion",
  "risk": "High",
  "current_level": 8.0,
  "minutes_to_empty": 12,
  "stoppages_per_hour": null,
  "image_url": "https://s3.amazonaws.com/plantiq-images/sha-sta4-20260619-143201.jpg",
  "device_id": "rpi-sha-sta4-001",
  "captured_at": "2026-06-19T14:32:01Z"
}
```
- **Destination:** HTTP POST to Anypoint MQ REST API (buffered — not direct to MuleSoft)
- **Retry logic:** If MQ POST fails, appends event to local `edge_buffer.json`. Background thread retries every 60s
- **Dev simulator:** `python simulate_edge.py --plant SHA --station "Station 4" --risk High` replicates the same payload without physical hardware

---

### 2. Anypoint MQ Layer

- **Queue name:** `plantiq-edge-signals` (standard queue)
- **Dead Letter Queue:** `plantiq-edge-signals-dlq` — messages failing 3 processing attempts land here for manual inspection
- **Message TTL:** 24 hours
- **Publish endpoint (Pi calls this):**
  - `POST https://mq.us-east-1.anypoint.mulesoft.com/api/v1/organizations/{orgId}/environments/{envId}/destinations/plantiq-edge-signals/messages`
  - Auth: Client Credentials (Pi holds `client_id` + `client_secret` as env vars)
  - Body: base64-encoded JSON payload, `contentType: application/json`
- **Subscriber:** MuleSoft Anypoint MQ Connector polls this queue — not HTTP pull by MuleSoft

---

### 3. MuleSoft Integration Layer (Anypoint Code Builder)

- **Project name:** `plantiq-integration`
- **Runtime:** Mule 4.6, deployed to CloudHub 2.0

**Flow 1: `ingest-edge-signal-flow`**
- **Source:** Anypoint MQ Subscriber → queue `plantiq-edge-signals`, `maxBatchSize=1`, `pollingTime=5000ms`
- **Step 1 — Logger:** Log raw message payload for audit trail
- **Step 2 — DataWeave transform** (maps MQ message → Salesforce Apex REST input):
```dataweave
%dw 2.0
output application/json
---
{
  plant_code:       payload.plant_code,
  station:          payload.station,
  signal_type:      payload.signal_type,
  risk:             payload.risk,
  current_level:    payload.current_level default null,
  minutes_to_empty: payload.minutes_to_empty default null,
  image_url:        payload.image_url default null
}
```
- **Step 3 — HTTP Request:** POST to `${salesforce.base_url}/services/apexrest/edge-signal/`
  - Auth: OAuth 2.0 Client Credentials (Salesforce Connected App)
  - Headers: `Content-Type: application/json`, `Authorization: Bearer ${access_token}`
- **Step 4 — Response handling:**
  - HTTP 201 → log signal ID, ACK message from MQ
  - HTTP 4xx/5xx → log error, NACK → retry up to 3x → DLQ

**Flow 2: `token-refresh-flow`**
- **Source:** Scheduler, every 55 minutes
- Calls Salesforce OAuth token endpoint, stores token in Object Store v2

**Error handling:**
- On connectivity failure → write to `edge_buffer.json` via File connector
- Anypoint Monitoring alert if DLQ depth > 5

**Connectors required:** `anypoint-mq-connector`, `http-connector`, `objectstore-connector`

---

### 4. Salesforce — Edge Signal Ingestion

**Apex REST endpoint:** `IngestEdgeSignalController`
- URL mapping: `/services/apexrest/edge-signal/`
- Method: `@HttpPost`
- **Processing:**
  1. Parses JSON body → maps to `GWB_Edge_Signal__c` fields
  2. Resolves `Plant_Function__c` by walking `Plant_Code__c` → `GWB_Plant__c` → `GWB_Plant_Shop__c` → `GWB_Plant_Function__c` where `Station__c` matches
  3. Inserts record with `Processed__c = false`
- **Response HTTP 201:**
```json
{ "id": "a3xHn000000XXXXX" }
```
- **Response HTTP 400:**
```json
{ "error": "Invalid JSON: <message>" }
```

**`GWB_Edge_Signal__c` record created:**
| Field | Value |
|---|---|
| Name (AutoNumber) | SIG-0007 |
| Plant_Function__c | SHA-ASM-Station 4 Final Fit |
| Station__c | Station 4 |
| Signal_Type__c | Bin-Depletion |
| Risk__c | High |
| Current_Level__c | 8.0 |
| Minutes_To_Empty__c | 12 |
| Processed__c | false |
| Raw_JSON__c | {full original payload} |
| Image_URL__c | https://s3.amazonaws.com/... |

---

### 5. Salesforce — Record-Triggered Flow (`Process_Edge_Signal`)

- **Object:** `GWB_Edge_Signal__c`
- **Trigger:** After Insert, entry criteria: `Processed__c = false`
- **Run mode:** System context

**Step 1 → `RetrievePlantContextAction` (Invocable Apex)**
- Input: `{ signalId: recordId }`
- Queries signal → plant function → shop → plant → HQ Target for same shop
- Output:
```
plantName, plantCode, shopName, shopType,
functionName, station, authPositions, currentHeadcount,
targetFTE, approvedFTECoverage, gapToTarget,
productionContext, quarter, signalType, riskLevel
```

**Step 2 → `MatchIdeaLibraryAction` (Invocable Apex)**
- Input: `{ signalType: "Bin-Depletion", maxResults: 5 }`
- Queries `GWB_Idea_Library__c` WHERE `Applicable_Signal_Types__c INCLUDES (signalType)`, ordered by `Typical_FTE_Max__c DESC`
- Output: `matchedIdeasJson` (JSON array), `topIdeaId`, `topIdeaName`
```json
[
  { "ideaLibraryId": "a2wHn000007eN7tIAE", "ideaName": "Bin Replenishment Process",
    "fteMin": 0.6, "fteMax": 1.4, "effort": "Low", "description": "..." },
  { "ideaLibraryId": "a2wHn000007eN7oIAE", "ideaName": "Material Flow Optimization",
    "fteMin": 0.5, "fteMax": 1.2, "effort": "Low", "description": "..." }
]
```

**Step 3 → `ScoreBenchmarksAction` (Invocable Apex)**
- Input: `{ matchedIdeasJson, shopType: "Assembly", productionContext: "EV..." }`
- Queries `GWB_Plant_Benchmark__c` for all matched idea IDs
- Scoring algorithm per idea: base 50 + benchmark exists (+20) + shop type match (+10) + FTE max ≥ 1.0 (+5) + Low effort (+5), capped at 99
- Output: `scoredIdeasJson`, `topIdeaId`, `topIdeaName`, `topConfidenceScore`, `topBenchmarkEvidence`

**Step 4 → `BuildRecommendationAction` (Invocable Apex — calls Prompt Template)**
- Assembles full context from Steps 1–3
- Calls `ConnectApi.EinsteinLLM.generateMessages()` with `PlantIQ_Recommendation` Prompt Template
- Prompt Template merge fields:
  - `{HQ_Gap}`, `{Quarter}`, `{ProductionContext}`, `{Station}`, `{ScoredIdeasJson}`, `{BenchmarkEvidence}`
- LLM instruction: *"Select the single best idea from the provided scored ideas list. Do not suggest ideas outside this list. Return: selected idea name, FTE range, dollar estimate at $130K/FTE, confidence score, 2-sentence reasoning, required validations."*
- Output: `selectedIdeaName`, `fteImpact`, `dollarImpact`, `confidenceScore`, `reasoning`, `requiredValidations`

**Step 5 → `CreateIdeaRecordAction` (Invocable Apex)**
- Creates `GWB_Productivity_Idea__c`:

| Field | Value |
|---|---|
| Name | SHA Sta-4: Bin Replenishment Redesign |
| Plant_Function__c | (from Step 1) |
| Idea_Library__c | (top idea from Step 3) |
| Edge_Signal__c | (triggering signal ID) |
| Status__c | Pending Approval |
| AI_Generated__c | true |
| FTE_Impact__c | 1.2 |
| Dollar_Impact__c | 156000 |
| Confidence_Score__c | 87 |
| Effort__c | Low |
| Assumptions__c | "Assumes bin replenishment route redesign..." |
| Benchmark_Evidence__c | "Spring Hill Plant B: 1.1 FTE Q3 2025..." |
| Required_Validations__c | "Safety review complete. Finance approved." |

**Step 6 → `PostToSlackAction` (Invocable Apex)**
- HTTP POST to Slack Incoming Webhook (URL stored in `PlantIQ_Config__mdt.Slack_Webhook_URL`)
- Block Kit payload structure:
  - **Header block:** "PlantIQ AI Recommendation"
  - **Section 1:** Plant / Shop / HQ Gap / Quarter (4-field grid)
  - **Section 2:** Idea title / FTE impact / Dollar value / Effort / Confidence %
  - **Section 3:** Benchmark evidence (italic text)
  - **Actions block:** 3 buttons — each carries `value = ideaId`

| Button | action_id | style |
|---|---|---|
| Approve | `approve_idea` | primary (green) |
| Reject | `reject_idea` | danger (red) |
| More Info | `more_info_idea` | default + `url` = SF record link |

- Saves Slack message timestamp to `GWB_Productivity_Idea__c.Slack_Message_TS__c`

**Step 7 — Flow Assignment**
- Sets `GWB_Edge_Signal__c.Processed__c = true`

---

### 6. Agentforce / Agent Fabric

**Prompt Template (`PlantIQ_Recommendation.promptTemplate`)**
- Built in Salesforce Prompt Builder (Setup → Prompt Builder)
- Type: Flex Prompt
- 6 merge field inputs (listed in Step 4 above)
- Enforces grounding: LLM can only select from provided scored ideas — cannot hallucinate new categories
- Test in Prompt Builder preview before wiring into `BuildRecommendationAction`

**Agentforce Agent (interactive mode)**
- Topic: "Productivity Idea Recommendation"
- Available actions: all 5 invocable Apex classes registered as Agent Actions
- Used by Plant Admin for conversational queries: "What ideas do I have for Station 12?"
- Channel: Einstein Copilot panel embedded in PlantIQ Lightning app

**MCP Servers (Model Context Protocol)**
- **`plantiq-salesforce-mcp`** (Node.js): exposes SOQL read tools to agent
  - `query_hq_targets` — returns targets by plant/quarter
  - `query_productivity_ideas` — returns ideas by status/plant
  - `query_benchmarks` — returns benchmarks by idea/shop type
- **`plantiq-slack-mcp`** (Node.js): wraps Slack API
  - `post_message` — post to channel
  - `get_thread_replies` — read thread context by `message_ts`
- Both registered in Agent Fabric MCP configuration

---

### 7. Slack Approval Loop

**Incoming Slack interaction payload (POST to `SlackCallbackController`):**
- Content-Type: `application/x-www-form-urlencoded`
- Body: `payload={url-encoded JSON}`
```json
{
  "type": "block_actions",
  "user": { "id": "U123ABC", "name": "jordan.smith" },
  "actions": [{ "action_id": "approve_idea", "value": "a4xHn000000YYYYY" }],
  "container": { "channel_id": "C456DEF", "message_ts": "1718800321.000100" }
}
```

**`SlackCallbackController` processing:**
- URL: `/services/apexrest/slack-callback/`
- Decodes `payload=` URL encoding
- Routes by `action_id`:
  - `approve_idea` → `Status__c = Approved`, thread reply: "✅ Approved by {username}"
  - `reject_idea` → `Status__c = Rejected`, thread reply: "❌ Rejected by {username}"
  - `more_info_idea` → queries idea, posts thread with: assumptions + benchmark evidence + required validations + SF record URL
- Returns HTTP 200 in all cases (Slack requires <3s response)

**Salesforce Site setup:**
- Force.com Site exposes callback endpoint publicly over HTTPS
- Guest user profile requires: Read on `GWB_Productivity_Idea__c`, Execute Apex on `SlackCallbackController`

---

### 8. Reports and Dashboards

**Reports (PlantIQ Reports folder):**

| ID | Name | Type | Grouped By | Columns |
|---|---|---|---|---|
| R1 | Ideas by Status | Summary | `Status__c` | Count, Sum(FTE_Impact__c), Sum(Dollar_Impact__c) |
| R2 | Ideas by Shop | Summary | `Plant_Function__r.Plant_Shop__r.Name` | Count, Sum(FTE), Sum($) — filter: Status IN (Approved, Pending) |
| R3 | HQ Gap vs Coverage | Joined | Plant_Shop (join key) | Target_FTE__c, Approved_FTE_Coverage__c, Gap_To_Target__c per shop/quarter |
| R4 | Signals by Risk | Summary | `Risk__c` + `Signal_Type__c` | Count |
| R5 | AI vs Manual Ideas | Matrix | Rows=Status, Cols=AI_Generated__c | Count |

**Dashboard (`PlantIQ Overview`) — 6 components:**

| # | Title | Type | Source | Filter |
|---|---|---|---|---|
| 1 | Ideas Submitted | Metric (count) | R1 | none |
| 2 | Pipeline Value | Metric (sum $) | R1 | Status != Rejected |
| 3 | Approved Ideas | Metric (count) | R1 | Status = Approved |
| 4 | Realized FTE | Metric (sum FTE) | R1 | Status = Approved |
| 5 | Ideas by Status | Donut chart | R1 | none |
| 6 | Gap vs Coverage by Shop | Horizontal bar | R3 | none |

**Gap_To_Target__c wiring (pending):**
- When `GWB_Productivity_Idea__c.Status__c` changes to `Approved`: Flow walks up to `GWB_Plant_Shop__c` → finds matching `GWB_HQ_Target__c` → sums `FTE_Impact__c` of all Approved ideas for that shop → writes to `Approved_FTE_Coverage__c` → `Gap_To_Target__c = Target_FTE__c - Approved_FTE_Coverage__c`

---

### 9. Integration Points Summary

| From | To | Protocol | Auth |
|---|---|---|---|
| Raspberry Pi | Anypoint MQ | HTTPS POST (REST) | Client Credentials |
| Anypoint MQ | MuleSoft Flow | MQ Connector (internal) | MQ Client ID/Secret |
| MuleSoft | Salesforce Apex REST | HTTPS POST | OAuth 2.0 Client Credentials |
| SF Record-Triggered Flow | Apex Invocable Actions | Internal Apex | System context |
| `PostToSlackAction` | Slack Incoming Webhook | HTTPS POST | Webhook URL (secret in CMT) |
| Slack Interactive | `SlackCallbackController` | HTTPS POST | Slack Signing Secret (HMAC-SHA256) |
| Agent Fabric MCP | Salesforce REST API | HTTPS | OAuth 2.0 |
| Agent Fabric MCP | Slack API | HTTPS | Slack Bot Token |

---

## Data Model

| Object | Description | Key Fields |
|---|---|---|
| `GWB_Plant__c` | Top-level manufacturing facility | `Plant_Code__c`, `Location__c` |
| `GWB_Plant_Shop__c` | Department within a plant | `Plant__c` (lookup), `Shop_Type__c` |
| `GWB_Plant_Function__c` | Production station | `Plant_Shop__c` (lookup), `Station__c`, `Auth_Positions__c`, `Current_Headcount__c` |
| `GWB_HQ_Target__c` | HQ FTE reduction mandate | `Plant__c`, `Plant_Shop__c`, `Target_FTE__c`, `Approved_FTE_Coverage__c`, `Gap_To_Target__c`, `Quarter__c` |
| `GWB_Idea_Library__c` | Curated intervention catalog | `Applicable_Signal_Types__c` (multi-picklist), `Typical_FTE_Min__c`, `Typical_FTE_Max__c`, `Typical_Effort__c` |
| `GWB_Plant_Benchmark__c` | Cross-plant evidence records | `Plant__c`, `Idea_Library__c`, `Achieved_FTE__c`, `Quarter__c`, `Production_Context__c` |
| `GWB_Edge_Signal__c` | IoT inbound events (AutoNumber name) | `Plant_Function__c`, `Signal_Type__c`, `Risk__c`, `Processed__c`, `Raw_JSON__c` |
| `GWB_Productivity_Idea__c` | AI-generated recommendations | `Plant_Function__c`, `Idea_Library__c`, `Edge_Signal__c`, `Status__c`, `FTE_Impact__c`, `Dollar_Impact__c`, `AI_Generated__c` |

---

## User Roles

| User | Permission Set | Can Do | Cannot Do |
|---|---|---|---|
| Alex Chen (`hq.admin@plantiq-demo.com`) | `GWB_HQ_Admin` | Create/edit HQ Targets, view all productivity data read-only | Edit Productivity Ideas |
| Jordan Smith (`jordan.smith@plantiq-demo.com`) | `GWB_Plant_Admin` | Create/edit Productivity Ideas and Edge Signals, view HQ Targets read-only | Edit HQ Targets |

---

## Repository Structure

```
force-app/main/default/
├── applications/          # PlantIQ Lightning App
├── classes/               # Apex — REST endpoints + Invocable actions
│   ├── IngestEdgeSignalController.cls      # MuleSoft → SF entry point
│   ├── RetrievePlantContextAction.cls      # Step 1: plant/target context
│   ├── MatchIdeaLibraryAction.cls          # Step 2: idea matching
│   ├── ScoreBenchmarksAction.cls           # Step 3: benchmark scoring
│   ├── CreateIdeaRecordAction.cls          # Step 5: create idea record
│   ├── PostToSlackAction.cls               # Step 6: Slack Block Kit post
│   └── SlackCallbackController.cls         # Slack button handler
├── customMetadata/        # PlantIQ_Config (Slack webhook URL)
├── objects/               # 8 GWB custom objects + fields + list views
├── permissionsets/        # GWB_HQ_Admin, GWB_Plant_Admin, PlantIQ_Admin
├── profiles/              # Admin profile (FLS for GWB objects)
└── tabs/                  # Custom tabs for all 8 GWB objects

data/
├── seed_data.apex                  # Plants, Shops, Functions, Targets, Library, Benchmarks
├── seed_signals_and_ideas.apex     # Edge Signals + Productivity Ideas (demo data)
└── create_demo_users.apex          # Demo users: HQ Admin + Plant Admin
```

---

## Setup

```bash
# 1. Authenticate to your Salesforce org
sf org login web --alias gwb-demo

# 2. Deploy all metadata
sf project deploy start --target-org gwb-demo --source-dir force-app

# 3. Load seed data
sf apex run --target-org gwb-demo --file data/seed_data.apex
sf apex run --target-org gwb-demo --file data/seed_signals_and_ideas.apex
sf apex run --target-org gwb-demo --file data/create_demo_users.apex

# 4. Update Slack webhook URL
# Edit customMetadata/PlantIQ_Config.Slack_Webhook_URL.md-meta.xml
# Replace REPLACE_WITH_SLACK_WEBHOOK_URL with your actual webhook URL
# Then redeploy:
sf project deploy start --target-org gwb-demo --source-dir force-app/main/default/customMetadata
```
