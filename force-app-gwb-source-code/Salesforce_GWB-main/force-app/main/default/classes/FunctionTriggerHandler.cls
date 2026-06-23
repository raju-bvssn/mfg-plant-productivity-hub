/**
 * @description Handler class for Function__c trigger.
 */
public without sharing class FunctionTriggerHandler {
    /**
     * @description Main handler method for Function__c trigger activation events.
     * @param newRecords List of new/updated Function__c records
     * @param oldMap Prior version of records on update, null on insert
     */
    public static void handleTrigger(List<Function__c> newRecords, Map<Id, Function__c> oldMap) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }

        syncPlantFunctionShopManagerViews(newRecords, oldMap);
        deactivatePlantFunctions(newRecords, oldMap);

        List<Function__c> eligibleFunctions = getEligibleFunctions(newRecords, oldMap);
        if (eligibleFunctions.isEmpty()) {
            return;
        }

        Set<String> authSectors = new Set<String>();
        Set<String> productTypes = new Set<String>();
        for (Function__c functionRecord : eligibleFunctions) {
            authSectors.add(functionRecord.Auth_Sector__c);
            productTypes.add(functionRecord.Product_Type__c);
        }

        List<Plant_Program__c> activePlanOfRecordPrograms = [
            SELECT Id, Auth_Plant_Name__c, Plant_Shop__c, Plant_Shop__r.Auth_Plant_Name__c,
                   Auth_Sector1__c, Product_Type__c, Shop__c, Program_Product_Index__c, Shifts_Def__c
            FROM Plant_Program__c
            WHERE Include__c = true
            AND Status__c = :PlantFunctionMatchingHelper.ACTIVE_PLANT_PROGRAM_STATUS
            AND Auth_Sector1__c IN :authSectors
            AND Product_Type__c IN :productTypes
        ];
        if (activePlanOfRecordPrograms.isEmpty()) {
            return;
        }

        List<Plant_Function__c> plantFunctionsToInsert =
            PlantFunctionMatchingHelper.buildPlantFunctions(eligibleFunctions, activePlanOfRecordPrograms);
        if (plantFunctionsToInsert.isEmpty()) {
            return;
        }
        
        // Enforce: only set the Function__c lookup on Plant_Function__c if the referenced
        // Function__c has Included_in_Auth_Plan_of_Record__c = true.
        // This covers cases where callers create Plant_Function__c records (e.g., via matching helper)
        // and we need to ensure the Function__c is only assigned when permitted.
        // Build set of Function Ids referenced by the candidate Plant Functions.
        Set<Id> candidateFunctionIds = new Set<Id>();
        for (Plant_Function__c pfCandidate : plantFunctionsToInsert) {
            if (pfCandidate.Function__c != null) {
                candidateFunctionIds.add(pfCandidate.Function__c);
            }
        }
        // Query Included_in_Auth_Plan_of_Record__c for those functions
        Map<Id, Function__c> funcsById = new Map<Id, Function__c>();
        if (!candidateFunctionIds.isEmpty()) {
            for (Function__c f : [
                SELECT Id, Included_in_Auth_Plan_of_Record__c
                FROM Function__c
                WHERE Id IN :candidateFunctionIds
            ]) {
                funcsById.put(f.Id, f);
            }
        }
        // Iterate backwards to safely remove ineligible candidates without index skipping.
        for (Integer i = plantFunctionsToInsert.size() - 1; i >= 0; i--) {
            Plant_Function__c pf = plantFunctionsToInsert[i];
            if (pf.Function__c == null) continue;

            Function__c related = funcsById.get(pf.Function__c);
            if (related == null || related.Included_in_Auth_Plan_of_Record__c != true) {
                plantFunctionsToInsert.remove(i);
            }
        }

        // Query existing records by Plant Program + Function to handle both deduplication and re-activation.
        // Active records are skipped; Decommissioned records are re-activated.
        Map<String, Plant_Function__c> existingByCompositeKey = new Map<String, Plant_Function__c>();
        Set<Id> plantProgramIds = new Set<Id>();
        Set<Id> functionIds = new Set<Id>();
        for (Plant_Function__c plantFunction : plantFunctionsToInsert) {
            if (plantFunction.Plant_Program__c != null) {
                plantProgramIds.add(plantFunction.Plant_Program__c);
            }
            if (plantFunction.Function__c != null) {
                functionIds.add(plantFunction.Function__c);
            }
        }
        for (Plant_Function__c existingPF : [
            SELECT Id, Plant_Program__c, Function__c, Status__c
            FROM Plant_Function__c
            WHERE Plant_Program__c IN :plantProgramIds
            AND Function__c IN :functionIds
        ]) {
            existingByCompositeKey.put(getCompositeKey(existingPF.Plant_Program__c, existingPF.Function__c), existingPF);
        }

        List<Plant_Function__c> newPlantFunctions = new List<Plant_Function__c>();
        List<Plant_Function__c> reactivatePlantFunctions = new List<Plant_Function__c>();
        for (Plant_Function__c plantFunction : plantFunctionsToInsert) {
            Plant_Function__c existing = existingByCompositeKey.get(
                getCompositeKey(plantFunction.Plant_Program__c, plantFunction.Function__c)
            );
            if (existing == null) {
                newPlantFunctions.add(plantFunction);
            } else if (existing.Status__c == PlantFunctionMatchingHelper.DECOMMISSIONED_PLANT_FUNCTION_STATUS) {
                reactivatePlantFunctions.add(new Plant_Function__c(
                    Id = existing.Id,
                    Status__c = PlantFunctionMatchingHelper.ACTIVE_PLANT_FUNCTION_STATUS
                ));
            }
            // Already Active — skip to avoid duplicates.
        }

        if (!newPlantFunctions.isEmpty()) {
            insert newPlantFunctions;
        }
        if (!reactivatePlantFunctions.isEmpty()) {
            update reactivatePlantFunctions;
        }
    }

    private static void deactivatePlantFunctions(List<Function__c> newRecords, Map<Id, Function__c> oldMap) {
        if (oldMap == null || oldMap.isEmpty()) {
            return;
        }

        List<Id> deactivatedFunctionIds = new List<Id>();
        for (Function__c functionRecord : newRecords) {
            Function__c oldRecord = oldMap.get(functionRecord.Id);
            if (oldRecord != null
                    && oldRecord.Included_in_Auth_Plan_of_Record__c == true
                    && functionRecord.Included_in_Auth_Plan_of_Record__c != true) {
                deactivatedFunctionIds.add(functionRecord.Id);
            }
        }

        if (deactivatedFunctionIds.isEmpty()) {
            return;
        }

        List<Plant_Function__c> toDeactivate = [
            SELECT Id
            FROM Plant_Function__c
            WHERE Function__c IN :deactivatedFunctionIds
            AND Status__c = :PlantFunctionMatchingHelper.ACTIVE_PLANT_FUNCTION_STATUS
        ];

        if (toDeactivate.isEmpty()) {
            return;
        }

        for (Plant_Function__c pf : toDeactivate) {
            pf.Status__c = PlantFunctionMatchingHelper.DECOMMISSIONED_PLANT_FUNCTION_STATUS;
        }
        update toDeactivate;
    }

    private static void syncPlantFunctionShopManagerViews(List<Function__c> newRecords, Map<Id, Function__c> oldMap) {
        if (oldMap == null || oldMap.isEmpty()) {
            return;
        }

        Map<Id, String> updatedShopViewsByFunctionId = new Map<Id, String>();
        for (Function__c functionRecord : newRecords) {
            Function__c oldRecord = oldMap.get(functionRecord.Id);
            if (oldRecord != null && oldRecord.Shop_Master_View__c != functionRecord.Shop_Master_View__c) {
                updatedShopViewsByFunctionId.put(functionRecord.Id, String.valueOf(functionRecord.Shop_Master_View__c));
            }
        }

        if (updatedShopViewsByFunctionId.isEmpty()) {
            return;
        }

        List<Plant_Function__c> plantFunctionsToUpdate = new List<Plant_Function__c>();
        for (Plant_Function__c plantFunction : [
            SELECT Id, Function__c, Shop_Manager_View__c
            FROM Plant_Function__c
            WHERE Function__c IN :updatedShopViewsByFunctionId.keySet()
        ]) {
            String newShopManagerView = updatedShopViewsByFunctionId.get(plantFunction.Function__c);
            if (plantFunction.Shop_Manager_View__c != newShopManagerView) {
                plantFunctionsToUpdate.add(new Plant_Function__c(
                    Id = plantFunction.Id,
                    Shop_Manager_View__c = newShopManagerView
                ));
            }
        }

        if (!plantFunctionsToUpdate.isEmpty()) {
            update plantFunctionsToUpdate;
        }
    }

    private static List<Function__c> getEligibleFunctions(List<Function__c> newRecords, Map<Id, Function__c> oldMap) {
        List<Function__c> eligibleFunctions = new List<Function__c>();
        for (Function__c functionRecord : newRecords) {
            if (isActivationEvent(functionRecord, oldMap) &&
                !PlantFunctionMatchingHelper.isEquationFunction(functionRecord)) {
                eligibleFunctions.add(functionRecord);
            }
        }
        return eligibleFunctions;
    }

    private static Boolean isActivationEvent(Function__c functionRecord, Map<Id, Function__c> oldMap) {
        if (functionRecord == null || functionRecord.Included_in_Auth_Plan_of_Record__c != true) {
            return false;
        }

        if (oldMap == null || !oldMap.containsKey(functionRecord.Id)) {
            return true;
        }

        Function__c oldRecord = oldMap.get(functionRecord.Id);
        return oldRecord == null || oldRecord.Included_in_Auth_Plan_of_Record__c != true;
    }

    private static String getCompositeKey(Id plantProgramId, Id functionId) {
        return String.valueOf(plantProgramId) + ':' + String.valueOf(functionId);
    }
}