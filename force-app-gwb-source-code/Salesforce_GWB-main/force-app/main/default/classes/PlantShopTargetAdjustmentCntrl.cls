public with sharing class PlantShopTargetAdjustmentCntrl {
    private static final String ALL_OPTION = 'All';
    private static final String ACTIVE_PLANT_FUNCTION_STATUS = 'Active';
    private static final String DRAFT_STATUS = 'Draft';
    private static final String FINALIZED_STATUS = 'Finalized';
    private static final String LOCKED_STATUS = 'Locked';
    private static final String WORKBOOK_TARGET_RECORD_TYPE = 'Targets';
    private static final String CONSOLIDATOR_NEGATIVE_TOTAL_VALIDATION_MESSAGE =
        'Total fields cannot be negative. Please enter a value of 0 or greater for all monthly totals.';
    private static final Map<String, String> WORKBOOK_TO_CONSOLIDATOR_RECORD_TYPES = new Map<String, String>{
        'Targets' => 'Target',
        'Actuals' => 'Actual',
        'Forecast' => 'Forecast'
    };
    private static final List<String> CALENDAR_MONTHS = new List<String>{
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December'
    };
    private static final List<String> CLASSIFICATION_ORDER = new List<String>{ 'OTS', 'Skilled', 'Salaried' };
    private static final Map<String, List<String>> MONTH_CREW_FIELDS = new Map<String, List<String>>{
        'January' => new List<String>{ 'Jan_1st__c', 'Jan_2nd__c', 'Jan_3rd__c' },
        'February' => new List<String>{ 'Feb_1st__c', 'Feb_2nd__c', 'Feb_3rd__c' },
        'March' => new List<String>{ 'Mar_1st__c', 'Mar_2nd__c', 'Mar_3rd__c' },
        'April' => new List<String>{ 'Apr_1st__c', 'Apr_2nd__c', 'Apr_3rd__c' },
        'May' => new List<String>{ 'May_1st__c', 'May_2nd__c', 'May_3rd__c' },
        'June' => new List<String>{ 'Jun_1st__c', 'Jun_2nd__c', 'Jun_3rd__c' },
        'July' => new List<String>{ 'Jul_1st__c', 'Jul_2nd__c', 'Jul_3rd__c' },
        'August' => new List<String>{ 'Aug_1st__c', 'Aug_2nd__c', 'Aug_3rd__c' },
        'September' => new List<String>{ 'Sep_1st__c', 'Sep_2nd__c', 'Sep_3rd__c' },
        'October' => new List<String>{ 'Oct_1st__c', 'Oct_2nd__c', 'Oct_3rd__c' },
        'November' => new List<String>{ 'Nov_1st__c', 'Nov_2nd__c', 'Nov_3rd__c' },
        'December' => new List<String>{ 'Dec_1st__c', 'Dec_2nd__c', 'Dec_3rd__c' }
    };

    // Loads Plant Shop Target adjustments and nested shop items for the given GWB Year.
    @AuraEnabled(cacheable=false)
    public static AdjustmentPayload getPlantShopTargetAdjustments(Id gwbYearId) {
        if (gwbYearId == null) {
            throw new AuraHandledException('GWB Year Id is required.');
        }

        return buildPlantShopTargetAdjustmentPayload(gwbYearId);
    }

    // Returns whether the current user can edit plant position adjustments.
    @AuraEnabled(cacheable=true)
    public static AdjustmentAccessResult getAdjustmentAccess() {
        AdjustmentAccessResult result = new AdjustmentAccessResult();
        result.hasAdjustmentEditPermission =
            FeatureManagement.checkPermission('Plant_Admin') ||
            FeatureManagement.checkPermission('GWB_System_Admin');
        return result;
    }

    // Builds the adjustment payload, including saved plant function target values from GWB Functions.
    private static AdjustmentPayload buildPlantShopTargetAdjustmentPayload(Id gwbYearId) {

        AdjustmentPayload payload = new AdjustmentPayload();
        payload.gwbYearId = gwbYearId;
        payload.plantPositionAdjustments = new List<PlantPositionAdjustment>();

        List<Plant_Shop_Target__c> plantShopTargets = [
            SELECT Id, Year__c, Month__c, Driver__c, Classification__c,
                   Total_Changes_Needed__c, Total_Changes_Made__c
            FROM Plant_Shop_Target__c
            WHERE Target__c = :gwbYearId
            ORDER BY Year__c, Month__c, Driver__c, Classification__c
        ];

        Map<Id, List<Plant_Shop_Target_Item__c>> itemsByPlantShopTargetId =
            getItemsByPlantShopTargetId(new Map<Id, Plant_Shop_Target__c>(plantShopTargets).keySet());
        TargetPlantFunctionScope plantFunctionScope = buildTargetPlantFunctionScope(
            plantShopTargets,
            itemsByPlantShopTargetId
        );
        Map<String, List<GWBFunctionAdjustment>> gwbFunctionAdjustmentsByPlantShopKey =
            getGwbFunctionAdjustmentsByPlantShopKey(gwbYearId, plantFunctionScope);

        for (Plant_Shop_Target__c plantShopTarget : plantShopTargets) {
            PlantPositionAdjustment adjustment = toPlantPositionAdjustment(plantShopTarget);
            if (adjustment == null) {
                continue;
            }
            adjustment.plantShops = new List<PlantShopAdjustment>();

            List<Plant_Shop_Target_Item__c> plantShopTargetItems = itemsByPlantShopTargetId.get(plantShopTarget.Id);
            if (plantShopTargetItems != null) {
                for (Plant_Shop_Target_Item__c item : plantShopTargetItems) {
                    PlantShopAdjustment plantShop = toPlantShopAdjustment(item, adjustment);
                    String plantShopPayloadKey = getPlantShopPayloadKey(adjustment, plantShop.shopManagerView);
                    if (gwbFunctionAdjustmentsByPlantShopKey.containsKey(plantShopPayloadKey)) {
                        plantShop.plantFunctions.addAll(gwbFunctionAdjustmentsByPlantShopKey.get(plantShopPayloadKey));
                    }
                    adjustment.plantShops.add(plantShop);
                }
            }

            payload.plantPositionAdjustments.add(adjustment);
        }

        return payload;
    }

    // Builds filter options from existing draft Plant Shop Targets for the given GWB Year.
    @AuraEnabled(cacheable=false)
    public static GlobalFilters getGlobalFilters(Id gwbYearId) {
        if (gwbYearId == null) {
            throw new AuraHandledException('GWB Year Id is required.');
        }

        return buildGlobalFilters(gwbYearId);
    }

    // Builds month, classification, and driver options from draft Plant Shop Targets.
    private static GlobalFilters buildGlobalFilters(Id gwbYearId) {
        Set<String> monthsWithTargets = new Set<String>();
        Map<String, Set<String>> classificationsByMonth = new Map<String, Set<String>>();
        Set<String> allClassifications = new Set<String>();
        Map<String, Set<String>> driversByClassification = new Map<String, Set<String>>();

        for (Plant_Shop_Target__c plantShopTarget : [
            SELECT Month__c, Classification__c, Driver__c
            FROM Plant_Shop_Target__c
            WHERE Target__c = :gwbYearId
            AND Status__c = :DRAFT_STATUS
        ]) {
            String monthValue = plantShopTarget.Month__c;
            String classificationValue = toPlantShopTargetClassification(plantShopTarget.Classification__c);
            String driverValue = plantShopTarget.Driver__c;

            if (String.isBlank(monthValue) || String.isBlank(classificationValue)) {
                continue;
            }

            monthsWithTargets.add(monthValue);
            allClassifications.add(classificationValue);

            if (!classificationsByMonth.containsKey(monthValue)) {
                classificationsByMonth.put(monthValue, new Set<String>());
            }
            classificationsByMonth.get(monthValue).add(classificationValue);

            if (!String.isBlank(driverValue)) {
                if (!driversByClassification.containsKey(classificationValue)) {
                    driversByClassification.put(classificationValue, new Set<String>());
                }
                driversByClassification.get(classificationValue).add(driverValue.trim());
            }
        }

        GlobalFilters filters = new GlobalFilters();
        filters.months = new List<String>{ ALL_OPTION };
        filters.classificationByMonth = new Map<String, List<String>>();
        filters.classificationByMonth.put(ALL_OPTION, buildOrderedOptions(allClassifications, CLASSIFICATION_ORDER));
        filters.driverByClassification = new Map<String, List<String>>();

        for (String monthValue : CALENDAR_MONTHS) {
            if (!monthsWithTargets.contains(monthValue)) {
                continue;
            }
            filters.months.add(monthValue);
            filters.classificationByMonth.put(
                monthValue,
                buildOrderedOptions(classificationsByMonth.get(monthValue), CLASSIFICATION_ORDER)
            );
        }

        for (String classificationValue : buildOrderedValues(allClassifications, CLASSIFICATION_ORDER)) {
            filters.driverByClassification.put(
                classificationValue,
                buildOrderedOptions(driversByClassification.get(classificationValue), null)
            );
        }

        return filters;
    }

    // Loads active Plant Functions for the GWB Year plant and requested target filters.
    @AuraEnabled(cacheable=false)
    public static List<PlantFunction> getTargetPlantFunctionList(
        Id gwbYearId,
        String shopManagerView,
        String classification
    ) {
        if (gwbYearId == null) {
            throw new AuraHandledException('GWB Year Id is required.');
        }

        List<PlantFunction> plantFunctions = new List<PlantFunction>();
        GWB_Year__c gwbYear = [
            SELECT Id, Plant__c, Type__c
            FROM GWB_Year__c
            WHERE Id = :gwbYearId
            LIMIT 1
        ];

        if (gwbYear.Plant__c == null) {
            return plantFunctions;
        }

        Set<String> classificationQueryValues = ClassificationDecoder.getClassificationsForGroup(classification);
        if (classificationQueryValues.isEmpty() && !String.isBlank(classification)) {
            classificationQueryValues.add(classification.trim());
        }

        if (
            String.isBlank(shopManagerView) ||
            classificationQueryValues.isEmpty() ||
            String.isBlank(gwbYear.Type__c)
        ) {
            return plantFunctions;
        }

        for (Plant_Function__c plantFunctionRecord : [
            SELECT Id, Name, Function__c, Function__r.Name, Function_Name__c, Plant_Program__c, Plant_Program__r.Name,
                   Program_Code__c, Function_Level__c, Functional_Area__c, Module__c
            FROM Plant_Function__c
            WHERE Status__c = :ACTIVE_PLANT_FUNCTION_STATUS
            AND Plant__c = :gwbYear.Plant__c
            AND Shop_Manager_View__c = :shopManagerView
            AND Classification__c IN :classificationQueryValues
            AND Base_SUPP__c = :gwbYear.Type__c
            ORDER BY Function__r.Name, Plant_Program__r.Name
        ]) {
            plantFunctions.add(toPlantFunction(plantFunctionRecord));
        }

        return plantFunctions;
    }

    // Finalizes Plant Shop Targets and locks the parent GWB Year.
    @AuraEnabled(cacheable=false)
    public static SaveResult finalizeTarget(Id gwbYearId) {
        SaveResult result = new SaveResult();
        result.success = false;

        try {
            if (gwbYearId == null) {
                throw new AuraHandledException('GWB Year Id is required.');
            }

            GWB_Year__c gwbYear = [
                SELECT Id
                FROM GWB_Year__c
                WHERE Id = :gwbYearId
                LIMIT 1
            ];

            List<Plant_Shop_Target__c> plantShopTargets = [
                SELECT Id
                FROM Plant_Shop_Target__c
                WHERE Target__c = :gwbYearId
            ];

            for (Plant_Shop_Target__c plantShopTarget : plantShopTargets) {
                plantShopTarget.Status__c = FINALIZED_STATUS;
            }

            if (!plantShopTargets.isEmpty()) {
                update plantShopTargets;
            }

            gwbYear.Status__c = LOCKED_STATUS;
            update gwbYear;

            result.success = true;
            result.message = 'Plant Shop Targets finalized and GWB Year locked successfully.';
            result.plantPositionAdjustmentCount = plantShopTargets.size();
            result.plantShopCount = 0;
            return result;
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Error finalizing Plant Shop Targets: ' + ex.getMessage());
        }
    }

    // Saves Plant Shop Target adjustments and nested plant function target values.
    @AuraEnabled(cacheable=false)
    public static SaveResult updatePlantShopTargetAdjustments(AdjustmentPayload payload) {
        SaveResult result = new SaveResult();
        result.success = false;

        try {
            if (payload == null || payload.plantPositionAdjustments == null) {
                throw new AuraHandledException('No Plant Shop Target adjustments were provided.');
            }

            Id gwbYearId = payload.gwbYearId;
            if (gwbYearId == null) {
                throw new AuraHandledException('GWB Year Id is required.');
            }

            GWB_Year__c gwbYear = [
                SELECT Id, Plant__c, Year__c, Type__c
                FROM GWB_Year__c
                WHERE Id = :gwbYearId
                LIMIT 1
            ];

            List<Plant_Shop_Target__c> existingPlantShopTargets = [
                SELECT Id, Target__c, Plant__c, Year__c, Month__c, Driver__c, Classification__c,
                       Total_Changes_Needed__c, Status__c
                FROM Plant_Shop_Target__c
                WHERE Target__c = :gwbYearId
            ];

            Map<Id, Plant_Shop_Target__c> plantShopTargetsById =
                new Map<Id, Plant_Shop_Target__c>(existingPlantShopTargets);
            Map<String, Plant_Shop_Target__c> plantShopTargetsByCompositeKey = new Map<String, Plant_Shop_Target__c>();
            for (Plant_Shop_Target__c plantShopTarget : existingPlantShopTargets) {
                if (String.isBlank(toPlantShopTargetClassification(plantShopTarget.Classification__c))) {
                    continue;
                }
                plantShopTargetsByCompositeKey.put(getPlantShopTargetCompositeKey(plantShopTarget), plantShopTarget);
            }

            Map<String, Plant_Shop_Target__c> plantShopTargetRecordsByPayloadKey = new Map<String, Plant_Shop_Target__c>();
            List<Plant_Shop_Target__c> plantShopTargetsToUpsert = new List<Plant_Shop_Target__c>();
            Set<String> plantShopTargetUpsertKeys = new Set<String>();

            for (PlantPositionAdjustment adjustment : payload.plantPositionAdjustments) {
                if (adjustment == null) {
                    continue;
                }

                if (String.isBlank(toPlantShopTargetClassification(adjustment.classification))) {
                    continue;
                }

                Plant_Shop_Target__c plantShopTargetRecord = resolvePlantShopTargetRecord(
                    adjustment,
                    gwbYearId,
                    gwbYear.Plant__c,
                    plantShopTargetsById,
                    plantShopTargetsByCompositeKey
                );

                applyPlantShopTargetValues(plantShopTargetRecord, adjustment);
                String payloadKey = getPayloadKey(adjustment);
                plantShopTargetRecordsByPayloadKey.put(payloadKey, plantShopTargetRecord);

                if (plantShopTargetUpsertKeys.add(payloadKey)) {
                    plantShopTargetsToUpsert.add(plantShopTargetRecord);
                }

                if (plantShopTargetRecord.Id == null) {
                    plantShopTargetsByCompositeKey.put(
                        getPlantShopTargetCompositeKey(plantShopTargetRecord),
                        plantShopTargetRecord
                    );
                }
            }

            if (!plantShopTargetsToUpsert.isEmpty()) {
                if (gwbYear.Plant__c == null) {
                    for (Plant_Shop_Target__c plantShopTargetRecord : plantShopTargetsToUpsert) {
                        if (plantShopTargetRecord.Id == null) {
                            throw new AuraHandledException('The GWB Year must have a Plant before new Plant Shop Targets can be created.');
                        }
                    }
                }
                upsert plantShopTargetsToUpsert;
            }

            Set<Id> plantShopTargetIds = new Set<Id>();
            for (Plant_Shop_Target__c plantShopTargetRecord : plantShopTargetRecordsByPayloadKey.values()) {
                if (plantShopTargetRecord.Id != null) {
                    plantShopTargetIds.add(plantShopTargetRecord.Id);
                }
            }

            Map<Id, Plant_Shop_Target_Item__c> itemsById = new Map<Id, Plant_Shop_Target_Item__c>();
            Map<String, Plant_Shop_Target_Item__c> itemsByPlantShopTargetAndShop = new Map<String, Plant_Shop_Target_Item__c>();
            for (Plant_Shop_Target_Item__c item : [
                SELECT Id, Plant_Shop_Target__c, Shop_Manager_View__c, Adjustment__c
                FROM Plant_Shop_Target_Item__c
                WHERE Plant_Shop_Target__c IN :plantShopTargetIds
            ]) {
                itemsById.put(item.Id, item);
                itemsByPlantShopTargetAndShop.put(
                    getItemCompositeKey(item.Plant_Shop_Target__c, item.Shop_Manager_View__c),
                    item
                );
            }

            List<Plant_Shop_Target_Item__c> itemsToUpsert = new List<Plant_Shop_Target_Item__c>();
            Set<String> itemUpsertKeys = new Set<String>();

            for (PlantPositionAdjustment adjustment : payload.plantPositionAdjustments) {
                if (adjustment == null || adjustment.plantShops == null) {
                    continue;
                }

                Plant_Shop_Target__c parentPlantShopTarget = plantShopTargetRecordsByPayloadKey.get(getPayloadKey(adjustment));
                if (parentPlantShopTarget == null || parentPlantShopTarget.Id == null) {
                    continue;
                }

                for (PlantShopAdjustment plantShop : adjustment.plantShops) {
                    if (plantShop == null) {
                        continue;
                    }

                    Plant_Shop_Target_Item__c itemRecord = resolveItemRecord(
                        plantShop,
                        parentPlantShopTarget.Id,
                        itemsById,
                        itemsByPlantShopTargetAndShop
                    );
                    if (itemRecord.Id == null) {
                        itemRecord.Plant_Shop_Target__c = parentPlantShopTarget.Id;
                    }
                    itemRecord.Shop_Manager_View__c = plantShop.shopManagerView;
                    itemRecord.Adjustment__c = plantShop.adjustment;

                    String itemUpsertKey = itemRecord.Id == null
                        ? getItemCompositeKey(parentPlantShopTarget.Id, plantShop.shopManagerView)
                        : String.valueOf(itemRecord.Id);
                    if (itemUpsertKeys.add(itemUpsertKey)) {
                        itemsToUpsert.add(itemRecord);
                    }

                    if (itemRecord.Id == null) {
                        itemsByPlantShopTargetAndShop.put(
                            getItemCompositeKey(itemRecord.Plant_Shop_Target__c, itemRecord.Shop_Manager_View__c),
                            itemRecord
                        );
                    }
                }
            }

            if (!itemsToUpsert.isEmpty()) {
                upsert itemsToUpsert;
            }

            List<Workbook__c> gwbFunctionsToUpsert = saveGwbFunctionTargets(gwbYear, payload);
            validateConsolidatorTotals(gwbFunctionsToUpsert);
            if (!gwbFunctionsToUpsert.isEmpty()) {
                upsert gwbFunctionsToUpsert;
            }

            result.success = true;
            result.message = 'Plant Shop Target adjustments saved successfully.';
            result.plantPositionAdjustmentCount = plantShopTargetsToUpsert.size();
            result.plantShopCount = itemsToUpsert.size();
            return result;
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Error saving Plant Shop Target adjustments: ' + ex.getMessage());
        }
    }

    // Finds an existing Plant Shop Target or prepares a new one from the adjustment payload.
    private static Plant_Shop_Target__c resolvePlantShopTargetRecord(
        PlantPositionAdjustment adjustment,
        Id gwbYearId,
        Id plantId,
        Map<Id, Plant_Shop_Target__c> plantShopTargetsById,
        Map<String, Plant_Shop_Target__c> plantShopTargetsByCompositeKey
    ) {
        Id adjustmentId = parseOptionalId(adjustment.adjustmentId, 'adjustmentId');
        if (adjustmentId != null) {
            if (!plantShopTargetsById.containsKey(adjustmentId)) {
                throw new AuraHandledException('Plant Shop Target does not belong to the provided GWB Year: ' + adjustmentId);
            }
            return plantShopTargetsById.get(adjustmentId);
        }

        Plant_Shop_Target__c lookupRecord = new Plant_Shop_Target__c(
            Target__c = gwbYearId,
            Year__c = parseYear(adjustment.year),
            Month__c = adjustment.month,
            Driver__c = adjustment.driver,
            Classification__c = toPlantShopTargetClassification(adjustment.classification)
        );
        String compositeKey = getPlantShopTargetCompositeKey(lookupRecord);
        if (plantShopTargetsByCompositeKey.containsKey(compositeKey)) {
            return plantShopTargetsByCompositeKey.get(compositeKey);
        }

        lookupRecord.Plant__c = plantId;
        lookupRecord.Status__c = DRAFT_STATUS;
        return lookupRecord;
    }

    // Finds an existing Plant Shop Target Item or prepares a new one for the shop entry.
    private static Plant_Shop_Target_Item__c resolveItemRecord(
        PlantShopAdjustment plantShop,
        Id parentPlantShopTargetId,
        Map<Id, Plant_Shop_Target_Item__c> itemsById,
        Map<String, Plant_Shop_Target_Item__c> itemsByPlantShopTargetAndShop
    ) {
        Id itemId = parseOptionalId(plantShop.adjustmentItemId, 'adjustmentItemId');
        if (itemId != null) {
            if (!itemsById.containsKey(itemId)) {
                throw new AuraHandledException('Plant Shop Target Item does not belong to the provided Plant Shop Target: ' + itemId);
            }
            Plant_Shop_Target_Item__c itemRecord = itemsById.get(itemId);
            if (itemRecord.Plant_Shop_Target__c != parentPlantShopTargetId) {
                throw new AuraHandledException('Plant Shop Target Item does not belong to the provided Plant Shop Target: ' + itemId);
            }
            return itemRecord;
        }

        String compositeKey = getItemCompositeKey(parentPlantShopTargetId, plantShop.shopManagerView);
        if (itemsByPlantShopTargetAndShop.containsKey(compositeKey)) {
            return itemsByPlantShopTargetAndShop.get(compositeKey);
        }

        return new Plant_Shop_Target_Item__c(Adjustment__c = 0);
    }

    // Copies payload values onto a Plant Shop Target record.
    private static void applyPlantShopTargetValues(
        Plant_Shop_Target__c plantShopTargetRecord,
        PlantPositionAdjustment adjustment
    ) {
        plantShopTargetRecord.Year__c = parseYear(adjustment.year);
        plantShopTargetRecord.Month__c = adjustment.month;
        plantShopTargetRecord.Driver__c = adjustment.driver;
        plantShopTargetRecord.Classification__c = toPlantShopTargetClassification(adjustment.classification);
        plantShopTargetRecord.Total_Changes_Needed__c = adjustment.totalChangesNeeded;
        if (String.isBlank(plantShopTargetRecord.Status__c)) {
            plantShopTargetRecord.Status__c = DRAFT_STATUS;
        }
    }

    // Groups nested plant function wrappers and builds one GWB Function per year/driver/classification/function.
    private static List<Workbook__c> saveGwbFunctionTargets(GWB_Year__c gwbYear, AdjustmentPayload payload) {
        Map<String, GwbFunctionTargetGroup> groupsByKey = new Map<String, GwbFunctionTargetGroup>();
        Set<Id> plantFunctionIds = new Set<Id>();
        Set<Id> gwbFunctionIds = new Set<Id>();

        for (PlantPositionAdjustment adjustment : payload.plantPositionAdjustments) {
            if (adjustment == null || adjustment.plantShops == null) {
                continue;
            }

            for (PlantShopAdjustment plantShop : adjustment.plantShops) {
                if (plantShop == null || plantShop.plantFunctions == null) {
                    continue;
                }

                for (GWBFunctionAdjustment gwbFunctionAdjustment : plantShop.plantFunctions) {
                    if (gwbFunctionAdjustment == null || String.isBlank(gwbFunctionAdjustment.plantFunctionId)) {
                        continue;
                    }

                    Decimal yearValue = gwbFunctionAdjustment.year == null
                        ? parseYear(adjustment.year)
                        : gwbFunctionAdjustment.year;
                    if (yearValue == null) {
                        yearValue = parseYear(gwbYear.Year__c);
                    }
                    if (yearValue == null) {
                        throw new AuraHandledException('A year is required for Plant Function adjustments.');
                    }

                    String monthValue = String.isBlank(gwbFunctionAdjustment.month)
                        ? adjustment.month
                        : gwbFunctionAdjustment.month;
                    if (!MONTH_CREW_FIELDS.containsKey(monthValue)) {
                        throw new AuraHandledException('Unsupported Plant Function month: ' + monthValue);
                    }

                    String driverValue = String.isBlank(gwbFunctionAdjustment.driver)
                        ? adjustment.driver
                        : gwbFunctionAdjustment.driver;
                    String classificationValue = String.isBlank(gwbFunctionAdjustment.classification)
                        ? adjustment.classification
                        : gwbFunctionAdjustment.classification;
                    String normalizedClassification = toPlantShopTargetClassification(classificationValue);
                    if (String.isBlank(driverValue) || String.isBlank(normalizedClassification)) {
                        throw new AuraHandledException('Driver and classification are required for Plant Function adjustments.');
                    }

                    Id plantFunctionId = parseId(gwbFunctionAdjustment.plantFunctionId, 'plantFunctionId');
                    Id gwbFunctionId = parseOptionalId(gwbFunctionAdjustment.gwbFunctionId, 'gwbFunctionId');
                    String groupKey = getGwbFunctionGroupKey(
                        yearValue,
                        driverValue,
                        normalizedClassification,
                        plantFunctionId
                    );

                    if (!groupsByKey.containsKey(groupKey)) {
                        groupsByKey.put(
                            groupKey,
                            new GwbFunctionTargetGroup(yearValue, driverValue, normalizedClassification, plantFunctionId)
                        );
                    }

                    groupsByKey.get(groupKey).addGwbFunctionAdjustment(monthValue, gwbFunctionAdjustment, gwbFunctionId);
                    plantFunctionIds.add(plantFunctionId);
                    if (gwbFunctionId != null) {
                        gwbFunctionIds.add(gwbFunctionId);
                    }
                }
            }
        }

        if (groupsByKey.isEmpty()) {
            return new List<Workbook__c>();
        }

        Map<Id, Plant_Function__c> plantFunctionsById = getPlantFunctionsById(plantFunctionIds);
        Map<Id, Workbook__c> existingGwbFunctionsById = getExistingGwbFunctionsById(gwbYear.Id, gwbFunctionIds);
        Id targetRecordTypeId;

        List<Workbook__c> gwbFunctionsToUpsert = new List<Workbook__c>();
        for (GwbFunctionTargetGroup targetGroup : groupsByKey.values()) {
            Workbook__c gwbFunction;
            if (targetGroup.gwbFunctionId == null) {
                gwbFunction = new Workbook__c();
            } else {
                Workbook__c existingGwbFunction = existingGwbFunctionsById.get(targetGroup.gwbFunctionId);
                gwbFunction = new Workbook__c(Id = existingGwbFunction.Id);
                gwbFunction.RecordTypeId = existingGwbFunction.RecordTypeId;

                // Carry forward untouched month crew fields so pre-save Consolidator validation
                // evaluates the same final values that upsert will persist.
                for (List<String> crewFields : MONTH_CREW_FIELDS.values()) {
                    for (String crewField : crewFields) {
                        gwbFunction.put(crewField, existingGwbFunction.get(crewField));
                    }
                }
            }

            if (gwbFunction.Id == null) {
                if (targetRecordTypeId == null) {
                    targetRecordTypeId = getWorkbookTargetRecordTypeId();
                }
                gwbFunction.RecordTypeId = targetRecordTypeId;
            }
            gwbFunction.GWB_Year__c = gwbYear.Id;
            gwbFunction.Year__c = targetGroup.yearValue;
            gwbFunction.Driver_New__c = targetGroup.driver;
            gwbFunction.Plant_Function__c = targetGroup.plantFunctionId;
            gwbFunction.Base_Supp__c = gwbYear.Type__c;
            applyPlantFunctionValues(gwbFunction, plantFunctionsById.get(targetGroup.plantFunctionId));

            for (String monthValue : targetGroup.gwbFunctionAdjustmentsByMonth.keySet()) {
                GWBFunctionAdjustment gwbFunctionAdjustment = targetGroup.gwbFunctionAdjustmentsByMonth.get(monthValue);
                List<String> crewFields = MONTH_CREW_FIELDS.get(monthValue);
                gwbFunction.put(crewFields[0], gwbFunctionAdjustment.crew1);
                gwbFunction.put(crewFields[1], gwbFunctionAdjustment.crew2);
                gwbFunction.put(crewFields[2], gwbFunctionAdjustment.crew3);
            }

            gwbFunctionsToUpsert.add(gwbFunction);
        }

        return gwbFunctionsToUpsert;
    }

    // Loads Plant Function records used to populate matching GWB Function fields.
    private static Map<Id, Plant_Function__c> getPlantFunctionsById(Set<Id> plantFunctionIds) {
        if (plantFunctionIds.isEmpty()) {
            return new Map<Id, Plant_Function__c>();
        }

        Map<Id, Plant_Function__c> plantFunctionsById = new Map<Id, Plant_Function__c>([
            SELECT Id, Plant__c, Plant_Program__c, Function__c, Function_Name__c,
                   Classification__c, Sector__c, Product_Type__c, Program_Product_Index__c,
                   Shop_Manager_View__c, Shop_Master_view__c, MFG_Sub_Function__c, Function_Level__c,
                   Functional_Area__c, Hover_Over__c
            FROM Plant_Function__c
            WHERE Id IN :plantFunctionIds
        ]);

        for (Id plantFunctionId : plantFunctionIds) {
            if (!plantFunctionsById.containsKey(plantFunctionId)) {
                throw new AuraHandledException('Plant Function does not exist: ' + plantFunctionId);
            }
        }

        return plantFunctionsById;
    }

    // Copies matching Plant Function values onto writable Workbook fields.
    private static void applyPlantFunctionValues(Workbook__c gwbFunction, Plant_Function__c plantFunction) {
        if (plantFunction == null) {
            return;
        }

        gwbFunction.Plant__c = plantFunction.Plant__c;
        gwbFunction.Classification__c = plantFunction.Classification__c;
        gwbFunction.Sector__c = plantFunction.Sector__c;
        gwbFunction.Shop_Mgr_view__c = plantFunction.Shop_Manager_View__c;
        gwbFunction.Shop_Master_view__c = plantFunction.Shop_Master_view__c;
    }

    // Loads existing GWB Functions and verifies they belong to the target GWB Year.
    private static Map<Id, Workbook__c> getExistingGwbFunctionsById(Id gwbYearId, Set<Id> gwbFunctionIds) {
        if (gwbFunctionIds.isEmpty()) {
            return new Map<Id, Workbook__c>();
        }

        Map<Id, Workbook__c> existingGwbFunctionsById = new Map<Id, Workbook__c>([
            SELECT Id, GWB_Year__c, RecordTypeId,
                   Jan_1st__c, Jan_2nd__c, Jan_3rd__c,
                   Feb_1st__c, Feb_2nd__c, Feb_3rd__c,
                   Mar_1st__c, Mar_2nd__c, Mar_3rd__c,
                   Apr_1st__c, Apr_2nd__c, Apr_3rd__c,
                   May_1st__c, May_2nd__c, May_3rd__c,
                   Jun_1st__c, Jun_2nd__c, Jun_3rd__c,
                   Jul_1st__c, Jul_2nd__c, Jul_3rd__c,
                   Aug_1st__c, Aug_2nd__c, Aug_3rd__c,
                   Sep_1st__c, Sep_2nd__c, Sep_3rd__c,
                   Oct_1st__c, Oct_2nd__c, Oct_3rd__c,
                   Nov_1st__c, Nov_2nd__c, Nov_3rd__c,
                   Dec_1st__c, Dec_2nd__c, Dec_3rd__c
            FROM Workbook__c
            WHERE Id IN :gwbFunctionIds
        ]);

        for (Id gwbFunctionId : gwbFunctionIds) {
            if (!existingGwbFunctionsById.containsKey(gwbFunctionId)) {
                throw new AuraHandledException('GWB Function does not exist: ' + gwbFunctionId);
            }
            if (existingGwbFunctionsById.get(gwbFunctionId).GWB_Year__c != gwbYearId) {
                throw new AuraHandledException('GWB Function does not belong to the provided GWB Year: ' + gwbFunctionId);
            }
        }

        return existingGwbFunctionsById;
    }

    // Validates that projected Consolidator running totals remain non-negative before Workbook DML.
    private static void validateConsolidatorTotals(List<Workbook__c> pendingWorkbookRows) {
        if (pendingWorkbookRows == null || pendingWorkbookRows.isEmpty()) {
            return;
        }

        Set<Id> plantFunctionIds = new Set<Id>();
        Set<Id> plantIds = new Set<Id>();
        Set<Decimal> years = new Set<Decimal>();
        Set<String> classifications = new Set<String>();
        Set<String> shopManagerViews = new Set<String>();
        Set<String> baseSuppValues = new Set<String>();
        Set<Id> workbookRecordTypeIds = new Set<Id>();
        Set<Id> pendingUpdateIds = new Set<Id>();
        Map<Id, Workbook__c> pendingById = new Map<Id, Workbook__c>();
        List<Workbook__c> pendingWithoutId = new List<Workbook__c>();

        for (Workbook__c workbook : pendingWorkbookRows) {
            if (
                workbook == null ||
                workbook.Plant_Function__c == null ||
                workbook.Plant__c == null ||
                workbook.Year__c == null ||
                String.isBlank(workbook.Classification__c) ||
                String.isBlank(workbook.Shop_Mgr_view__c) ||
                String.isBlank(workbook.Base_Supp__c) ||
                workbook.RecordTypeId == null
            ) {
                continue;
            }
            plantFunctionIds.add(workbook.Plant_Function__c);
            plantIds.add(workbook.Plant__c);
            years.add(workbook.Year__c);
            classifications.add(workbook.Classification__c);
            shopManagerViews.add(workbook.Shop_Mgr_view__c);
            baseSuppValues.add(workbook.Base_Supp__c);
            workbookRecordTypeIds.add(workbook.RecordTypeId);

            if (workbook.Id != null) {
                pendingUpdateIds.add(workbook.Id);
                pendingById.put(workbook.Id, workbook);
            } else {
                pendingWithoutId.add(workbook);
            }
        }

        if (
            plantFunctionIds.isEmpty() ||
            plantIds.isEmpty() ||
            years.isEmpty() ||
            classifications.isEmpty() ||
            shopManagerViews.isEmpty() ||
            baseSuppValues.isEmpty() ||
            workbookRecordTypeIds.isEmpty()
        ) {
            return;
        }

        Map<Id, Id> workbookToConsolidatorRecordTypeIds =
            getConsolidatorRecordTypeByWorkbookRecordType(workbookRecordTypeIds);
        if (workbookToConsolidatorRecordTypeIds.isEmpty()) {
            return;
        }

        Map<String, ConsolidatorTotals> totalsByGroupKey = new Map<String, ConsolidatorTotals>();
        Set<Id> consolidatorRecordTypeIds = new Set<Id>();
        Set<Decimal> priorYears = new Set<Decimal>();
        for (Decimal yearValue : years) {
            if (yearValue != null) {
                priorYears.add(yearValue - 1);
            }
        }

        for (Workbook__c workbook : [
            SELECT Id, Plant_Function__c, Plant__c, Year__c, Classification__c, Shop_Mgr_view__c,
                   Base_Supp__c, Exclude_From_GWB__c, RecordTypeId,
                   Jan_1st__c, Jan_2nd__c, Jan_3rd__c,
                   Feb_1st__c, Feb_2nd__c, Feb_3rd__c,
                   Mar_1st__c, Mar_2nd__c, Mar_3rd__c,
                   Apr_1st__c, Apr_2nd__c, Apr_3rd__c,
                   May_1st__c, May_2nd__c, May_3rd__c,
                   Jun_1st__c, Jun_2nd__c, Jun_3rd__c,
                   Jul_1st__c, Jul_2nd__c, Jul_3rd__c,
                   Aug_1st__c, Aug_2nd__c, Aug_3rd__c,
                   Sep_1st__c, Sep_2nd__c, Sep_3rd__c,
                   Oct_1st__c, Oct_2nd__c, Oct_3rd__c,
                   Nov_1st__c, Nov_2nd__c, Nov_3rd__c,
                   Dec_1st__c, Dec_2nd__c, Dec_3rd__c
            FROM Workbook__c
            WHERE Plant_Function__c IN :plantFunctionIds
              AND Plant__c IN :plantIds
              AND Year__c IN :years
              AND Classification__c IN :classifications
              AND Shop_Mgr_view__c IN :shopManagerViews
              AND Base_Supp__c IN :baseSuppValues
              AND RecordTypeId IN :workbookRecordTypeIds
        ]) {
            if (pendingUpdateIds.contains(workbook.Id)) {
                continue;
            }
            addWorkbookToConsolidatorTotals(workbook, workbookToConsolidatorRecordTypeIds, totalsByGroupKey, consolidatorRecordTypeIds);
        }

        for (Workbook__c workbook : pendingById.values()) {
            addWorkbookToConsolidatorTotals(workbook, workbookToConsolidatorRecordTypeIds, totalsByGroupKey, consolidatorRecordTypeIds);
        }
        for (Workbook__c workbook : pendingWithoutId) {
            addWorkbookToConsolidatorTotals(workbook, workbookToConsolidatorRecordTypeIds, totalsByGroupKey, consolidatorRecordTypeIds);
        }

        if (totalsByGroupKey.isEmpty()) {
            return;
        }

        Map<String, Decimal> priorDecemberByGroup = new Map<String, Decimal>();
        if (!priorYears.isEmpty() && !consolidatorRecordTypeIds.isEmpty()) {
            for (GWB_Consolidator__c previousConsolidator : [
                SELECT Plant_Function__c, Plant__c, Year__c, Classification__c, Shop_Manager_View__c,
                       Base_Supp__c, Exclude_From_GWB__c, RecordTypeId, Dec_Total__c
                FROM GWB_Consolidator__c
                WHERE Plant_Function__c IN :plantFunctionIds
                  AND Plant__c IN :plantIds
                  AND Year__c IN :priorYears
                  AND Classification__c IN :classifications
                  AND Shop_Manager_View__c IN :shopManagerViews
                  AND Base_Supp__c IN :baseSuppValues
                  AND RecordTypeId IN :consolidatorRecordTypeIds
            ]) {
                String priorKey = buildConsolidatorGroupKey(
                    previousConsolidator.Plant_Function__c,
                    previousConsolidator.Plant__c,
                    previousConsolidator.Year__c == null ? null : previousConsolidator.Year__c + 1,
                    previousConsolidator.Classification__c,
                    previousConsolidator.Shop_Manager_View__c,
                    previousConsolidator.Base_Supp__c,
                    previousConsolidator.Exclude_From_GWB__c,
                    previousConsolidator.RecordTypeId
                );
                Decimal running = priorDecemberByGroup.get(priorKey);
                priorDecemberByGroup.put(
                    priorKey,
                    (running == null ? 0 : running) + d(previousConsolidator.Dec_Total__c)
                );
            }
        }

        for (ConsolidatorTotals totals : totalsByGroupKey.values()) {
            Decimal prevDec = d(priorDecemberByGroup.get(totals.groupKey));
            String failingLabel;
            Decimal janTotal = prevDec + totals.janSum;
            Decimal febTotal = janTotal + totals.febSum;
            Decimal marTotal = febTotal + totals.marSum;
            Decimal aprTotal = marTotal + totals.aprSum;
            Decimal mayTotal = aprTotal + totals.maySum;
            Decimal junTotal = mayTotal + totals.junSum;
            Decimal julTotal = junTotal + totals.julSum;
            Decimal augTotal = julTotal + totals.augSum;
            Decimal sepTotal = augTotal + totals.sepSum;
            Decimal octTotal = sepTotal + totals.octSum;
            Decimal novTotal = octTotal + totals.novSum;
            Decimal decTotal = novTotal + totals.decSum;

            List<Decimal> runningTotals = new List<Decimal>{
                janTotal, febTotal, marTotal, aprTotal, mayTotal, junTotal,
                julTotal, augTotal, sepTotal, octTotal, novTotal, decTotal
            };
            List<String> totalLabels = new List<String>{
                'Jan_Total__c', 'Feb_Total__c', 'Mar_Total__c', 'Apr_Total__c',
                'May_Total__c', 'Jun_Total__c', 'Jul_Total__c', 'Aug_Total__c',
                'Sep_Total__c', 'Oct_Total__c', 'Nov_Total__c', 'Dec_Total__c'
            };

            System.debug(
                LoggingLevel.INFO,
                'Consolidator projection before upsert: ' +
                JSON.serialize(new Map<String, Object>{
                    'groupKey' => totals.groupKey,
                    'plantFunctionId' => totals.plantFunctionId,
                    'year' => totals.yearValue,
                    'classification' => totals.classificationValue,
                    'shopManagerView' => totals.shopManagerView,
                    'prevDecTotal' => prevDec,
                    'janTotal' => janTotal,
                    'febTotal' => febTotal,
                    'marTotal' => marTotal,
                    'aprTotal' => aprTotal,
                    'mayTotal' => mayTotal,
                    'junTotal' => junTotal,
                    'julTotal' => julTotal,
                    'augTotal' => augTotal,
                    'sepTotal' => sepTotal,
                    'octTotal' => octTotal,
                    'novTotal' => novTotal,
                    'decTotal' => decTotal
                })
            );

            if (prevDec < 0) {
                failingLabel = 'Prev_Dec_Total__c';
            } else {
                for (Integer index = 0; index < runningTotals.size(); index++) {
                    if (runningTotals[index] < 0) {
                        failingLabel = totalLabels[index];
                        break;
                    }
                }
            }

            if (failingLabel != null) {
                throw new AuraHandledException(CONSOLIDATOR_NEGATIVE_TOTAL_VALIDATION_MESSAGE);
            }
        }
    }

    // Adds one workbook row into the projected Consolidator aggregation map.
    private static void addWorkbookToConsolidatorTotals(
        Workbook__c workbook,
        Map<Id, Id> workbookToConsolidatorRecordTypeIds,
        Map<String, ConsolidatorTotals> totalsByGroupKey,
        Set<Id> consolidatorRecordTypeIds
    ) {
        if (
            workbook == null ||
            workbook.Plant_Function__c == null ||
            workbook.Plant__c == null ||
            workbook.Year__c == null ||
            String.isBlank(workbook.Classification__c) ||
            String.isBlank(workbook.Shop_Mgr_view__c) ||
            String.isBlank(workbook.Base_Supp__c)
        ) {
            return;
        }

        Id consolidatorRecordTypeId = workbookToConsolidatorRecordTypeIds.get(workbook.RecordTypeId);
        if (consolidatorRecordTypeId == null) {
            return;
        }

        String groupKey = buildConsolidatorGroupKey(
            workbook.Plant_Function__c,
            workbook.Plant__c,
            workbook.Year__c,
            workbook.Classification__c,
            workbook.Shop_Mgr_view__c,
            workbook.Base_Supp__c,
            workbook.Exclude_From_GWB__c,
            consolidatorRecordTypeId
        );
        if (!totalsByGroupKey.containsKey(groupKey)) {
            totalsByGroupKey.put(
                groupKey,
                new ConsolidatorTotals(
                    workbook.Plant_Function__c,
                    workbook.Plant__c,
                    workbook.Year__c,
                    workbook.Classification__c,
                    workbook.Shop_Mgr_view__c,
                    workbook.Base_Supp__c,
                    workbook.Exclude_From_GWB__c == null ? false : workbook.Exclude_From_GWB__c,
                    consolidatorRecordTypeId
                )
            );
        }
        totalsByGroupKey.get(groupKey).accumulate(workbook);
        consolidatorRecordTypeIds.add(consolidatorRecordTypeId);
    }

    // Maps Workbook Record Type Ids to the corresponding Consolidator Record Type Ids.
    private static Map<Id, Id> getConsolidatorRecordTypeByWorkbookRecordType(Set<Id> workbookRecordTypeIds) {
        Map<Id, Id> workbookToConsolidatorRecordTypeIds = new Map<Id, Id>();
        if (workbookRecordTypeIds == null || workbookRecordTypeIds.isEmpty()) {
            return workbookToConsolidatorRecordTypeIds;
        }

        Map<Id, Schema.RecordTypeInfo> workbookRecordTypeInfoById =
            Schema.SObjectType.Workbook__c.getRecordTypeInfosById();
        Map<String, Schema.RecordTypeInfo> consolidatorRecordTypeInfoByDeveloperName =
            Schema.SObjectType.GWB_Consolidator__c.getRecordTypeInfosByDeveloperName();

        for (Id workbookRecordTypeId : workbookRecordTypeIds) {
            Schema.RecordTypeInfo workbookRecordTypeInfo = workbookRecordTypeInfoById.get(workbookRecordTypeId);
            if (workbookRecordTypeInfo == null) {
                continue;
            }
            String consolidatorDeveloperName = WORKBOOK_TO_CONSOLIDATOR_RECORD_TYPES.get(
                workbookRecordTypeInfo.getDeveloperName()
            );
            if (String.isBlank(consolidatorDeveloperName)) {
                continue;
            }
            Schema.RecordTypeInfo consolidatorRecordTypeInfo =
                consolidatorRecordTypeInfoByDeveloperName.get(consolidatorDeveloperName);
            if (consolidatorRecordTypeInfo == null) {
                continue;
            }
            workbookToConsolidatorRecordTypeIds.put(
                workbookRecordTypeId,
                consolidatorRecordTypeInfo.getRecordTypeId()
            );
        }

        return workbookToConsolidatorRecordTypeIds;
    }

    // Builds a deterministic key for Consolidator grouping dimensions.
    private static String buildConsolidatorGroupKey(
        Id plantFunctionId,
        Id plantId,
        Decimal yearValue,
        String classificationValue,
        String shopManagerView,
        String baseSuppValue,
        Boolean excludeFromGwb,
        Id consolidatorRecordTypeId
    ) {
        return String.valueOf(plantFunctionId) +
            '|' + String.valueOf(plantId) +
            '|' + String.valueOf(yearValue) +
            '|' + String.valueOf(classificationValue) +
            '|' + String.valueOf(shopManagerView) +
            '|' + String.valueOf(baseSuppValue) +
            '|' + String.valueOf(excludeFromGwb == null ? false : excludeFromGwb) +
            '|' + String.valueOf(consolidatorRecordTypeId);
    }

    // Null-safe decimal helper for aggregation math.
    private static Decimal d(Decimal value) {
        return value == null ? 0 : value;
    }


    // Returns the Workbook Target record type used for GWB Function adjustment records.
    private static Id getWorkbookTargetRecordTypeId() {
        Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.Workbook__c
            .getRecordTypeInfosByDeveloperName()
            .get(WORKBOOK_TARGET_RECORD_TYPE);
        if (recordTypeInfo == null) {
            throw new AuraHandledException('Workbook Target record type was not found.');
        }
        return recordTypeInfo.getRecordTypeId();
    }

    // Groups Plant Shop Target Items by their parent Plant Shop Target Id.
    private static Map<Id, List<Plant_Shop_Target_Item__c>> getItemsByPlantShopTargetId(
        Set<Id> plantShopTargetIds
    ) {
        Map<Id, List<Plant_Shop_Target_Item__c>> itemsByPlantShopTargetId =
            new Map<Id, List<Plant_Shop_Target_Item__c>>();
        if (plantShopTargetIds == null || plantShopTargetIds.isEmpty()) {
            return itemsByPlantShopTargetId;
        }

        for (Plant_Shop_Target_Item__c item : [
            SELECT Id, Plant_Shop_Target__c, Shop_Manager_View__c, Adjustment__c
            FROM Plant_Shop_Target_Item__c
            WHERE Plant_Shop_Target__c IN :plantShopTargetIds
            ORDER BY Shop_Manager_View__c
        ]) {
            if (!itemsByPlantShopTargetId.containsKey(item.Plant_Shop_Target__c)) {
                itemsByPlantShopTargetId.put(item.Plant_Shop_Target__c, new List<Plant_Shop_Target_Item__c>());
            }
            itemsByPlantShopTargetId.get(item.Plant_Shop_Target__c).add(item);
        }

        return itemsByPlantShopTargetId;
    }

    // Collects the Plant Shop Target dimensions used to narrow saved GWB Function reloads.
    private static TargetPlantFunctionScope buildTargetPlantFunctionScope(
        List<Plant_Shop_Target__c> plantShopTargets,
        Map<Id, List<Plant_Shop_Target_Item__c>> itemsByPlantShopTargetId
    ) {
        TargetPlantFunctionScope scope = new TargetPlantFunctionScope();
        for (Plant_Shop_Target__c plantShopTarget : plantShopTargets) {
            String classification = toPlantShopTargetClassification(plantShopTarget.Classification__c);
            if (
                plantShopTarget.Year__c == null ||
                String.isBlank(plantShopTarget.Driver__c) ||
                String.isBlank(classification)
            ) {
                continue;
            }

            scope.years.add(plantShopTarget.Year__c);
            scope.drivers.add(plantShopTarget.Driver__c);
            scope.classifications.add(classification);

            List<Plant_Shop_Target_Item__c> items = itemsByPlantShopTargetId.get(plantShopTarget.Id);
            if (items == null) {
                continue;
            }
            for (Plant_Shop_Target_Item__c item : items) {
                if (!String.isBlank(item.Shop_Manager_View__c)) {
                    scope.shopManagerViews.add(item.Shop_Manager_View__c);
                }
            }
        }
        return scope;
    }

    // Expands saved GWB Function month crew fields into adjustment wrappers keyed by parent shop context.
    private static Map<String, List<GWBFunctionAdjustment>> getGwbFunctionAdjustmentsByPlantShopKey(
        Id gwbYearId,
        TargetPlantFunctionScope scope
    ) {
        Map<String, List<GWBFunctionAdjustment>> gwbFunctionAdjustmentsByPlantShopKey = new Map<String, List<GWBFunctionAdjustment>>();
        if (
            scope == null ||
            scope.years.isEmpty() ||
            scope.drivers.isEmpty() ||
            scope.classifications.isEmpty() ||
            scope.shopManagerViews.isEmpty()
        ) {
            return gwbFunctionAdjustmentsByPlantShopKey;
        }

        for (Workbook__c gwbFunction : [
            SELECT Id, Name, Year__c, Driver_New__c, Classification__c, Plant_Function__c,
                   Plant_Function__r.Shop_Manager_View__c, Plant_Function__r.Function__c,
                   Plant_Function__r.Name, Plant_Function__r.Function_Name__c,
                   Plant_Function__r.Function__r.Name, Plant_Function__r.Plant_Program__c,
                   Plant_Function__r.Plant_Program__r.Name, Plant_Function__r.Program_Code__c,
                   Plant_Function__r.Function_Level__c, Plant_Function__r.Functional_Area__c,
                   Plant_Function__r.Module__c,
                   Jan_1st__c, Jan_2nd__c, Jan_3rd__c,
                   Feb_1st__c, Feb_2nd__c, Feb_3rd__c,
                   Mar_1st__c, Mar_2nd__c, Mar_3rd__c,
                   Apr_1st__c, Apr_2nd__c, Apr_3rd__c,
                   May_1st__c, May_2nd__c, May_3rd__c,
                   Jun_1st__c, Jun_2nd__c, Jun_3rd__c,
                   Jul_1st__c, Jul_2nd__c, Jul_3rd__c,
                   Aug_1st__c, Aug_2nd__c, Aug_3rd__c,
                   Sep_1st__c, Sep_2nd__c, Sep_3rd__c,
                   Oct_1st__c, Oct_2nd__c, Oct_3rd__c,
                   Nov_1st__c, Nov_2nd__c, Nov_3rd__c,
                   Dec_1st__c, Dec_2nd__c, Dec_3rd__c
            FROM Workbook__c
            WHERE GWB_Year__c = :gwbYearId
            AND RecordType.DeveloperName = :WORKBOOK_TARGET_RECORD_TYPE
            AND Plant_Function__c != null
            AND Year__c IN :scope.years
            AND Driver_New__c IN :scope.drivers
            AND Plant_Function__r.Shop_Manager_View__c IN :scope.shopManagerViews
        ]) {
            String shopManagerView = gwbFunction.Plant_Function__r == null
                ? null
                : gwbFunction.Plant_Function__r.Shop_Manager_View__c;
            String classification = toPlantShopTargetClassification(gwbFunction.Classification__c);
            if (
                String.isBlank(shopManagerView) ||
                String.isBlank(classification) ||
                !scope.classifications.contains(classification) ||
                String.isBlank(gwbFunction.Driver_New__c) ||
                gwbFunction.Year__c == null
            ) {
                continue;
            }

            for (String monthValue : CALENDAR_MONTHS) {
                List<String> crewFields = MONTH_CREW_FIELDS.get(monthValue);
                Decimal crew1 = (Decimal)gwbFunction.get(crewFields[0]);
                Decimal crew2 = (Decimal)gwbFunction.get(crewFields[1]);
                Decimal crew3 = (Decimal)gwbFunction.get(crewFields[2]);
                if (crew1 == null && crew2 == null && crew3 == null) {
                    continue;
                }

                GWBFunctionAdjustment gwbFunctionAdjustment = new GWBFunctionAdjustment();
                gwbFunctionAdjustment.month = monthValue;
                gwbFunctionAdjustment.year = gwbFunction.Year__c;
                gwbFunctionAdjustment.driver = gwbFunction.Driver_New__c;
                gwbFunctionAdjustment.classification = classification;
                gwbFunctionAdjustment.crew1 = crew1;
                gwbFunctionAdjustment.crew2 = crew2;
                gwbFunctionAdjustment.crew3 = crew3;
                gwbFunctionAdjustment.plantFunctionId = String.valueOf(gwbFunction.Plant_Function__c);
                gwbFunctionAdjustment.gwbFunctionId = String.valueOf(gwbFunction.Id);
                gwbFunctionAdjustment.recordDisplayName = gwbFunction.Name;
                gwbFunctionAdjustment.plantFunctionRecordName = gwbFunction.Plant_Function__r == null
                    ? null
                    : gwbFunction.Plant_Function__r.Name;
                gwbFunctionAdjustment.plantFunctionName = gwbFunction.Plant_Function__r == null
                    ? null
                    : gwbFunction.Plant_Function__r.Function_Name__c;
                gwbFunctionAdjustment.plantFunctionMaster = gwbFunction.Plant_Function__r.Function__r == null
                    ? null
                    : gwbFunction.Plant_Function__r.Function__r.Name;
                gwbFunctionAdjustment.plantFunctionMasterId = gwbFunction.Plant_Function__r.Function__c == null
                    ? null
                    : String.valueOf(gwbFunction.Plant_Function__r.Function__c);
                gwbFunctionAdjustment.plantProgramName = gwbFunction.Plant_Function__r.Plant_Program__r == null
                    ? null
                    : gwbFunction.Plant_Function__r.Plant_Program__r.Name;
                gwbFunctionAdjustment.plantProgramId = gwbFunction.Plant_Function__r.Plant_Program__c == null
                    ? null
                    : String.valueOf(gwbFunction.Plant_Function__r.Plant_Program__c);
                gwbFunctionAdjustment.plantProgramCode = gwbFunction.Plant_Function__r.Program_Code__c;
                gwbFunctionAdjustment.plantFunctionLevel = gwbFunction.Plant_Function__r.Function_Level__c;
                gwbFunctionAdjustment.plantFunctionArea = gwbFunction.Plant_Function__r.Functional_Area__c;
                gwbFunctionAdjustment.module = gwbFunction.Plant_Function__r.Module__c;

                String plantShopPayloadKey = getPlantShopPayloadKey(
                    monthValue,
                    toYearString(gwbFunction.Year__c),
                    gwbFunction.Driver_New__c,
                    classification,
                    shopManagerView
                );
                if (!gwbFunctionAdjustmentsByPlantShopKey.containsKey(plantShopPayloadKey)) {
                    gwbFunctionAdjustmentsByPlantShopKey.put(plantShopPayloadKey, new List<GWBFunctionAdjustment>());
                }
                gwbFunctionAdjustmentsByPlantShopKey.get(plantShopPayloadKey).add(gwbFunctionAdjustment);
            }
        }

        return gwbFunctionAdjustmentsByPlantShopKey;
    }

    // Converts a Plant Shop Target record into the payload adjustment shape.
    private static PlantPositionAdjustment toPlantPositionAdjustment(Plant_Shop_Target__c plantShopTarget) {
        String targetClassification = toPlantShopTargetClassification(plantShopTarget.Classification__c);
        if (String.isBlank(targetClassification)) {
            return null;
        }

        PlantPositionAdjustment adjustment = new PlantPositionAdjustment();
        adjustment.adjustmentId = String.valueOf(plantShopTarget.Id);
        adjustment.year = plantShopTarget.Year__c == null ? null : String.valueOf(plantShopTarget.Year__c.intValue());
        adjustment.month = plantShopTarget.Month__c;
        adjustment.driver = plantShopTarget.Driver__c;
        adjustment.classification = targetClassification;
        adjustment.totalChangesNeeded = plantShopTarget.Total_Changes_Needed__c;
        adjustment.totalChangesMade = plantShopTarget.Total_Changes_Made__c;
        adjustment.uniqueKey = buildUniqueKey(new List<String>{
            adjustment.month,
            adjustment.year,
            adjustment.driver,
            adjustment.classification
        });
        return adjustment;
    }

    // Converts a Plant Shop Target Item record into the payload shop shape.
    private static PlantShopAdjustment toPlantShopAdjustment(
        Plant_Shop_Target_Item__c item,
        PlantPositionAdjustment parentAdjustment
    ) {
        PlantShopAdjustment plantShop = new PlantShopAdjustment();
        plantShop.adjustmentId = parentAdjustment.adjustmentId;
        plantShop.adjustmentItemId = String.valueOf(item.Id);
        plantShop.adjustment = item.Adjustment__c;
        plantShop.shopManagerView = item.Shop_Manager_View__c;
        plantShop.plantFunctions = new List<GWBFunctionAdjustment>();
        plantShop.uniqueKey = buildUniqueKey(new List<String>{
            parentAdjustment.month,
            parentAdjustment.year,
            parentAdjustment.driver,
            parentAdjustment.classification,
            plantShop.shopManagerView
        });
        return plantShop;
    }

    // Converts a Plant Function record into the payload shape used by the target UI.
    private static PlantFunction toPlantFunction(Plant_Function__c plantFunctionRecord) {
        PlantFunction plantFunction = new PlantFunction();
        plantFunction.plantFunctionRecordName = plantFunctionRecord.Name;
        plantFunction.plantFunctionName = plantFunctionRecord.Function_Name__c;
        plantFunction.plantFunctionMaster = plantFunctionRecord.Function__r == null
            ? null
            : plantFunctionRecord.Function__r.Name;
        plantFunction.plantProgramName = plantFunctionRecord.Plant_Program__r == null
            ? null
            : plantFunctionRecord.Plant_Program__r.Name;
        plantFunction.plantProgramCode = plantFunctionRecord.Program_Code__c;
        plantFunction.plantFunctionLevel = plantFunctionRecord.Function_Level__c;
        plantFunction.plantFunctionArea = plantFunctionRecord.Functional_Area__c;
        plantFunction.plantFunctionId = plantFunctionRecord.Id;
        plantFunction.plantFunctionMasterId = plantFunctionRecord.Function__c;
        plantFunction.plantProgramId = plantFunctionRecord.Plant_Program__c;
        plantFunction.module = plantFunctionRecord.Module__c;
        return plantFunction;
    }

    // Builds the payload key used to match incoming adjustments to existing records.
    private static String getPayloadKey(PlantPositionAdjustment adjustment) {
        if (!String.isBlank(adjustment.uniqueKey)) {
            return adjustment.uniqueKey;
        }
        return buildUniqueKey(new List<String>{ adjustment.month, adjustment.year, adjustment.driver, adjustment.classification });
    }

    // Builds a normalized composite key for Plant Shop Target matching.
    private static String getPlantShopTargetCompositeKey(Plant_Shop_Target__c plantShopTarget) {
        String yearValue = plantShopTarget.Year__c == null ? null : String.valueOf(plantShopTarget.Year__c.intValue());
        return buildNormalizedKey(new List<String>{
            yearValue,
            plantShopTarget.Month__c,
            plantShopTarget.Driver__c,
            toPlantShopTargetClassification(plantShopTarget.Classification__c)
        });
    }

    // Builds a normalized composite key for Plant Shop Target Item matching.
    private static String getItemCompositeKey(Id plantShopTargetId, String shopManagerView) {
        return buildNormalizedKey(new List<String>{ String.valueOf(plantShopTargetId), shopManagerView });
    }

    // Builds the lookup key used to attach saved plant function wrappers to a plant shop wrapper.
    private static String getPlantShopPayloadKey(PlantPositionAdjustment adjustment, String shopManagerView) {
        return getPlantShopPayloadKey(
            adjustment.month,
            adjustment.year,
            adjustment.driver,
            adjustment.classification,
            shopManagerView
        );
    }

    // Builds the normalized plant shop payload key from explicit parent and shop values.
    private static String getPlantShopPayloadKey(
        String monthValue,
        String yearValue,
        String driverValue,
        String classificationValue,
        String shopManagerView
    ) {
        return buildNormalizedKey(new List<String>{
            monthValue,
            yearValue,
            driverValue,
            toPlantShopTargetClassification(classificationValue),
            shopManagerView
        });
    }

    // Builds the normalized grouping key for consolidated GWB Function records.
    private static String getGwbFunctionGroupKey(
        Decimal yearValue,
        String driverValue,
        String classificationValue,
        Id plantFunctionId
    ) {
        return buildNormalizedKey(new List<String>{
            toYearString(yearValue),
            driverValue,
            classificationValue,
            String.valueOf(plantFunctionId)
        });
    }

    // Joins values into a stable unique key for payload records.
    private static String buildUniqueKey(List<String> values) {
        List<String> normalizedValues = new List<String>();
        for (String value : values) {
            normalizedValues.add(value == null ? '' : value.trim());
        }
        return String.join(normalizedValues, '-');
    }

    // Joins values into a normalized lookup key.
    private static String buildNormalizedKey(List<String> values) {
        List<String> normalizedValues = new List<String>();
        for (String value : values) {
            normalizedValues.add(String.isBlank(value) ? '' : value.trim().toLowerCase());
        }
        return String.join(normalizedValues, '|');
    }

    // Returns the option list with "All" first, followed by known ordering and then sorted remaining values.
    private static List<String> buildOrderedOptions(Set<String> values, List<String> preferredOrder) {
        List<String> options = new List<String>{ ALL_OPTION };
        options.addAll(buildOrderedValues(values, preferredOrder));
        return options;
    }

    // Orders values deterministically while allowing unexpected values to remain available.
    private static List<String> buildOrderedValues(Set<String> values, List<String> preferredOrder) {
        List<String> orderedValues = new List<String>();
        if (values == null || values.isEmpty()) {
            return orderedValues;
        }

        Set<String> remainingValues = new Set<String>(values);
        if (preferredOrder != null) {
            for (String preferredValue : preferredOrder) {
                if (remainingValues.remove(preferredValue)) {
                    orderedValues.add(preferredValue);
                }
            }
        }

        List<String> extraValues = new List<String>(remainingValues);
        extraValues.sort();
        orderedValues.addAll(extraValues);
        return orderedValues;
    }

    // Parses a year string into a Decimal value when present.
    private static Decimal parseYear(String yearValue) {
        if (String.isBlank(yearValue)) {
            return null;
        }
        try {
            return Decimal.valueOf(yearValue);
        } catch (TypeException ex) {
            throw new AuraHandledException('Invalid year value: ' + yearValue);
        }
    }

    // Converts stored Decimal year values into the string format used by payload keys.
    private static String toYearString(Decimal yearValue) {
        return yearValue == null ? null : String.valueOf(yearValue.intValue());
    }

    // Trims text copied into fields with a smaller storage limit than the source field.
    private static String truncateText(String value, Integer maxLength) {
        if (value == null || maxLength == null || value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }

    // Normalizes source classification values to the Plant Shop Target classification group.
    private static String toPlantShopTargetClassification(String classification) {
        return ClassificationDecoder.toClassificationGroup(classification);
    }

    // Parses an optional Id string and returns null when blank.
    private static Id parseOptionalId(String idValue, String fieldName) {
        if (String.isBlank(idValue)) {
            return null;
        }
        return parseId(idValue, fieldName);
    }

    // Parses and validates an Id string for a specific field.
    private static Id parseId(String idValue, String fieldName) {
        try {
            return (Id)idValue;
        } catch (Exception ex) {
            throw new AuraHandledException('Invalid ' + fieldName + ': ' + idValue);
        }
    }

    // Holds all monthly GWB Function adjustment wrapper values that consolidate into one GWB Function.
    private class GwbFunctionTargetGroup {
        private Decimal yearValue;
        private String driver;
        private String classification;
        private Id plantFunctionId;
        private Id gwbFunctionId;
        private Map<String, GWBFunctionAdjustment> gwbFunctionAdjustmentsByMonth;

        private GwbFunctionTargetGroup(
            Decimal yearValue,
            String driver,
            String classification,
            Id plantFunctionId
        ) {
            this.yearValue = yearValue;
            this.driver = driver;
            this.classification = classification;
            this.plantFunctionId = plantFunctionId;
            this.gwbFunctionAdjustmentsByMonth = new Map<String, GWBFunctionAdjustment>();
        }

        private void addGwbFunctionAdjustment(
            String monthValue,
            GWBFunctionAdjustment gwbFunctionAdjustment,
            Id incomingGwbFunctionId
        ) {
            if (incomingGwbFunctionId != null) {
                if (gwbFunctionId != null && gwbFunctionId != incomingGwbFunctionId) {
                    throw new AuraHandledException('Grouped Plant Function adjustments cannot reference multiple GWB Functions.');
                }
                gwbFunctionId = incomingGwbFunctionId;
            }
            gwbFunctionAdjustmentsByMonth.put(monthValue, gwbFunctionAdjustment);
        }
    }

    // Stores the loaded target dimensions used to keep GWB Function reverse queries selective.
    private class TargetPlantFunctionScope {
        private Set<Decimal> years = new Set<Decimal>();
        private Set<String> drivers = new Set<String>();
        private Set<String> classifications = new Set<String>();
        private Set<String> shopManagerViews = new Set<String>();
    }

    public class AdjustmentPayload {
        @AuraEnabled public Id gwbYearId { get; set; }
        @AuraEnabled public List<PlantPositionAdjustment> plantPositionAdjustments { get; set; }
    }

    public class GlobalFilters {
        @AuraEnabled public List<String> months { get; set; }
        @AuraEnabled public Map<String, List<String>> classificationByMonth { get; set; }
        @AuraEnabled public Map<String, List<String>> driverByClassification { get; set; }
    }

    public class AdjustmentAccessResult {
        @AuraEnabled public Boolean hasAdjustmentEditPermission { get; set; }
    }

    public class PlantPositionAdjustment {
        @AuraEnabled public String uniqueKey { get; set; }
        @AuraEnabled public String year { get; set; }
        @AuraEnabled public String month { get; set; }
        @AuraEnabled public String driver { get; set; }
        @AuraEnabled public String classification { get; set; }
        @AuraEnabled public Decimal totalChangesNeeded { get; set; }
        @AuraEnabled public Decimal totalChangesMade { get; set; }
        @AuraEnabled public String adjustmentId { get; set; }
        @AuraEnabled public List<PlantShopAdjustment> plantShops { get; set; }
    }

    public class PlantShopAdjustment {
        @AuraEnabled public String uniqueKey { get; set; }
        @AuraEnabled public String adjustmentId { get; set; }
        @AuraEnabled public String adjustmentItemId { get; set; }
        @AuraEnabled public Decimal adjustment { get; set; }
        @AuraEnabled public String shopManagerView { get; set; }
        @AuraEnabled public List<GWBFunctionAdjustment> plantFunctions { get; set; }
    }

    // Aggregated monthly crew totals for one projected Consolidator record.
    private class ConsolidatorTotals {
        public String groupKey;
        public Id plantFunctionId;
        public Decimal yearValue;
        public String classificationValue;
        public String shopManagerView;

        public Decimal janSum = 0;
        public Decimal febSum = 0;
        public Decimal marSum = 0;
        public Decimal aprSum = 0;
        public Decimal maySum = 0;
        public Decimal junSum = 0;
        public Decimal julSum = 0;
        public Decimal augSum = 0;
        public Decimal sepSum = 0;
        public Decimal octSum = 0;
        public Decimal novSum = 0;
        public Decimal decSum = 0;

        public ConsolidatorTotals(
            Id plantFunctionId,
            Id plantId,
            Decimal yearValue,
            String classificationValue,
            String shopManagerView,
            String baseSuppValue,
            Boolean excludeFromGwb,
            Id consolidatorRecordTypeId
        ) {
            this.plantFunctionId = plantFunctionId;
            this.yearValue = yearValue;
            this.classificationValue = classificationValue;
            this.shopManagerView = shopManagerView;
            this.groupKey = buildConsolidatorGroupKey(
                plantFunctionId,
                plantId,
                yearValue,
                classificationValue,
                shopManagerView,
                baseSuppValue,
                excludeFromGwb,
                consolidatorRecordTypeId
            );
        }

        public void accumulate(Workbook__c workbook) {
            janSum += d(workbook.Jan_1st__c) + d(workbook.Jan_2nd__c) + d(workbook.Jan_3rd__c);
            febSum += d(workbook.Feb_1st__c) + d(workbook.Feb_2nd__c) + d(workbook.Feb_3rd__c);
            marSum += d(workbook.Mar_1st__c) + d(workbook.Mar_2nd__c) + d(workbook.Mar_3rd__c);
            aprSum += d(workbook.Apr_1st__c) + d(workbook.Apr_2nd__c) + d(workbook.Apr_3rd__c);
            maySum += d(workbook.May_1st__c) + d(workbook.May_2nd__c) + d(workbook.May_3rd__c);
            junSum += d(workbook.Jun_1st__c) + d(workbook.Jun_2nd__c) + d(workbook.Jun_3rd__c);
            julSum += d(workbook.Jul_1st__c) + d(workbook.Jul_2nd__c) + d(workbook.Jul_3rd__c);
            augSum += d(workbook.Aug_1st__c) + d(workbook.Aug_2nd__c) + d(workbook.Aug_3rd__c);
            sepSum += d(workbook.Sep_1st__c) + d(workbook.Sep_2nd__c) + d(workbook.Sep_3rd__c);
            octSum += d(workbook.Oct_1st__c) + d(workbook.Oct_2nd__c) + d(workbook.Oct_3rd__c);
            novSum += d(workbook.Nov_1st__c) + d(workbook.Nov_2nd__c) + d(workbook.Nov_3rd__c);
            decSum += d(workbook.Dec_1st__c) + d(workbook.Dec_2nd__c) + d(workbook.Dec_3rd__c);
        }
    }

    // Represents a saved adjustment wrapper nested under a plant shop wrapper. Holds GWB Function references and monthly crew values.
    public class GWBFunctionAdjustment {
        @AuraEnabled public String recordDisplayName { get; set; }
        @AuraEnabled public String plantFunctionRecordName { get; set; }
        @AuraEnabled public String plantFunctionName { get; set; }
        @AuraEnabled public String plantFunctionMaster { get; set; }
        @AuraEnabled public String plantProgramName { get; set; }
        @AuraEnabled public String plantProgramCode { get; set; }
        @AuraEnabled public String plantFunctionLevel { get; set; }
        @AuraEnabled public String plantFunctionArea { get; set; }
        @AuraEnabled public String plantFunctionMasterId { get; set; }
        @AuraEnabled public String plantProgramId { get; set; }
        @AuraEnabled public String month { get; set; }
        @AuraEnabled public Decimal year { get; set; }
        @AuraEnabled public String driver { get; set; }
        @AuraEnabled public String classification { get; set; }
        @AuraEnabled public Decimal crew1 { get; set; }
        @AuraEnabled public Decimal crew2 { get; set; }
        @AuraEnabled public Decimal crew3 { get; set; }
        @AuraEnabled public String plantFunctionId { get; set; }
        @AuraEnabled public String gwbFunctionId { get; set; }
        @AuraEnabled public String line { get; set; }
        @AuraEnabled public String module { get; set; }
    }

    // Represents a Plant Function record as a wrapper for the target UI. Holds Plant Function details and record references.
    public class PlantFunction {
        @AuraEnabled public String plantFunctionRecordName { get; set; }
        @AuraEnabled public String plantFunctionName { get; set; }
        @AuraEnabled public String plantFunctionMaster { get; set; }
        @AuraEnabled public String plantProgramName { get; set; }
        @AuraEnabled public String plantProgramCode { get; set; }
        @AuraEnabled public String plantFunctionLevel { get; set; }
        @AuraEnabled public String plantFunctionArea { get; set; }
        @AuraEnabled public Id plantFunctionId { get; set; }
        @AuraEnabled public Id plantFunctionMasterId { get; set; }
        @AuraEnabled public Id plantProgramId { get; set; }
        @AuraEnabled public String line { get; set; }
        @AuraEnabled public String module { get; set; }
    }

    public class SaveResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Integer plantPositionAdjustmentCount { get; set; }
        @AuraEnabled public Integer plantShopCount { get; set; }
    }
}