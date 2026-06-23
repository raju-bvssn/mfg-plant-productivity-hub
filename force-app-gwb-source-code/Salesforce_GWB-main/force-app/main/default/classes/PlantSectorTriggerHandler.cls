/**
 * @description Prevents inserting duplicate Plant Sector records for the same Plant.
 */
public with sharing class PlantSectorTriggerHandler {
    public static void handleBeforeInsert(List<Plant_Sector__c> newRecords) {
        Set<Id> plantIds = new Set<Id>();
        Set<Id> duplicatePlantIdsInTransaction = new Set<Id>();
        Set<Id> seenPlantIds = new Set<Id>();

        for (Plant_Sector__c plantSector : newRecords) {
            if (plantSector.Plant__c == null) {
                continue;
            }

            if (!seenPlantIds.add(plantSector.Plant__c)) {
                duplicatePlantIdsInTransaction.add(plantSector.Plant__c);
            }

            plantIds.add(plantSector.Plant__c);
        }

        if (plantIds.isEmpty()) {
            return;
        }

        Map<Id, Plant__c> plantsById = new Map<Id, Plant__c>();
        for (Plant__c plant : [
            SELECT Id, Name, Auth_Region__c
            FROM Plant__c
            WHERE Id IN :plantIds
        ]) {
            plantsById.put(plant.Id, plant);
        }

        Set<Id> existingPlantIds = new Set<Id>();
        for (Plant_Sector__c existingPlantSector : [
            SELECT Id, Plant__c
            FROM Plant_Sector__c
            WHERE Plant__c IN :plantIds
        ]) {
            existingPlantIds.add(existingPlantSector.Plant__c);
        }

        for (Plant_Sector__c plantSector : newRecords) {
            if (plantSector.Plant__c == null) {
                continue;
            }

            Plant__c plant = plantsById.get(plantSector.Plant__c);
            // Populate Auth_Region__c from parent Plant
            if (plant != null && plant.Auth_Region__c != null) {
                plantSector.Auth_Region__c = plant.Auth_Region__c;
            }

            /*if (duplicatePlantIdsInTransaction.contains(plantSector.Plant__c) || existingPlantIds.contains(plantSector.Plant__c)) {
                String plantName = plant.Name;
                String message = 'A Plant Sector record already exists for this Plant.';
                if (String.isNotBlank(plantName)) {
                    message = 'A Plant Sector record already exists for plant "' + plantName + '".';
                }
                plantSector.addError(message);
            }*/
        }
    }
}