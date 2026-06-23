trigger PlantProgramTrigger on Plant_Program__c (after insert, after update) {
    if (Trigger.isAfter && Trigger.isInsert) {
        PlantProgramTriggerHandler.handleAfterInsert(Trigger.new);
    }
}