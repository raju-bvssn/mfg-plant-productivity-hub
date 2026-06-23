public with sharing class GWBYearTriggerHandler {
    private static final String PUBLISHED_STATUS = 'Published';

    // Enqueues draft Plant Shop Target creation for GWB Years that have newly become Published.
    public static void createPlantShopTargetsForPublishedYears(List<GWB_Year__c> newYears, Map<Id, GWB_Year__c> oldYearMap) {
        List<Id> publishedYearIds = new List<Id>();
        for (GWB_Year__c gwbYear : newYears) {
            GWB_Year__c oldYear = oldYearMap != null ? oldYearMap.get(gwbYear.Id) : null;
            if (
                gwbYear.Status__c == PUBLISHED_STATUS &&
                (oldYear == null || oldYear.Status__c != PUBLISHED_STATUS)
            ) {
                publishedYearIds.add(gwbYear.Id);
            }
        }

        if (!publishedYearIds.isEmpty()) {
            System.enqueueJob(new PlantShopTargetDraftCreator.CreateDraftPlantShopTargetsJob(publishedYearIds, 0, 0));
        }
    }
}