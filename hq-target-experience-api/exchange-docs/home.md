# HQ Target Experience API

Experience API exposing `GWB_HQ_Target__c` for POST (create) operations.

- Accepts JSON per the OAS spec (`src/main/resources/api/hq-target-experience-api.yaml`)
- Resolves `plantCode` to `GWB_Plant__c.Id` via SOQL
- Maps and inserts `GWB_HQ_Target__c` via Salesforce JWT connector
- API Manager Instance ID: `20986802` (Sandbox)
