@RestResource(urlMapping='/edge-signal/*')
global with sharing class IngestEdgeSignalController {

    @HttpPost
    global static String doPost() {
        RestRequest req = RestContext.request;
        String body = req.requestBody.toString();

        Map<String, Object> payload;
        try {
            payload = (Map<String, Object>) JSON.deserializeUntyped(body);
        } catch (Exception e) {
            RestContext.response.statusCode = 400;
            return JSON.serialize(new Map<String, String>{ 'error' => 'Invalid JSON: ' + e.getMessage() });
        }

        GWB_Edge_Signal__c sig = new GWB_Edge_Signal__c();
        sig.Station__c         = (String)  payload.get('station');
        sig.Signal_Type__c     = (String)  payload.get('signal_type');
        sig.Risk__c            = (String)  payload.get('risk');
        sig.Raw_JSON__c        = body;
        sig.Processed__c       = false;

        if (payload.get('current_level') != null)
            sig.Current_Level__c = Decimal.valueOf(String.valueOf(payload.get('current_level')));
        if (payload.get('minutes_to_empty') != null)
            sig.Minutes_To_Empty__c = Decimal.valueOf(String.valueOf(payload.get('minutes_to_empty')));
        if (payload.get('image_url') != null)
            sig.Image_URL__c = (String) payload.get('image_url');

        String plantCode = (String) payload.get('plant_code');
        String stationName = sig.Station__c;
        if (plantCode != null && stationName != null) {
            List<GWB_Plant__c> plants = [SELECT Id FROM GWB_Plant__c WHERE Plant_Code__c = :plantCode LIMIT 1];
            if (!plants.isEmpty()) {
                List<GWB_Plant_Shop__c> shops = [SELECT Id FROM GWB_Plant_Shop__c WHERE Plant__c = :plants[0].Id];
                if (!shops.isEmpty()) {
                    Set<Id> shopIds = new Map<Id, GWB_Plant_Shop__c>(shops).keySet();
                    List<GWB_Plant_Function__c> fns = [
                        SELECT Id FROM GWB_Plant_Function__c
                        WHERE Station__c = :stationName AND Plant_Shop__c IN :shopIds
                        LIMIT 1
                    ];
                    if (!fns.isEmpty()) sig.Plant_Function__c = fns[0].Id;
                }
            }
        }

        insert sig;
        RestContext.response.statusCode = 201;
        return JSON.serialize(new Map<String, String>{ 'id' => sig.Id });
    }
}
