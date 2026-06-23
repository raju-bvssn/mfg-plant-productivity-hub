# HQ Target Experience API — Field Mapping Document

**API Version:** 1.0.0  
**Salesforce Object:** `GWB_HQ_Target__c`  
**Related Objects:** `GWB_Plant__c`, `GWB_Plant_Shop__c`

---

## 1. HQ Target (`GWB_HQ_Target__c`)

| API Field | SF API Name | SF Label | Type | Required | Notes |
|---|---|---|---|---|---|
| `id` | `Id` | Record ID | `string (18-char)` | read-only | System-generated Salesforce record ID |
| `name` | `Name` | Target Name | `string` | Yes | Auto-name or user-supplied label |
| `quarter` | `Quarter__c` | Quarter | `picklist` | No | Values: `Q1 2026`, `Q2 2026`, `Q3 2026`, `Q4 2026` |
| `targetFte` | `Target_FTE__c` | Target FTE Reduction | `Number(6,1)` | Yes | Mandated FTE reduction goal set by HQ admin |
| `approvedFteCoverage` | `Approved_FTE_Coverage__c` | Approved FTE Coverage | `Number(6,1)` | No | Sum of FTE from Approved `GWB_Productivity_Idea__c` records; default `0` |
| `gapToTarget` | `Gap_To_Target__c` | Gap To Target | `Number(6,1)` | read-only | Salesforce formula: `Target_FTE__c − Approved_FTE_Coverage__c` |
| `productionContext` | `Production_Context__c` | Production Context | `TextArea` | No | Free-text HQ notes; used by Agentforce prompt template |
| `plantId` | `Plant__c` | Plant | `Lookup(GWB_Plant__c)` | Yes | Foreign key resolved via `plantCode` on create |
| `plantShopId` | `Plant_Shop__c` | Plant Shop | `Lookup(GWB_Plant_Shop__c)` | No | Scopes target to a specific shop within the plant |
| `createdDate` | `CreatedDate` | Created Date | `datetime` | read-only | ISO 8601 UTC |
| `lastModifiedDate` | `LastModifiedDate` | Last Modified Date | `datetime` | read-only | ISO 8601 UTC |

### 1.1 Embedded Plant (`plant`) — `GWB_Plant__c`

Returned when `?embed=plant` is included. Sourced via `GWB_HQ_Target__c.Plant__c` lookup.

| API Field | SF API Name | SF Label | Type | Notes |
|---|---|---|---|---|
| `plant.id` | `Plant__r.Id` | — | `string` | Salesforce record ID of parent plant |
| `plant.name` | `Plant__r.Name` | Plant Name | `string` | Display name |
| `plant.plantCode` | `Plant__r.Plant_Code__c` | Plant Code | `string(10)` | Unique external ID; used as path param in `/by-plant/{plantCode}` |
| `plant.location` | `Plant__r.Location__c` | Location | `string(100)` | City/state label |
| `plant.active` | `Plant__r.Active__c` | Active | `boolean` | Inactive plants are excluded from target creation |

### 1.2 Embedded Plant Shop (`plantShop`) — `GWB_Plant_Shop__c`

Returned when `?embed=plantShop` is included. Sourced via `GWB_HQ_Target__c.Plant_Shop__c` lookup.

| API Field | SF API Name | SF Label | Type | Notes |
|---|---|---|---|---|
| `plantShop.id` | `Plant_Shop__r.Id` | — | `string` | Salesforce record ID |
| `plantShop.name` | `Plant_Shop__r.Name` | Plant Shop Name | `string` | Display name |
| `plantShop.shopType` | `Plant_Shop__r.Shop_Type__c` | Shop Type | `picklist` | Values: `Assembly`, `Body`, `Paint`, `Stamping`, `Powertrain`, `General` |
| `plantShop.active` | `Plant_Shop__r.Active__c` | Active | `boolean` | |

---

## 2. Create Request → Salesforce Field Mapping

When `POST /hq-targets` is received, the Experience API layer maps the request body to SOQL insert fields as follows:

| Request Body Field | Action | Salesforce Field | Notes |
|---|---|---|---|
| `name` | Direct | `Name` | |
| `quarter` | Direct | `Quarter__c` | Validated against picklist |
| `plantCode` | SOQL Lookup | `Plant__c` | `SELECT Id FROM GWB_Plant__c WHERE Plant_Code__c = :plantCode AND Active__c = true LIMIT 1` |
| `plantShopId` | Direct | `Plant_Shop__c` | Optional; pass `null` for plant-level target |
| `targetFte` | Direct | `Target_FTE__c` | |
| `approvedFteCoverage` | Direct | `Approved_FTE_Coverage__c` | Defaults to `0` if omitted |
| `productionContext` | Direct | `Production_Context__c` | |
| _(not supplied)_ | Computed by SF | `Gap_To_Target__c` | Formula field — never set by API |

---

## 3. Update Request → Salesforce Field Mapping (PATCH)

Only fields present in the request body are updated (`sObject.update` via SOAP/REST).

| Request Body Field | Salesforce Field | Notes |
|---|---|---|
| `name` | `Name` | |
| `quarter` | `Quarter__c` | |
| `targetFte` | `Target_FTE__c` | |
| `approvedFteCoverage` | `Approved_FTE_Coverage__c` | |
| `productionContext` | `Production_Context__c` | |
| `gapToTarget` | _(ignored)_ | Read-only formula; silently dropped if present |

