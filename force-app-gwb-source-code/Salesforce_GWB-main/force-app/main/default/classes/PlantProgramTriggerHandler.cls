/**
 * Handler class for Plant_Program__c trigger
 */
public with sharing class PlantProgramTriggerHandler {
    public static void handleAfterInsert(List<Plant_Program__c> newRecords) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }

        List<Plant_Program__c> eligiblePrograms = getEligiblePrograms(newRecords);
        if (eligiblePrograms.isEmpty()) {
            return;
        }

        Set<String> authSectors = new Set<String>();
        Set<String> productTypes = new Set<String>();
        Set<String> shops = new Set<String>();
        for (Plant_Program__c program : eligiblePrograms) {
            authSectors.add(program.Auth_Sector1__c);
            productTypes.add(program.Product_Type__c);
            shops.add(program.Shop__c);
        }

        List<Function__c> eligibleFunctions = [
            SELECT Id, Name, Auth_Sector__c, Product_Type__c, Shop_Master_View__c,
                   Program_Product_Index__c, Included_in_Auth_Plan_of_Record__c
            FROM Function__c
            WHERE Included_in_Auth_Plan_of_Record__c = true
            AND Auth_Sector__c IN :authSectors
            AND Product_Type__c IN :productTypes
            AND Shop_Master_View__c IN :shops
        ];
        if (eligibleFunctions.isEmpty()) {
            return;
        }

        List<Plant_Function__c> plantFunctionsToInsert =
            PlantFunctionMatchingHelper.buildPlantFunctions(eligibleFunctions, eligiblePrograms);
        if (plantFunctionsToInsert.isEmpty()) {
            return;
        }

        Set<Id> eligibleProgramIds = new Set<Id>();
        for (Plant_Program__c program : eligiblePrograms) {
            eligibleProgramIds.add(program.Id);
        }
        Set<Id> eligibleFunctionIds = new Set<Id>();
        for (Function__c functionRecord : eligibleFunctions) {
            eligibleFunctionIds.add(functionRecord.Id);
        }

        Set<String> existingCompositeKeys = new Set<String>();
        for (Plant_Function__c existingPlantFunction : [
            SELECT Plant_Program__c, Function__c
            FROM Plant_Function__c
            WHERE Plant_Program__c IN :eligibleProgramIds
            AND Function__c IN :eligibleFunctionIds
        ]) {
            existingCompositeKeys.add(getCompositeKey(existingPlantFunction.Plant_Program__c, existingPlantFunction.Function__c));
        }

        List<Plant_Function__c> newPlantFunctions = new List<Plant_Function__c>();
        for (Plant_Function__c plantFunction : plantFunctionsToInsert) {
            String key = getCompositeKey(plantFunction.Plant_Program__c, plantFunction.Function__c);
            if (!existingCompositeKeys.contains(key)) {
                newPlantFunctions.add(plantFunction);
            }
        }

        if (!newPlantFunctions.isEmpty()) {
            // SANITIZATION: Ensure Function__c is only assigned when the referenced Function__c
            // record has Included_in_Auth_Plan_of_Record__c = true. Bulkified check.
            Set<Id> referencedFunctionIds = new Set<Id>();
            for (Plant_Function__c pfCand : newPlantFunctions) {
                if (pfCand.Function__c != null) {
                    referencedFunctionIds.add(pfCand.Function__c);
                }
            }
            Map<Id, Function__c> functionsMap = new Map<Id, Function__c>();
            if (!referencedFunctionIds.isEmpty()) {
                for (Function__c f : [
                    SELECT Id, Included_in_Auth_Plan_of_Record__c
                    FROM Function__c
                    WHERE Id IN :referencedFunctionIds
                ]) {
                    functionsMap.put(f.Id, f);
                }
            }
            for (Integer i = newPlantFunctions.size() - 1; i >= 0; i--) {
                Plant_Function__c pfCand = newPlantFunctions[i];
                if (pfCand.Function__c == null) continue;
                
                Function__c related = functionsMap.get(pfCand.Function__c);
                if (related == null || related.Included_in_Auth_Plan_of_Record__c != true) {
                    newPlantFunctions.remove(i);
                }
            }
            
            if (!newPlantFunctions.isEmpty()) {
                insert newPlantFunctions;
            }
        }
    }

    private static List<Plant_Program__c> getEligiblePrograms(List<Plant_Program__c> newRecords) {
        List<Plant_Program__c> eligiblePrograms = new List<Plant_Program__c>();
        for (Plant_Program__c program : newRecords) {
            if (program.Include__c == true &&
                program.Status__c == PlantFunctionMatchingHelper.ACTIVE_PLANT_PROGRAM_STATUS &&
                String.isNotBlank(program.Auth_Sector1__c) &&
                String.isNotBlank(program.Product_Type__c) &&
                String.isNotBlank(program.Shop__c)) {
                eligiblePrograms.add(program);
            }
        }
        return eligiblePrograms;
    }

    private static String getCompositeKey(Id plantProgramId, Id functionId) {
        return String.valueOf(plantProgramId) + ':' + String.valueOf(functionId);
    }
}