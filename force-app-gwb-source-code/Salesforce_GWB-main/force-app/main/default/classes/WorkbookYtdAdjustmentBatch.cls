/**
 * @description       : Batch class that populates YTD_Adjustment_*__c running sum fields on
 *                      Workbook__c records. Processes 200 records per batch execution.
 *                      On insert (populatePrevDec=true), seeds YTD_Adjustment_Prev_Dec_*__c
 *                      from the linked Previous_Year_Workbook__c before computing running sums.
 *                      On update (populatePrevDec=false), recomputes Jan–Dec running sums only.
 * @group             : Plant Management
 * @last modified on  : 05-20-2026
 */
public with sharing class WorkbookYtdAdjustmentBatch implements Database.Batchable<SObject> {

    private Set<Id>  workbookIds;
    private Boolean  populatePrevDec;

    /**
     * @param workbookIds     IDs of Workbook__c records to process
     * @param populatePrevDec When true, seeds Prev Dec values from the previous year's workbook
     *                        (insert path only). When false, only recomputes Jan–Dec running sums.
     */
    public WorkbookYtdAdjustmentBatch(Set<Id> workbookIds, Boolean populatePrevDec) {
        this.workbookIds    = workbookIds    != null ? workbookIds    : new Set<Id>();
        this.populatePrevDec = populatePrevDec != null ? populatePrevDec : false;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Previous_Year_Workbook__c,
                   Jan_1st__c,  Jan_2nd__c,  Jan_3rd__c,
                   Feb_1st__c,  Feb_2nd__c,  Feb_3rd__c,
                   Mar_1st__c,  Mar_2nd__c,  Mar_3rd__c,
                   Apr_1st__c,  Apr_2nd__c,  Apr_3rd__c,
                   May_1st__c,  May_2nd__c,  May_3rd__c,
                   Jun_1st__c,  Jun_2nd__c,  Jun_3rd__c,
                   Jul_1st__c,  Jul_2nd__c,  Jul_3rd__c,
                   Aug_1st__c,  Aug_2nd__c,  Aug_3rd__c,
                   Sep_1st__c,  Sep_2nd__c,  Sep_3rd__c,
                   Oct_1st__c,  Oct_2nd__c,  Oct_3rd__c,
                   Nov_1st__c,  Nov_2nd__c,  Nov_3rd__c,
                   Dec_1st__c,  Dec_2nd__c,  Dec_3rd__c
            FROM Workbook__c
            WHERE Id IN :workbookIds
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Workbook__c> scope) {
        if (populatePrevDec) {
            seedPrevDecValues(scope);
        }
        for (Workbook__c wb : scope) {
            WorkbookTriggerHandler.calculateYtdOnRecord(wb);
        }
        try {
            update scope;
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR,
                'WorkbookYtdAdjustmentBatch: Error updating YTD Adjustment fields: ' + e.getMessage());
            throw e;
        }
    }

    public void finish(Database.BatchableContext bc) {}

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Queries the previous year workbooks for each record in scope and sets
     *              YTD_Adjustment_Prev_Dec_1st/2nd/3rd__c. Defaults to 0 when no previous
     *              year workbook is linked or the Dec YTD value is null.
     */
    private static void seedPrevDecValues(List<Workbook__c> scope) {
        Set<Id> prevYearIds = new Set<Id>();
        for (Workbook__c wb : scope) {
            if (wb.Previous_Year_Workbook__c != null) {
                prevYearIds.add(wb.Previous_Year_Workbook__c);
            }
        }

        Map<Id, Workbook__c> prevYearById = new Map<Id, Workbook__c>();
        if (!prevYearIds.isEmpty()) {
            for (Workbook__c prevWb : [
                SELECT Id,
                       YTD_Adjustment_Dec_1st__c,
                       YTD_Adjustment_Dec_2nd__c,
                       YTD_Adjustment_Dec_3rd__c
                FROM Workbook__c
                WHERE Id IN :prevYearIds
            ]) {
                prevYearById.put(prevWb.Id, prevWb);
            }
        }

        for (Workbook__c wb : scope) {
            Workbook__c prevWb = wb.Previous_Year_Workbook__c != null
                ? prevYearById.get(wb.Previous_Year_Workbook__c)
                : null;
            // WorkbookTriggerHandler.dec() normalises null → 0
            wb.YTD_Adjustment_Prev_Dec_1st__c = prevWb != null
                ? WorkbookTriggerHandler.dec(prevWb.YTD_Adjustment_Dec_1st__c) : 0;
            wb.YTD_Adjustment_Prev_Dec_2nd__c = prevWb != null
                ? WorkbookTriggerHandler.dec(prevWb.YTD_Adjustment_Dec_2nd__c) : 0;
            wb.YTD_Adjustment_Prev_Dec_3rd__c = prevWb != null
                ? WorkbookTriggerHandler.dec(prevWb.YTD_Adjustment_Dec_3rd__c) : 0;
        }
    }
}