/**
 * @description Trigger on Function__c for activation processing.
 */
trigger FunctionTrigger on Function__c (after insert, after update) {
    FunctionTriggerHandler.handleTrigger(
        Trigger.new,
        Trigger.isUpdate ? Trigger.oldMap : null
    );
}