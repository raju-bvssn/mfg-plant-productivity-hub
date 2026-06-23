public with sharing class PlantShopTargetDraftCreator {
    private static final String ACTIVE_PLANT_FUNCTION_STATUS = 'Active';
    private static final String DRAFT_STATUS = 'Draft';
    @TestVisible
    private static Integer dmlRowBudget = 9000;

    private static final List<MonthField> GWB_MONTH_VALUE_FIELDS = new List<MonthField>{
        new MonthField('Jan_Number__c', 'January'),
        new MonthField('Jan_Decimal__c', 'January'),
        new MonthField('Jan_Percent__c', 'January'),
        new MonthField('Feb_Number__c', 'February'),
        new MonthField('Feb_Decimal__c', 'February'),
        new MonthField('Feb_Percent__c', 'February'),
        new MonthField('Mar_Number__c', 'March'),
        new MonthField('Mar_Decimal__c', 'March'),
        new MonthField('Mar_Percent__c', 'March'),
        new MonthField('Apr_Number__c', 'April'),
        new MonthField('Apr_Decimal__c', 'April'),
        new MonthField('Apr_Percent__c', 'April'),
        new MonthField('May_Number__c', 'May'),
        new MonthField('May_Decimal__c', 'May'),
        new MonthField('May_Percent__c', 'May'),
        new MonthField('Jun_Number__c', 'June'),
        new MonthField('Jun_Decimal__c', 'June'),
        new MonthField('Jun_Percent__c', 'June'),
        new MonthField('Jul_Number__c', 'July'),
        new MonthField('Jul_Decimal__c', 'July'),
        new MonthField('Jul_Percent__c', 'July'),
        new MonthField('Aug_Number__c', 'August'),
        new MonthField('Aug_Decimal__c', 'August'),
        new MonthField('Aug_Percent__c', 'August'),
        new MonthField('Sep_Number__c', 'September'),
        new MonthField('Sep_Decimal__c', 'September'),
        new MonthField('Sep_Percent__c', 'September'),
        new MonthField('Oct_Number__c', 'October'),
        new MonthField('Oct_Decimal__c', 'October'),
        new MonthField('Oct_Percent__c', 'October'),
        new MonthField('Nov_Number__c', 'November'),
        new MonthField('Nov_Decimal__c', 'November'),
        new MonthField('Nov_Percent__c', 'November'),
        new MonthField('Dec_Number__c', 'December'),
        new MonthField('Dec_Decimal__c', 'December'),
        new MonthField('Dec_Percent__c', 'December')
    };

    // Creates missing draft Plant Shop Targets and their Shop Manager View items for the given GWB Years.
    public static void createDraftPlantShopTargets(Set<Id> gwbYearIds) {
        if (gwbYearIds == null || gwbYearIds.isEmpty()) {
            return;
        }

        List<Id> orderedGwbYearIds = new List<Id>(gwbYearIds);
        orderedGwbYearIds.sort();
        createDraftPlantShopTargets(orderedGwbYearIds, 0, 0);
    }

    private static void createDraftPlantShopTargets(List<Id> gwbYearIds, Integer yearOffset, Integer groupOffset) {
        if (gwbYearIds == null || gwbYearIds.isEmpty()) {
            return;
        }

        Integer safeYearOffset = yearOffset == null ? 0 : yearOffset;
        if (safeYearOffset >= gwbYearIds.size()) {
            return;
        }

        Id gwbYearId = gwbYearIds[safeYearOffset];
        Integer nextGroupOffset = createDraftPlantShopTargetsForYear(gwbYearId, groupOffset);
        if (nextGroupOffset != null) {
            enqueueContinuation(gwbYearIds, safeYearOffset, nextGroupOffset);
            return;
        }

        Integer nextYearOffset = safeYearOffset + 1;
        if (nextYearOffset < gwbYearIds.size()) {
            enqueueContinuation(gwbYearIds, nextYearOffset, 0);
        }
    }

    private static Integer createDraftPlantShopTargetsForYear(Id gwbYearId, Integer groupOffset) {
        Set<Id> gwbYearIds = new Set<Id>{ gwbYearId };

        Map<Id, GWB_Year__c> gwbYearsById = getGwbYearsById(gwbYearIds);
        Map<String, PlantShopTargetGroup> plantShopTargetGroupsByKey = buildPlantShopTargetGroups(gwbYearIds, gwbYearsById);
        addShopManagerViews(plantShopTargetGroupsByKey);
        overlayExistingDraftPlantShopTargets(gwbYearIds, plantShopTargetGroupsByKey);

        List<PlantShopTargetGroup> plantShopTargetGroups = getOrderedPlantShopTargetGroups(plantShopTargetGroupsByKey);
        Integer safeGroupOffset = groupOffset == null ? 0 : groupOffset;
        List<PlantShopTargetGroup> chunk = getDmlSafeChunk(plantShopTargetGroups, safeGroupOffset);
        insertPlantShopTargetGroups(chunk);

        Integer nextGroupOffset = safeGroupOffset + chunk.size();
        return nextGroupOffset < plantShopTargetGroups.size() ? nextGroupOffset : null;
    }

    private static List<PlantShopTargetGroup> getOrderedPlantShopTargetGroups(
        Map<String, PlantShopTargetGroup> plantShopTargetGroupsByKey
    ) {
        List<String> orderedKeys = new List<String>(plantShopTargetGroupsByKey.keySet());
        orderedKeys.sort();

        List<PlantShopTargetGroup> orderedGroups = new List<PlantShopTargetGroup>();
        for (String key : orderedKeys) {
            orderedGroups.add(plantShopTargetGroupsByKey.get(key));
        }
        return orderedGroups;
    }

    private static List<PlantShopTargetGroup> getDmlSafeChunk(
        List<PlantShopTargetGroup> plantShopTargetGroups,
        Integer groupOffset
    ) {
        List<PlantShopTargetGroup> chunk = new List<PlantShopTargetGroup>();
        Integer rowBudget = getAvailableDmlRowBudget();
        Integer chunkRows = 0;

        for (Integer index = groupOffset; index < plantShopTargetGroups.size(); index++) {
            PlantShopTargetGroup plantShopTargetGroup = plantShopTargetGroups[index];
            Integer groupRows = getDmlRowsNeeded(plantShopTargetGroup);
            if (groupRows == 0) {
                chunk.add(plantShopTargetGroup);
                continue;
            }

            if (chunkRows + groupRows > rowBudget) {
                if (chunk.isEmpty() && groupRows <= getRemainingDmlRows()) {
                    chunk.add(plantShopTargetGroup);
                }
                break;
            }

            chunk.add(plantShopTargetGroup);
            chunkRows += groupRows;
        }

        return chunk;
    }

    private static Integer getAvailableDmlRowBudget() {
        return Math.min(dmlRowBudget, getRemainingDmlRows());
    }

    private static Integer getRemainingDmlRows() {
        return Limits.getLimitDmlRows() - Limits.getDmlRows();
    }

    private static Integer getDmlRowsNeeded(PlantShopTargetGroup plantShopTargetGroup) {
        Integer rowsNeeded = plantShopTargetGroup.plantShopTargetId == null ? 1 : 0;
        for (String shopManagerView : plantShopTargetGroup.shopManagerViews) {
            if (!plantShopTargetGroup.existingShopManagerViews.contains(shopManagerView)) {
                rowsNeeded++;
            }
        }
        return rowsNeeded;
    }

    private static void insertPlantShopTargetGroups(List<PlantShopTargetGroup> plantShopTargetGroups) {
        List<Plant_Shop_Target__c> plantShopTargetsToInsert = new List<Plant_Shop_Target__c>();
        List<PlantShopTargetGroup> pendingPlantShopTargetGroups = new List<PlantShopTargetGroup>();
        for (PlantShopTargetGroup plantShopTargetGroup : plantShopTargetGroups) {
            if (plantShopTargetGroup.plantShopTargetId != null) {
                continue;
            }

            pendingPlantShopTargetGroups.add(plantShopTargetGroup);
            plantShopTargetsToInsert.add(new Plant_Shop_Target__c(
                Target__c = plantShopTargetGroup.gwbYearId,
                Plant__c = plantShopTargetGroup.plantId,
                Year__c = parseYear(plantShopTargetGroup.yearValue),
                Month__c = plantShopTargetGroup.monthName,
                Driver__c = plantShopTargetGroup.driver,
                Classification__c = plantShopTargetGroup.plantShopTargetClassification,
                Total_Changes_Needed__c = plantShopTargetGroup.totalChangeNeeded,
                Status__c = DRAFT_STATUS
            ));
        }

        if (!plantShopTargetsToInsert.isEmpty()) {
            insert plantShopTargetsToInsert;

            for (Integer index = 0; index < plantShopTargetsToInsert.size(); index++) {
                pendingPlantShopTargetGroups[index].plantShopTargetId = plantShopTargetsToInsert[index].Id;
            }
        }

        List<Plant_Shop_Target_Item__c> itemsToInsert = new List<Plant_Shop_Target_Item__c>();
        for (PlantShopTargetGroup plantShopTargetGroup : plantShopTargetGroups) {
            if (plantShopTargetGroup.plantShopTargetId == null || plantShopTargetGroup.shopManagerViews.isEmpty()) {
                continue;
            }

            for (String shopManagerView : plantShopTargetGroup.shopManagerViews) {
                if (plantShopTargetGroup.existingShopManagerViews.contains(shopManagerView)) {
                    continue;
                }

                itemsToInsert.add(new Plant_Shop_Target_Item__c(
                    Plant_Shop_Target__c = plantShopTargetGroup.plantShopTargetId,
                    Shop_Manager_View__c = shopManagerView,
                    Adjustment__c = 0
                ));
            }
        }

        if (!itemsToInsert.isEmpty()) {
            insert itemsToInsert;
        }
    }

    private static void enqueueContinuation(List<Id> gwbYearIds, Integer yearOffset, Integer groupOffset) {
        System.enqueueJob(new CreateDraftPlantShopTargetsJob(gwbYearIds, yearOffset, groupOffset));
    }

    public class CreateDraftPlantShopTargetsJob implements Queueable {
        private List<Id> gwbYearIds;
        private Integer yearOffset;
        private Integer groupOffset;

        // Stores the full ordered year list and the group offset this queueable should continue from.
        public CreateDraftPlantShopTargetsJob(List<Id> gwbYearIds, Integer yearOffset, Integer groupOffset) {
            this.gwbYearIds = new List<Id>(gwbYearIds);
            this.yearOffset = yearOffset == null ? 0 : yearOffset;
            this.groupOffset = groupOffset == null ? 0 : groupOffset;
        }

        public void execute(QueueableContext context) {
            createDraftPlantShopTargets(gwbYearIds, yearOffset, groupOffset);
        }
    }

    // Loads GWB Years with plant data needed to build Plant Shop Target groups.
    private static Map<Id, GWB_Year__c> getGwbYearsById(Set<Id> gwbYearIds) {
        Map<Id, GWB_Year__c> gwbYearsById = new Map<Id, GWB_Year__c>();
        for (GWB_Year__c gwbYear : [
            SELECT Id, Plant__c, Type__c
            FROM GWB_Year__c
            WHERE Id IN :gwbYearIds
            AND Plant__c != null
        ]) {
            gwbYearsById.put(gwbYear.Id, gwbYear);
        }
        return gwbYearsById;
    }

    // Builds one Plant Shop Target group for each non-zero monthly driver/classification value.
    private static Map<String, PlantShopTargetGroup> buildPlantShopTargetGroups(Set<Id> gwbYearIds, Map<Id, GWB_Year__c> gwbYearsById) {
        Map<String, PlantShopTargetGroup> plantShopTargetGroupsByKey = new Map<String, PlantShopTargetGroup>();
        for (GWB_Month__c monthRecord : [
            SELECT Id, GWB_Year__c, Year__c, Driver__c, Classification__c,
                Jan_Number__c, Jan_Decimal__c, Jan_Percent__c,
                Feb_Number__c, Feb_Decimal__c, Feb_Percent__c,
                Mar_Number__c, Mar_Decimal__c, Mar_Percent__c,
                Apr_Number__c, Apr_Decimal__c, Apr_Percent__c,
                May_Number__c, May_Decimal__c, May_Percent__c,
                Jun_Number__c, Jun_Decimal__c, Jun_Percent__c,
                Jul_Number__c, Jul_Decimal__c, Jul_Percent__c,
                Aug_Number__c, Aug_Decimal__c, Aug_Percent__c,
                Sep_Number__c, Sep_Decimal__c, Sep_Percent__c,
                Oct_Number__c, Oct_Decimal__c, Oct_Percent__c,
                Nov_Number__c, Nov_Decimal__c, Nov_Percent__c,
                Dec_Number__c, Dec_Decimal__c, Dec_Percent__c
            FROM GWB_Month__c
            WHERE GWB_Year__c IN :gwbYearIds
            AND Driver__c != null
            AND Classification__c != null
        ]) {
            for (MonthField monthField : GWB_MONTH_VALUE_FIELDS) {
                Decimal value = (Decimal)monthRecord.get(monthField.fieldName);
                if (value == null || value == 0) {
                    continue;
                }

                String targetClassification =
                    normalizePlantFunctionClassificationForTarget(monthRecord.Classification__c);
                if (String.isBlank(targetClassification)) {
                    continue;
                }

                String key = getPlantShopTargetGroupKey(
                    monthRecord.GWB_Year__c,
                    monthField.monthName,
                    monthRecord.Year__c,
                    monthRecord.Driver__c,
                    targetClassification
                );
                if (!plantShopTargetGroupsByKey.containsKey(key)) {
                    GWB_Year__c gwbYear = gwbYearsById.get(monthRecord.GWB_Year__c);
                    if (gwbYear == null) {
                        continue;
                    }

                    plantShopTargetGroupsByKey.put(key, new PlantShopTargetGroup(
                        monthRecord.GWB_Year__c,
                        gwbYear.Plant__c,
                        gwbYear.Type__c,
                        monthRecord.Year__c,
                        monthField.monthName,
                        monthRecord.Driver__c,
                        targetClassification
                    ));
                    plantShopTargetGroupsByKey.get(key).totalChangeNeeded = value;
                }
            }
        }

        return plantShopTargetGroupsByKey;
    }

    // Adds matching active Plant Function Shop Manager Views to each Plant Shop Target group.
    private static void addShopManagerViews(Map<String, PlantShopTargetGroup> plantShopTargetGroupsByKey) {
        Map<String, List<PlantShopTargetGroup>> plantShopTargetGroupsByMatchKey = new Map<String, List<PlantShopTargetGroup>>();
        Set<String> classificationQueryValues = new Set<String>();
        Set<String> typeValues = new Set<String>();
        Set<Id> plantIds = new Set<Id>();

        for (PlantShopTargetGroup plantShopTargetGroup : plantShopTargetGroupsByKey.values()) {
            String matchKey = getPlantFunctionMatchKey(
                plantShopTargetGroup.plantId,
                plantShopTargetGroup.typeValue,
                plantShopTargetGroup.plantShopTargetClassification
            );
            if (!plantShopTargetGroupsByMatchKey.containsKey(matchKey)) {
                plantShopTargetGroupsByMatchKey.put(matchKey, new List<PlantShopTargetGroup>());
            }
            plantShopTargetGroupsByMatchKey.get(matchKey).add(plantShopTargetGroup);
            classificationQueryValues.addAll(getPlantFunctionClassificationQueryValues(
                plantShopTargetGroup.plantShopTargetClassification
            ));
            if (!String.isBlank(plantShopTargetGroup.typeValue)) {
                typeValues.add(plantShopTargetGroup.typeValue);
            }
            plantIds.add(plantShopTargetGroup.plantId);
        }

        if (classificationQueryValues.isEmpty() || typeValues.isEmpty() || plantIds.isEmpty()) {
            return;
        }

        for (Plant_Function__c plantFunction : [
            SELECT Id, Classification__c, Base_SUPP__c, Status__c, Shop_Manager_View__c, Plant__c
            FROM Plant_Function__c
            WHERE Status__c = :ACTIVE_PLANT_FUNCTION_STATUS
            AND Classification__c IN :classificationQueryValues
            AND Base_SUPP__c IN :typeValues
            AND Plant__c IN :plantIds
            AND Shop_Manager_View__c != null
        ]) {
            if (String.isBlank(plantFunction.Shop_Manager_View__c)) {
                continue;
            }

            String plantShopTargetGroupLookupKey = getPlantFunctionMatchKey(
                plantFunction.Plant__c,
                plantFunction.Base_SUPP__c,
                normalizePlantFunctionClassificationForTarget(plantFunction.Classification__c)
            );
            if (plantShopTargetGroupsByMatchKey.containsKey(plantShopTargetGroupLookupKey)) {
                for (PlantShopTargetGroup plantShopTargetGroup : plantShopTargetGroupsByMatchKey.get(plantShopTargetGroupLookupKey)) {
                    plantShopTargetGroup.shopManagerViews.add(plantFunction.Shop_Manager_View__c);
                }
            }
        }
    }

    // Links groups to existing draft Plant Shop Targets and tracks already-created child items.
    private static void overlayExistingDraftPlantShopTargets(
        Set<Id> gwbYearIds,
        Map<String, PlantShopTargetGroup> plantShopTargetGroupsByKey
    ) {
        if (plantShopTargetGroupsByKey.isEmpty()) {
            return;
        }

        Map<Id, PlantShopTargetGroup> plantShopTargetGroupByPlantShopTargetId = new Map<Id, PlantShopTargetGroup>();
        for (Plant_Shop_Target__c plantShopTargetRecord : [
            SELECT Id, Target__c, Year__c, Month__c, Driver__c, Classification__c, Status__c
            FROM Plant_Shop_Target__c
            WHERE Target__c IN :gwbYearIds
            AND Status__c = :DRAFT_STATUS
        ]) {
            String key = getPlantShopTargetGroupKey(
                plantShopTargetRecord.Target__c,
                String.valueOf(plantShopTargetRecord.Month__c),
                plantShopTargetRecord.Year__c == null ? null : String.valueOf(plantShopTargetRecord.Year__c.intValue()),
                plantShopTargetRecord.Driver__c,
                plantShopTargetRecord.Classification__c
            );
            if (plantShopTargetGroupsByKey.containsKey(key)) {
                plantShopTargetGroupsByKey.get(key).plantShopTargetId = plantShopTargetRecord.Id;
                plantShopTargetGroupByPlantShopTargetId.put(
                    plantShopTargetRecord.Id,
                    plantShopTargetGroupsByKey.get(key)
                );
            }
        }

        if (plantShopTargetGroupByPlantShopTargetId.isEmpty()) {
            return;
        }

        for (Plant_Shop_Target_Item__c itemRecord : [
            SELECT Id, Plant_Shop_Target__c, Shop_Manager_View__c
            FROM Plant_Shop_Target_Item__c
            WHERE Plant_Shop_Target__c IN :plantShopTargetGroupByPlantShopTargetId.keySet()
        ]) {
            PlantShopTargetGroup plantShopTargetGroup =
                plantShopTargetGroupByPlantShopTargetId.get(itemRecord.Plant_Shop_Target__c);
            plantShopTargetGroup.existingShopManagerViews.add(itemRecord.Shop_Manager_View__c);
        }
    }

    // Creates the unique grouping key for matching GWB monthly values to draft Plant Shop Targets.
    private static String getPlantShopTargetGroupKey(
        Id gwbYearId,
        String monthName,
        String yearValue,
        String driver,
        String classification
    ) {
        return String.join(new List<String>{
            String.valueOf(gwbYearId),
            normalizeKey(monthName),
            normalizeKey(yearValue),
            normalizeKey(driver),
            normalizeKey(classification)
        }, ':');
    }

    // Creates the lookup key used to match Plant Functions to Plant Shop Target groups.
    private static String getPlantFunctionMatchKey(Id plantId, String typeValue, String plantShopTargetClassification) {
        return String.join(new List<String>{
            String.valueOf(plantId),
            normalizeKey(typeValue),
            normalizeKey(plantShopTargetClassification)
        }, ':');
    }

    // Normalizes values before they are used in composite map keys.
    private static String normalizeKey(String value) {
        return String.isBlank(value) ? '' : value.trim();
    }

    // Returns the Plant Function classification values that match the Plant Shop Target classification group.
    private static Set<String> getPlantFunctionClassificationQueryValues(String classification) {
        return ClassificationDecoder.getClassificationsForGroup(classification);
    }

    // Converts Plant Function classifications to the matching Plant Shop Target classification group.
    private static String normalizePlantFunctionClassificationForTarget(String classification) {
        return ClassificationDecoder.toClassificationGroup(classification);
    }

    // Converts the source year string to a Decimal for the Plant Shop Target record.
    private static Decimal parseYear(String yearValue) {
        if (String.isBlank(yearValue)) {
            return null;
        }

        try {
            return Decimal.valueOf(yearValue);
        } catch (Exception ex) {
            return null;
        }
    }

    private class MonthField {
        String fieldName;
        String monthName;

        // Pairs a GWB Month value field API name with its calendar month name.
        MonthField(String fieldName, String monthName) {
            this.fieldName = fieldName;
            this.monthName = monthName;
        }
    }

    private class PlantShopTargetGroup {
        Id gwbYearId;
        Id plantId;
        Id plantShopTargetId;
        String typeValue;
        String yearValue;
        String monthName;
        String driver;
        String plantShopTargetClassification;
        Decimal totalChangeNeeded = 0;
        Set<String> shopManagerViews = new Set<String>();
        Set<String> existingShopManagerViews = new Set<String>();

        // Captures the identifying data shared by a parent target and its child view items.
        PlantShopTargetGroup(
            Id gwbYearId,
            Id plantId,
            String typeValue,
            String yearValue,
            String monthName,
            String driver,
            String plantShopTargetClassification
        ) {
            this.gwbYearId = gwbYearId;
            this.plantId = plantId;
            this.typeValue = typeValue;
            this.yearValue = yearValue;
            this.monthName = monthName;
            this.driver = driver;
            this.plantShopTargetClassification = plantShopTargetClassification;
        }
    }
}