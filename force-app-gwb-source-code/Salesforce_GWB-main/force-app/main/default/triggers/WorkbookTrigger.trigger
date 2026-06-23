/**
 * @description       : Trigger for Workbook__c object
 *                      Before insert: auto-populates Previous_Year_Workbook__c from the prior year.
 *                      After insert:  enqueues YTD Adjustment batch (seeds Prev Dec + running sums)
 *                                     and GWBConsolidatorBatch (creates Consolidator records).
 *                      After update:  enqueues YTD Adjustment batch and GWBConsolidatorBatch when
 *                                     crew month shift fields (Jan_1st__c – Dec_3rd__c) change.
 * @group             : Plant Management
 * @last modified on  : 05-20-2026
**/
trigger WorkbookTrigger on Workbook__c (before insert, after insert, after update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        WorkbookTriggerHandler.handleBeforeInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isInsert) {
        WorkbookTriggerHandler.handleAfterInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        WorkbookTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}