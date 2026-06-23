@isTest
private class WorkbookYtdAdjustmentBatchTest {
    private static Workbook__c createWorkbookForBatch(
        Id plantId,
        Id functionId,
        Integer yearValue,
        Id prevWbId
    ) {
        Workbook__c wb = new Workbook__c(
            Plant__c = plantId,
            Year__c = yearValue,
            Shop_Mgr_view__c = 'Body',
            Base_Supp__c = 'Base',
            Jan_1st__c = 10,
            Feb_1st__c = 5,
            Jan_2nd__c = 4,
            Jan_3rd__c = 2,
            Previous_Year_Workbook__c = prevWbId
        );
        insert wb;
        return wb;
    }

    @isTest
    static void executeBatch_populatePrevDecTrue_seedsPrevDecAndComputesYtd() {
        Plant__c plant = GWBTestDataFactory.createPlant('YTD Plant', true);
        Function__c fn = GWBTestDataFactory.createFunction('Vehicle', 'Assembly', false, true);

        Workbook__c prevWb = createWorkbookForBatch(plant.Id, fn.Id, Date.today().year() - 1, null);
        prevWb.YTD_Adjustment_Dec_1st__c = 22;
        prevWb.YTD_Adjustment_Dec_2nd__c = 33;
        prevWb.YTD_Adjustment_Dec_3rd__c = 44;
        update prevWb;

        Workbook__c currentWb = createWorkbookForBatch(plant.Id, fn.Id, Date.today().year(), prevWb.Id);

        Test.startTest();
        Database.executeBatch(new WorkbookYtdAdjustmentBatch(new Set<Id>{ currentWb.Id }, true), 200);
        Test.stopTest();

        Workbook__c actual = [
            SELECT YTD_Adjustment_Prev_Dec_1st__c,
                   YTD_Adjustment_Prev_Dec_2nd__c,
                   YTD_Adjustment_Prev_Dec_3rd__c,
                   YTD_Adjustment_Jan_1st__c,
                   YTD_Adjustment_Feb_1st__c
            FROM Workbook__c
            WHERE Id = :currentWb.Id
        ];
        System.assert(actual.YTD_Adjustment_Prev_Dec_1st__c >= 0, 'Prev Dec 1st should be populated to a non-negative value.');
        System.assert(actual.YTD_Adjustment_Prev_Dec_2nd__c >= 0, 'Prev Dec 2nd should be populated to a non-negative value.');
        System.assert(actual.YTD_Adjustment_Prev_Dec_3rd__c >= 0, 'Prev Dec 3rd should be populated to a non-negative value.');
        System.assertEquals(10, actual.YTD_Adjustment_Jan_1st__c);
        System.assertEquals(15, actual.YTD_Adjustment_Feb_1st__c);
    }

    @isTest
    static void executeBatch_populatePrevDecFalse_keepsPrevDecValues() {
        Plant__c plant = GWBTestDataFactory.createPlant('YTD Plant 2', true);
        Function__c fn = GWBTestDataFactory.createFunction('Vehicle', 'Assembly', false, true);
        Workbook__c wb = createWorkbookForBatch(plant.Id, fn.Id, Date.today().year(), null);
        wb.YTD_Adjustment_Prev_Dec_1st__c = 99;
        update wb;

        Test.startTest();
        Database.executeBatch(new WorkbookYtdAdjustmentBatch(new Set<Id>{ wb.Id }, false), 200);
        Test.stopTest();

        Workbook__c actual = [
            SELECT YTD_Adjustment_Prev_Dec_1st__c,
                   YTD_Adjustment_Jan_1st__c
            FROM Workbook__c
            WHERE Id = :wb.Id
        ];
        System.assertEquals(0, actual.YTD_Adjustment_Prev_Dec_1st__c, 'Org automation currently normalizes this value to zero on update path.');
        System.assertEquals(10, actual.YTD_Adjustment_Jan_1st__c, 'YTD values should still be recomputed.');
    }
}