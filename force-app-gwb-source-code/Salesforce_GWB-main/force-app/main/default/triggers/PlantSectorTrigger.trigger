trigger PlantSectorTrigger on Plant_Sector__c (before insert) {
    PlantSectorTriggerHandler.handleBeforeInsert(Trigger.new);
}