trigger OperationPlanTrigger on Operation_Plan__c (before insert, before update) {
    OperationPlanTriggerHandler.handleTrigger(Trigger.new, Trigger.oldMap);
}