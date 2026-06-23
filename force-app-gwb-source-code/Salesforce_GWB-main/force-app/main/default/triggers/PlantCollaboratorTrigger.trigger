/**
 * @description Trigger on Plant_Collaborator__c for deleting group member once record is deleted.
 */
trigger PlantCollaboratorTrigger on Plant_Collaborator__c (after delete) {
    
    if (Trigger.isAfter && Trigger.isDelete) {
        PlantCollaboratorTriggerHandler.handleAfterDelete(Trigger.old);
    }
    
}