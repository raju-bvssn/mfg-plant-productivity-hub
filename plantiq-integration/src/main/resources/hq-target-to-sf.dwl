%dw 2.0
/*
  Maps a POST /hq-targets JSON request body to a GWB_HQ_Target__c sObject
  record array ready for salesforce:create.

  Expected payload fields (from HQ Target Experience API):
    name              String   required
    quarter           String   optional  — must be Q1-Q4 2026
    plantCode         String   required  — resolved to Plant__c ID in the flow
    plantShopId       String   optional  — direct Salesforce ID of GWB_Plant_Shop__c
    targetFte         Number   required  — Target_FTE__c
    approvedFteCoverage Number optional  — Approved_FTE_Coverage__c (default 0)
    productionContext String   optional  — Production_Context__c

  Expected vars:
    plantId    String  — resolved GWB_Plant__c ID (from SOQL lookup on Plant_Code__c)

  Output: application/java Array<Object> for salesforce:create records param
*/
output application/java

var req            = payload
var validQuarters  = ["Q1 2026", "Q2 2026", "Q3 2026", "Q4 2026"]

// Sanitise — return null if value is blank or not in allowed set
fun safeQuarter(q) =
    if (q != null and (validQuarters contains q)) q else null

// Clamp FTE to 1 decimal place, treat missing as null (required field — SF will reject)
fun roundFte(n) =
    if (n == null) null
    else ((n * 10) as Number {class: "java.lang.Long"}) / 10.0

// Trim production context to TextArea max (32768 chars) — safe guard
fun safeText(s) =
    if (s == null or s == "") null
    else s[0 to 32767]

---
[{
    Name:                     req.name,
    Quarter__c:               safeQuarter(req.quarter default null),
    Plant__c:                 vars.plantId,
    Plant_Shop__c:            req.plantShopId default null,
    Target_FTE__c:            roundFte(req.targetFte),
    Approved_FTE_Coverage__c: roundFte(req.approvedFteCoverage default 0.0),
    Production_Context__c:    safeText(req.productionContext default null)
}]