---

## 4. Salesforce Response → API Response Mapping

When reading records (GET), the Salesforce SOQL result is mapped as follows.

### Base SOQL (no embed)

```soql
SELECT Id, Name, Quarter__c, Target_FTE__c, Approved_FTE_Coverage__c,
       Gap_To_Target__c, Production_Context__c, Plant__c, Plant_Shop__c,
       CreatedDate, LastModifiedDate
FROM   GWB_HQ_Target__c
WHERE  ...
```

### SOQL with `embed=plant,plantShop`

```soql
SELECT Id, Name, Quarter__c, Target_FTE__c, Approved_FTE_Coverage__c,
       Gap_To_Target__c, Production_Context__c,
       Plant__c, Plant__r.Name, Plant__r.Plant_Code__c,
       Plant__r.Location__c, Plant__r.Active__c,
       Plant_Shop__c, Plant_Shop__r.Name, Plant_Shop__r.Shop_Type__c,
       Plant_Shop__r.Active__c,
       CreatedDate, LastModifiedDate
FROM   GWB_HQ_Target__c
WHERE  ...
```

### Field mapping

| Salesforce Field | API Response Field | Transform |
|---|---|---|
| `Id` | `id` | None |
| `Name` | `name` | None |
| `Quarter__c` | `quarter` | None |
| `Target_FTE__c` | `targetFte` | camelCase rename |
| `Approved_FTE_Coverage__c` | `approvedFteCoverage` | camelCase rename |
| `Gap_To_Target__c` | `gapToTarget` | camelCase rename |
| `Production_Context__c` | `productionContext` | camelCase rename |
| `Plant__c` | `plantId` | camelCase rename |
| `Plant_Shop__c` | `plantShopId` | camelCase rename; `null` if not set |
| `Plant__r.Id` | `plant.id` | Only present when `embed=plant` |
| `Plant__r.Name` | `plant.name` | Only present when `embed=plant` |
| `Plant__r.Plant_Code__c` | `plant.plantCode` | Only present when `embed=plant` |
| `Plant__r.Location__c` | `plant.location` | Only present when `embed=plant` |
| `Plant__r.Active__c` | `plant.active` | Only present when `embed=plant` |
| `Plant_Shop__r.Id` | `plantShop.id` | Only present when `embed=plantShop` |
| `Plant_Shop__r.Name` | `plantShop.name` | Only present when `embed=plantShop` |
| `Plant_Shop__r.Shop_Type__c` | `plantShop.shopType` | Only present when `embed=plantShop` |
| `Plant_Shop__r.Active__c` | `plantShop.active` | Only present when `embed=plantShop` |
| `CreatedDate` | `createdDate` | Formatted as ISO 8601 UTC |
| `LastModifiedDate` | `lastModifiedDate` | Formatted as ISO 8601 UTC |

---

## 5. Query Filter → SOQL WHERE Clause Mapping

| Query Parameter | SOQL Predicate | Notes |
|---|---|---|
| `plantCode` | `Plant__r.Plant_Code__c = :plantCode` | Case-insensitive; Plant_Code__c has `caseSensitive=false` |
| `quarter` | `Quarter__c = :quarter` | Picklist match |
| `shopType` | `Plant_Shop__r.Shop_Type__c = :shopType` | Requires a plant shop to be linked |
| `pageToken` | `OFFSET :offset` | Token encodes numeric offset as base64 JSON |
| `pageSize` | `LIMIT :pageSize` | Default 25, max 200 |

---

## 6. Error Code Mapping

| HTTP Status | API `code` | Trigger |
|---|---|---|
| `400` | `BAD_REQUEST` | Invalid parameter type or value (e.g. unknown quarter, negative FTE) |
| `401` | `UNAUTHORIZED` | Missing, expired, or invalid OAuth 2.0 bearer token |
| `404` | `NOT_FOUND` | Record ID does not exist or caller has no access |
| `422` | `UNPROCESSABLE_ENTITY` | Business rule failure (e.g. inactive plant, plantShop not under plantCode) |
| `500` | `INTERNAL_ERROR` | Salesforce API error, timeout, or unexpected exception |

---

## 7. Endpoint Summary

| Method | Path | Salesforce Operation | Description |
|---|---|---|---|
| `GET` | `/hq-targets` | `SOQL SELECT` | List all targets (paginated, filterable) |
| `POST` | `/hq-targets` | `sobjects/GWB_HQ_Target__c` POST | Create a new target |
| `GET` | `/hq-targets/{id}` | `sobjects/GWB_HQ_Target__c/{id}` GET | Get single target by SF record ID |
| `PATCH` | `/hq-targets/{id}` | `sobjects/GWB_HQ_Target__c/{id}` PATCH | Partial update |
| `DELETE` | `/hq-targets/{id}` | `sobjects/GWB_HQ_Target__c/{id}` DELETE | Hard delete |
| `GET` | `/hq-targets/by-plant/{plantCode}` | `SOQL SELECT WHERE Plant__r.Plant_Code__c` | List targets for a plant (used by MCP tool) |
| `GET` | `/health` | — | Liveness probe (no auth required) |
