# PlantIQ — Architecture Diagrams

Two AI patterns share a single Salesforce data layer and a single Slack workspace.

---

## High-Level System Map

```mermaid
graph TB
    subgraph Edge["IoT Edge"]
        PI["🎥 Raspberry Pi Camera<br/>(Python + OpenCV)"]
    end

    subgraph MQ["Anypoint MQ"]
        QUEUE["plantiq-edge-signals<br/>queue"]
        DLQ["Dead Letter Queue<br/>(retry × 3)"]
    end

    subgraph MuleSoft["MuleSoft — Anypoint Code Builder"]
        INGEST["ingest-edge-signal-flow<br/>(MQ consumer + DataWeave)"]
        AGENT_FABRIC["Agent Fabric<br/>plantiq-conversational-flow"]
    end

    subgraph SF["Salesforce (headless data layer + Agentforce)"]
        APEX_IN["IngestEdgeSignalController<br/>(Apex REST)"]
        EDGE_OBJ["GWB_Edge_Signal__c<br/>(evidence store)"]
        TARGET_OBJ["GWB_HQ_Target__c<br/>(mandate → trigger)"]
        FLOW["Process_HQ_Target<br/>(Record-Triggered Flow)"]
        AGENTFORCE["Agentforce + Einstein LLM<br/>(Prompt Template)"]
        IDEA_OBJ["GWB_Productivity_Idea__c"]
        MCP["plantiq-salesforce-mcp<br/>(Node.js MCP server)"]
    end

    subgraph Slack["Slack #plant-productivity"]
        BOT["Slack Bot<br/>(Events API)"]
        CARD["Block Kit Card<br/>Approve / Reject / More Info"]
        CONVO["Conversational replies"]
    end

    PI -->|"HTTPS POST JSON"| QUEUE
    QUEUE -->|"MQ Connector"| INGEST
    INGEST -->|"HTTPS POST OAuth2"| APEX_IN
    APEX_IN --> EDGE_OBJ

    TARGET_OBJ -->|"After Insert/Update"| FLOW
    FLOW -->|"reads signals as evidence"| EDGE_OBJ
    FLOW --> AGENTFORCE
    AGENTFORCE --> IDEA_OBJ
    AGENTFORCE -->|"Slack Incoming Webhook"| CARD
    CARD -->|"button click"| SF

    BOT -->|"user question"| AGENT_FABRIC
    AGENT_FABRIC -->|"MCP tools"| MCP
    MCP -->|"SOQL via REST API"| SF
    AGENT_FABRIC -->|"Slack Bot API"| CONVO

    style Edge fill:#fff3e0,stroke:#e65100
    style MQ fill:#e3f2fd,stroke:#1565c0
    style MuleSoft fill:#e8f5e9,stroke:#2e7d32
    style SF fill:#f3e5f5,stroke:#6a1b9a
    style Slack fill:#e0f2f1,stroke:#00695c
```

---

## Pattern 1 — IoT Pipeline + HQ-Triggered Recommendation

```mermaid
sequenceDiagram
    participant PI as Raspberry Pi
    participant MQ as Anypoint MQ
    participant MU as MuleSoft Flow
    participant SF_REST as Salesforce<br/>Apex REST
    participant EDGE as GWB_Edge_Signal__c
    participant HQ as HQ Admin
    participant TARGET as GWB_HQ_Target__c
    participant FLOW as Record-Triggered Flow<br/>Process_HQ_Target
    participant AG as Agentforce<br/>+ Einstein LLM
    participant IDEA as GWB_Productivity_Idea__c
    participant SLACK as Slack

    PI->>MQ: POST edge signal JSON<br/>(bin depletion / micro-stoppage / idle time)
    MQ->>MU: MQ Connector delivers message
    MU->>SF_REST: POST /services/apexrest/edge-signal/<br/>OAuth 2.0 Client Credentials
    SF_REST->>EDGE: Insert record<br/>Processed__c = false
    Note over EDGE: Stored as evidence<br/>No Slack trigger

    HQ->>TARGET: Create / update GWB_HQ_Target__c<br/>(SHA Assembly — 5 FTE — Q2)
    TARGET->>FLOW: After Insert / After Update trigger

    FLOW->>FLOW: Step 1: RetrievePlantContextAction<br/>Target → Shop → Plant → Functions<br/>+ recent Edge Signals (enrichment)
    FLOW->>FLOW: Step 2: MatchIdeaLibraryAction<br/>Query GWB_Idea_Library__c by signal type
    FLOW->>FLOW: Step 3: ScoreBenchmarksAction<br/>Score ideas vs GWB_Plant_Benchmark__c
    FLOW->>AG: Step 4: BuildRecommendationAction<br/>ConnectApi.EinsteinLLM.generateMessages()
    AG-->>FLOW: selectedIdea, FTE range, $ estimate,<br/>confidence score, reasoning
    FLOW->>IDEA: Step 5: CreateIdeaRecordAction<br/>Status = Pending Approval, AI_Generated = true
    FLOW->>SLACK: Step 6: PostToSlackAction<br/>Block Kit card — Incoming Webhook

    SLACK-->>HQ: Approve / Reject / More Info buttons
    HQ->>SF_REST: Button click → SlackCallbackController
    SF_REST->>IDEA: Update Status__c = Approved / Rejected
    SF_REST->>SLACK: Thread reply ✅ Approved by Jordan Smith
```

---

