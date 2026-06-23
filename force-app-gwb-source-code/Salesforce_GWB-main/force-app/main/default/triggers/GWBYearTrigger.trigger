trigger GWBYearTrigger on GWB_Year__c (after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        if (FeatureManagement.checkPermission('Create_Plant_Target_Split_Draft')) {
            GWBYearTriggerHandler.createPlantShopTargetsForPublishedYears(Trigger.new, Trigger.oldMap);
        }
    }
}