## Pattern 2 — Conversational Q&A (Headless Salesforce)

```mermaid
sequenceDiagram
    participant USER as Plant / HQ User
    participant SLACK as Slack<br/>#plant-productivity
    participant MU_AF as MuleSoft<br/>Agent Fabric
    participant MCP as plantiq-salesforce-mcp<br/>(Node.js)
    participant SF as Salesforce REST API

    USER->>SLACK: "How close is SHA Assembly<br/>to its Q2 FTE target?"
    SLACK->>MU_AF: Events API POST<br/>(message event)
    MU_AF->>MU_AF: Verify Slack signing secret<br/>(HMAC-SHA256)
    MU_AF->>MU_AF: Agent Fabric reasoning loop<br/>selects tool: query_hq_targets

    MU_AF->>MCP: call query_hq_targets<br/>{plant: "SHA", quarter: "Q2"}
    MCP->>SF: GET /services/data/v62.0/query/<br/>SELECT Target_FTE__c, Gap_To_Target__c<br/>FROM GWB_HQ_Target__c WHERE ...
    SF-->>MCP: {targetFTE: 5.0, approvedCoverage: 2.3, gap: 2.7}
    MCP-->>MU_AF: tool result

    MU_AF->>MU_AF: Compose answer from tool result
    MU_AF->>SLACK: Bot API reply to thread<br/>"SHA Assembly is 2.7 FTE short of its<br/>5.0 FTE Q2 target. 2.3 FTE covered<br/>by 12 approved ideas."
    SLACK-->>USER: Thread reply in #plant-productivity

    Note over USER,SF: All Salesforce access is headless<br/>No Salesforce UI opened at any point
```

---

## Data Model Relationships

```mermaid
erDiagram
    GWB_Plant__c {
        string Plant_Code__c
        string Location__c
        boolean Active__c
    }
    GWB_Plant_Shop__c {
        lookup Plant__c
        string Shop_Type__c
        boolean Active__c
    }
    GWB_Plant_Function__c {
        lookup Plant_Shop__c
        string Station__c
        number Auth_Positions__c
        number Current_Headcount__c
    }
    GWB_HQ_Target__c {
        lookup Plant__c
        lookup Plant_Shop__c
        number Target_FTE__c
        number Approved_FTE_Coverage__c
        number Gap_To_Target__c
        string Quarter__c
        string Production_Context__c
    }
    GWB_Edge_Signal__c {
        lookup Plant_Function__c
        string Signal_Type__c
        string Risk__c
        number Current_Level__c
        number Minutes_To_Empty__c
        boolean Processed__c
        string Image_URL__c
    }
    GWB_Idea_Library__c {
        string Idea_Category__c
        multipicklist Applicable_Signal_Types__c
        number Typical_FTE_Min__c
        number Typical_FTE_Max__c
        string Typical_Effort__c
    }
    GWB_Plant_Benchmark__c {
        lookup Plant__c
        lookup Idea_Library__c
        string Shop_Type__c
        number Achieved_FTE__c
        string Quarter__c
    }
    GWB_Productivity_Idea__c {
        lookup Plant_Function__c
        lookup Idea_Library__c
        lookup Edge_Signal__c
        string Status__c
        number FTE_Impact__c
        number Dollar_Impact__c
        number Confidence_Score__c
        boolean AI_Generated__c
        string Slack_Message_TS__c
    }

    GWB_Plant__c ||--o{ GWB_Plant_Shop__c : "has shops"
    GWB_Plant_Shop__c ||--o{ GWB_Plant_Function__c : "has functions"
    GWB_Plant__c ||--o{ GWB_HQ_Target__c : "has targets"
    GWB_Plant_Shop__c ||--o{ GWB_HQ_Target__c : "scoped to shop"
    GWB_Plant_Function__c ||--o{ GWB_Edge_Signal__c : "generates signals"
    GWB_Plant_Function__c ||--o{ GWB_Productivity_Idea__c : "has ideas"
    GWB_Idea_Library__c ||--o{ GWB_Productivity_Idea__c : "sourced from"
    GWB_Idea_Library__c ||--o{ GWB_Plant_Benchmark__c : "evidenced by"
    GWB_Edge_Signal__c ||--o{ GWB_Productivity_Idea__c : "informed by"
```

---

## Key Roles & Access

```mermaid
graph LR
    subgraph HQ["HQ Admin — Alex Chen"]
        HQ_CAN["✅ Create / edit HQ Targets<br/>✅ View all productivity data<br/>❌ Edit Productivity Ideas"]
    end

    subgraph PLANT["Plant Admin — Jordan Smith"]
        PLANT_CAN["✅ Create / edit Productivity Ideas<br/>✅ View HQ Targets (read-only)<br/>❌ Edit HQ Targets"]
    end

    subgraph SLACK_ACTIONS["In Slack"]
        APPROVE["Click Approve → Idea = Approved"]
        REJECT["Click Reject → Idea = Rejected"]
        INFO["Click More Info → thread with<br/>assumptions + benchmarks + SF link"]
    end

    HQ -->|"sets mandate"| APPROVE
    PLANT --> APPROVE
    PLANT --> REJECT
    PLANT --> INFO

    style HQ fill:#e3f2fd,stroke:#1565c0
    style PLANT fill:#e8f5e9,stroke:#2e7d32
    style SLACK_ACTIONS fill:#e0f2f1,stroke:#00695c
```
