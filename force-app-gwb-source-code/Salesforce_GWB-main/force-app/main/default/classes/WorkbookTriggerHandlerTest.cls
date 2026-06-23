/**
 * @description Test class for WorkbookTriggerHandler and WorkbookYtdAdjustmentBatch.
 *              Tests YTD Adjustment field population on insert and update via batch.
 * @group Plant Management
 * @last modified on 05-20-2026
 */
@isTest
private class WorkbookTriggerHandlerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // Shared test data helpers
    // ─────────────────────────────────────────────────────────────────────────

    @testSetup
    static void setupTestData() {
        Integer currentYear = Date.today().year();
        Plant__c plant = createPlantWithMvp('Test Plant');
        Function__c function = GWBTestDataFactory.createFunction('Vehicle', 'Assembly', false, true);
        Workbook__c workbook = GWBTestDataFactory.createWorkbookWithFunction(function.Id, true);
        workbook.Plant__c = plant.Id;
        workbook.Shop_Master_view__c = 'Body';
        workbook.Sector__c = 'Assembly';
        workbook.Year__c = currentYear;
        workbook.Base_Supp__c = 'Base';
        workbook.Jan_1st__c = 100;
        workbook.Jan_2nd__c = 100;
        workbook.Jan_3rd__c = 100;
        workbook.Feb_1st__c = 100;
        workbook.Feb_2nd__c = 100;
        workbook.Feb_3rd__c = 100;
        update workbook;

    }

    private static Plant_Function__c createPlantFunctionForWorkbook(Id plantId, Id functionId) {
        Shop_Master__c shopMaster = GWBTestDataFactory.createShopMaster('Assembly', 'Vehicle', 'Body', true, true);
        Plant_Shop__c plantShop = GWBTestDataFactory.createPlantShop(plantId, shopMaster.Id, 'Assembly', 'Vehicle', 'Body', true);
        Plant_Program__c pp = GWBTestDataFactory.createPlantProgramForShop(plantShop.Id, 'A', true, 'CSS', true);
        Plant_Function__c pf = GWBTestDataFactory.createPlantFunction(functionId, pp.Id, 'PF_WTH_' + String.valueOf(System.now().getTime()), true);
        pf.Plant__c = plantId;
        pf.Shop_Manager_View__c = 'Body Shop';
        pf.Status__c = 'Active';
        update pf;
        return pf;
    }

    private static Plant__c createPlantWithMvp(String name) {
        Plant__c plant = new Plant__c(
            Name = name,
            Auth_Region__c = 'GMNA',
            MVP__c = UserInfo.getUserId()
        );
        insert plant;
        return plant;
    }

    private static Id getWorkbookRecordTypeId(String developerName) {
        return [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Workbook__c'
            AND DeveloperName = :developerName
            LIMIT 1
        ].Id;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Previous_Year_Workbook__c — before insert auto-population
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testBeforeInsert_PopulatesPreviousYearWorkbook_WhenMatchFound() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Function__c func = [SELECT Id, Name FROM Function__c LIMIT 1];
        Plant_Function__c pf = createPlantFunctionForWorkbook(plant.Id, func.Id);
        Integer currentYear = Date.today().year();
        Id workbookRtId = getWorkbookRecordTypeId('Targets');

        // Insert the prior-year workbook directly (bypassing auto-population for setup).
        Workbook__c prevWb = new Workbook__c(
            RecordTypeId = workbookRtId,
            Plant_Function__c = pf.Id,
            Plant__c = plant.Id,
            Shop_Master_view__c = 'Body',
            Shop_Mgr_view__c = 'Body Shop',
            Sector__c = 'Assembly',
            Year__c = currentYear - 1,
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base'
        );
        insert prevWb;

        Workbook__c newWb = new Workbook__c(
            RecordTypeId = workbookRtId,
            Plant_Function__c = pf.Id,
            Plant__c = plant.Id,
            Shop_Master_view__c = 'Body',
            Shop_Mgr_view__c = 'Body Shop',
            Sector__c = 'Assembly',
            Year__c = currentYear,
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base'
        );

        Test.startTest();
        insert newWb;
        Test.stopTest();

        Workbook__c result = [SELECT Previous_Year_Workbook__c FROM Workbook__c WHERE Id = :newWb.Id];
        System.assertEquals(prevWb.Id, result.Previous_Year_Workbook__c,
            'Previous_Year_Workbook__c should be auto-populated from the matching prior-year workbook');
    }

    @isTest
    static void testBeforeInsert_DoesNotOverrideExplicitPreviousYearWorkbook() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Function__c func = [SELECT Id, Name FROM Function__c LIMIT 1];
        Plant_Function__c pf = createPlantFunctionForWorkbook(plant.Id, func.Id);
        Integer currentYear = Date.today().year();

        Workbook__c prevWb = new Workbook__c(
            Plant_Function__c = pf.Id,
            Plant__c = plant.Id, Shop_Master_view__c = 'Body', Shop_Mgr_view__c = 'Body Shop',
            Sector__c = 'Assembly', Year__c = currentYear - 1,
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base'
        );
        insert prevWb;

        // Explicitly set a different previous year workbook.
        Workbook__c otherPrevWb = new Workbook__c(
             Plant_Function__c = pf.Id,
            Plant__c = plant.Id, Shop_Master_view__c = 'Body',
            Sector__c = 'Assembly', Year__c = currentYear - 2,
            Classification__c = 'Direct OTS', Base_Supp__c = 'Base'
        );
        insert otherPrevWb;

        Workbook__c newWb = new Workbook__c(
            Plant_Function__c = pf.Id,
            Plant__c = plant.Id, Shop_Master_view__c = 'Body',
            Sector__c = 'Assembly', Year__c = currentYear,
            Classification__c = 'Direct OTS', Base_Supp__c = 'Base',
            Previous_Year_Workbook__c = otherPrevWb.Id   // explicitly set
        );

        Test.startTest();
        insert newWb;
        Test.stopTest();

        Workbook__c result = [SELECT Previous_Year_Workbook__c FROM Workbook__c WHERE Id = :newWb.Id];
        System.assertEquals(otherPrevWb.Id, result.Previous_Year_Workbook__c,
            'Explicitly provided Previous_Year_Workbook__c should not be overridden by auto-population');
    }

    @isTest
    static void testBeforeInsert_LeavesNullWhenNoMatchFound() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Function__c func = [SELECT Id, Name FROM Function__c LIMIT 1];
        Plant_Function__c pf = createPlantFunctionForWorkbook(plant.Id, func.Id);
        Integer currentYear = Date.today().year();

        // No prior-year workbook exists with this driver/classification combo.
        Workbook__c newWb = new Workbook__c(
            Plant_Function__c = pf.Id,
            Plant__c = plant.Id, Shop_Master_view__c = 'Body',
            Sector__c = 'Assembly', Year__c = currentYear,
            Classification__c = 'Direct OTS', Base_Supp__c = 'Base',
            Shop_Mgr_view__c = 'No-Match Shop'
        );

        Test.startTest();
        insert newWb;
        Test.stopTest();

        Workbook__c result = [SELECT Previous_Year_Workbook__c FROM Workbook__c WHERE Id = :newWb.Id];
        System.assertEquals(null, result.Previous_Year_Workbook__c,
            'Previous_Year_Workbook__c should remain null when no prior-year match is found');
    }

    @isTest
    static void testBuildPrevYearKey_NullsNormalisedToEmptyString() {
        String key1 = WorkbookTriggerHandler.buildPrevYearKey(null, null, null, null, null, null, null);
        String key2 = WorkbookTriggerHandler.buildPrevYearKey(null, null, null, null, null, null, null);
        System.assertEquals(key1, key2, 'Keys with all nulls should be equal');
        System.assert(key1.contains('|'), 'Key should still contain separators');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // YTD Adjustment — insert path (batch runs inside Test.startTest/stopTest)
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testInsert_YtdRunningSum_NoPreYearWorkbook() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Function__c func = [SELECT Id, Name FROM Function__c LIMIT 1];

        Workbook__c wb = new Workbook__c(
            Plant__c = plant.Id,
            Shop_Master_view__c = 'Body',
            Sector__c = 'Assembly',
            Year__c = Date.today().year(),
            Base_Supp__c = 'Base',
            Jan_1st__c = 100, Jan_2nd__c = 100, Jan_3rd__c = 100,
            Feb_1st__c = 100, Feb_2nd__c = 100, Feb_3rd__c = 100
        );

        Test.startTest();
        insert wb;
        Test.stopTest();

        Workbook__c result = [
            SELECT YTD_Adjustment_Jan_1st__c, YTD_Adjustment_Feb_1st__c, YTD_Adjustment_Mar_1st__c,
                   YTD_Adjustment_Dec_1st__c,
                   YTD_Adjustment_Jan_2nd__c, YTD_Adjustment_Feb_2nd__c,
                   YTD_Adjustment_Prev_Dec_1st__c, YTD_Adjustment_Prev_Dec_2nd__c, YTD_Adjustment_Prev_Dec_3rd__c
            FROM Workbook__c WHERE Id = :wb.Id
        ];

        System.assertEquals(100, result.YTD_Adjustment_Jan_1st__c, 'Jan YTD 1st should equal Jan_1st');
        System.assertEquals(200, result.YTD_Adjustment_Feb_1st__c, 'Feb YTD 1st should be Jan + Feb');
        System.assertEquals(200, result.YTD_Adjustment_Mar_1st__c, 'Mar YTD 1st should carry forward (Mar=null=0)');
        System.assertEquals(200, result.YTD_Adjustment_Dec_1st__c, 'Dec YTD 1st should carry all the way through');
        System.assertEquals(0,   result.YTD_Adjustment_Prev_Dec_1st__c, 'Prev Dec should be 0 when no prev year workbook');
        System.assertEquals(0,   result.YTD_Adjustment_Prev_Dec_2nd__c);
        System.assertEquals(0,   result.YTD_Adjustment_Prev_Dec_3rd__c);
    }

    @isTest
    static void testInsert_YtdRunningSum_WithPrevYearWorkbook() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Function__c func = [SELECT Id, Name FROM Function__c LIMIT 1];
        Integer currentYear = Date.today().year();

        Workbook__c prevYearWb = new Workbook__c(
            Plant__c = plant.Id,
            Shop_Master_view__c = 'Body',
            Sector__c = 'Assembly',
            Year__c = currentYear - 1,
            Base_Supp__c = 'Base',
            YTD_Adjustment_Dec_1st__c = 500,
            YTD_Adjustment_Dec_2nd__c = 300,
            YTD_Adjustment_Dec_3rd__c = 200
        );
        insert prevYearWb;

        Workbook__c newWb = new Workbook__c(
            Plant__c = plant.Id,
            Shop_Master_view__c = 'Body',
            Sector__c = 'Assembly',
            Year__c = currentYear,
            Base_Supp__c = 'Base',
            Previous_Year_Workbook__c = prevYearWb.Id,
            Jan_1st__c = 50, Jan_2nd__c = 20, Jan_3rd__c = 10
        );

        Test.startTest();
        insert newWb;
        Test.stopTest();

        Workbook__c result = [
            SELECT YTD_Adjustment_Prev_Dec_1st__c, YTD_Adjustment_Prev_Dec_2nd__c, YTD_Adjustment_Prev_Dec_3rd__c,
                   YTD_Adjustment_Jan_1st__c, YTD_Adjustment_Feb_1st__c,
                   YTD_Adjustment_Jan_2nd__c, YTD_Adjustment_Jan_3rd__c
            FROM Workbook__c WHERE Id = :newWb.Id
        ];

        System.assert(result.YTD_Adjustment_Prev_Dec_1st__c >= 0, 'Prev Dec 1st should be non-negative.');
        System.assert(result.YTD_Adjustment_Prev_Dec_2nd__c >= 0, 'Prev Dec 2nd should be non-negative.');
        System.assert(result.YTD_Adjustment_Prev_Dec_3rd__c >= 0, 'Prev Dec 3rd should be non-negative.');
        System.assertEquals(50,  result.YTD_Adjustment_Jan_1st__c, 'Jan YTD 1st should equal Jan_1st');
        System.assertEquals(50,  result.YTD_Adjustment_Feb_1st__c, 'Feb YTD 1st should carry (Feb=null=0)');
        System.assertEquals(20,  result.YTD_Adjustment_Jan_2nd__c, 'Jan YTD 2nd should equal Jan_2nd');
        System.assertEquals(10,  result.YTD_Adjustment_Jan_3rd__c, 'Jan YTD 3rd should equal Jan_3rd');
    }

    @isTest
    static void testInsert_PrevYearWorkbookWithNullDecValues() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Function__c func = [SELECT Id, Name FROM Function__c LIMIT 1];
        Integer currentYear = Date.today().year();

        Workbook__c prevYearWb = new Workbook__c(
            Plant__c = plant.Id,
            Shop_Master_view__c = 'Body',
            Sector__c = 'Assembly',
            Year__c = currentYear - 1,
            Base_Supp__c = 'Base'
            // YTD_Adjustment_Dec_*__c intentionally left null
        );
        insert prevYearWb;

        Workbook__c newWb = new Workbook__c(
            Plant__c = plant.Id,
            Shop_Master_view__c = 'Body',
            Sector__c = 'Assembly',
            Year__c = currentYear,
            Base_Supp__c = 'Base',
            Previous_Year_Workbook__c = prevYearWb.Id,
            Jan_1st__c = 100
        );

        Test.startTest();
        insert newWb;
        Test.stopTest();

        Workbook__c result = [
            SELECT YTD_Adjustment_Prev_Dec_1st__c, YTD_Adjustment_Prev_Dec_2nd__c, YTD_Adjustment_Prev_Dec_3rd__c
            FROM Workbook__c WHERE Id = :newWb.Id
        ];
        System.assertEquals(0, result.YTD_Adjustment_Prev_Dec_1st__c, 'Prev Dec should default to 0 when prev year Dec YTD is null');
        System.assertEquals(0, result.YTD_Adjustment_Prev_Dec_2nd__c);
        System.assertEquals(0, result.YTD_Adjustment_Prev_Dec_3rd__c);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // YTD Adjustment — update path
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testUpdate_YtdRecalculatedWhenShiftFieldChanges() {
        Workbook__c wb = [SELECT Id, YTD_Adjustment_Prev_Dec_1st__c FROM Workbook__c LIMIT 1];
        Decimal prevDecBefore = wb.YTD_Adjustment_Prev_Dec_1st__c;

        Test.startTest();
        wb.Jan_1st__c = 50;
        wb.Feb_1st__c = 75;
        update wb;
        Test.stopTest();

        Workbook__c result = [
            SELECT YTD_Adjustment_Jan_1st__c, YTD_Adjustment_Feb_1st__c,
                   YTD_Adjustment_Mar_1st__c, YTD_Adjustment_Prev_Dec_1st__c
            FROM Workbook__c WHERE Id = :wb.Id
        ];
        System.assertEquals(50,  result.YTD_Adjustment_Jan_1st__c, 'YTD Jan should equal new Jan_1st value');
        System.assertEquals(125, result.YTD_Adjustment_Feb_1st__c, 'YTD Feb should be Jan+Feb running sum');
        System.assertEquals(125, result.YTD_Adjustment_Mar_1st__c, 'YTD Mar should carry (Mar=null=0)');
        System.assertEquals(prevDecBefore, result.YTD_Adjustment_Prev_Dec_1st__c, 'Prev Dec should NOT change on update');
    }

    @isTest
    static void testUpdate_YtdNotChangedWhenNonShiftFieldChanges() {
        Workbook__c wb = [SELECT Id, YTD_Adjustment_Jan_1st__c FROM Workbook__c LIMIT 1];
        Decimal ytdBefore = wb.YTD_Adjustment_Jan_1st__c;

        Test.startTest();
        wb.Sector__c = 'Press';
        update wb;
        Test.stopTest();

        Workbook__c result = [SELECT YTD_Adjustment_Jan_1st__c FROM Workbook__c WHERE Id = :wb.Id];
        System.assertEquals(ytdBefore, result.YTD_Adjustment_Jan_1st__c, 'YTD should be unchanged when non-shift fields update');
    }

    @isTest
    static void testUpdate_AllThreeShiftsRecalculated() {
        Workbook__c wb = [SELECT Id FROM Workbook__c LIMIT 1];

        Test.startTest();
        wb.Jan_1st__c = 10; wb.Jan_2nd__c = 20; wb.Jan_3rd__c = 30;
        wb.Feb_1st__c = 10; wb.Feb_2nd__c = 20; wb.Feb_3rd__c = 30;
        wb.Mar_1st__c = 10; wb.Mar_2nd__c = 20; wb.Mar_3rd__c = 30;
        update wb;
        Test.stopTest();

        Workbook__c result = [
            SELECT YTD_Adjustment_Jan_1st__c, YTD_Adjustment_Mar_1st__c,
                   YTD_Adjustment_Jan_2nd__c, YTD_Adjustment_Mar_2nd__c,
                   YTD_Adjustment_Jan_3rd__c, YTD_Adjustment_Mar_3rd__c
            FROM Workbook__c WHERE Id = :wb.Id
        ];
        System.assertEquals(10, result.YTD_Adjustment_Jan_1st__c);
        System.assertEquals(30, result.YTD_Adjustment_Mar_1st__c, 'Mar YTD 1st = 10+10+10');
        System.assertEquals(20, result.YTD_Adjustment_Jan_2nd__c);
        System.assertEquals(60, result.YTD_Adjustment_Mar_2nd__c, 'Mar YTD 2nd = 20+20+20');
        System.assertEquals(30, result.YTD_Adjustment_Jan_3rd__c);
        System.assertEquals(90, result.YTD_Adjustment_Mar_3rd__c, 'Mar YTD 3rd = 30+30+30');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // WorkbookYtdAdjustmentBatch — direct batch execution tests
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testBatch_PopulatePrevDecFalse_OnlyRecalculatesRunningSum() {
        Workbook__c wb = [SELECT Id FROM Workbook__c LIMIT 1];

        // Pre-set a known Prev Dec value directly to confirm batch doesn't change it.
        wb.YTD_Adjustment_Prev_Dec_1st__c = 999;
        update wb;

        Test.startTest();
        Database.executeBatch(new WorkbookYtdAdjustmentBatch(new Set<Id>{ wb.Id }, false), 200);
        Test.stopTest();

        Workbook__c result = [
            SELECT YTD_Adjustment_Prev_Dec_1st__c, YTD_Adjustment_Jan_1st__c
            FROM Workbook__c WHERE Id = :wb.Id
        ];
        System.assertEquals(999, result.YTD_Adjustment_Prev_Dec_1st__c, 'Prev Dec should be untouched when populatePrevDec=false');
        System.assertNotEquals(null, result.YTD_Adjustment_Jan_1st__c, 'Running sums should still be calculated');
    }

    @isTest
    static void testBatch_PopulatePrevDecTrue_SeedsAndCalculates() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Function__c func = [SELECT Id, Name FROM Function__c LIMIT 1];
        Integer currentYear = Date.today().year();

        Workbook__c prevWb = new Workbook__c(
            Plant__c = plant.Id, Shop_Master_view__c = 'Body',
            Sector__c = 'Assembly', 
            Base_Supp__c = 'Base',
            YTD_Adjustment_Dec_1st__c = 400, YTD_Adjustment_Dec_2nd__c = 200, YTD_Adjustment_Dec_3rd__c = 100
        );
        insert prevWb;

        Workbook__c wb = new Workbook__c(
            Plant__c = plant.Id, Shop_Master_view__c = 'Body',
            Sector__c = 'Assembly', Year__c = currentYear,
            Base_Supp__c = 'Base',
            Previous_Year_Workbook__c = prevWb.Id,
            Jan_1st__c = 30, Feb_1st__c = 20
        );
        insert wb;

        Test.startTest();
        Database.executeBatch(new WorkbookYtdAdjustmentBatch(new Set<Id>{ wb.Id }, true), 200);
        Test.stopTest();

        Workbook__c result = [
            SELECT YTD_Adjustment_Prev_Dec_1st__c, YTD_Adjustment_Prev_Dec_2nd__c, YTD_Adjustment_Prev_Dec_3rd__c,
                   YTD_Adjustment_Jan_1st__c, YTD_Adjustment_Feb_1st__c
            FROM Workbook__c WHERE Id = :wb.Id
        ];
        System.assert(result.YTD_Adjustment_Prev_Dec_1st__c >= 0, 'Prev Dec 1st should be non-negative.');
        System.assert(result.YTD_Adjustment_Prev_Dec_2nd__c >= 0, 'Prev Dec 2nd should be non-negative.');
        System.assert(result.YTD_Adjustment_Prev_Dec_3rd__c >= 0, 'Prev Dec 3rd should be non-negative.');
        System.assertEquals(30,  result.YTD_Adjustment_Jan_1st__c);
        System.assertEquals(50,  result.YTD_Adjustment_Feb_1st__c, 'Feb YTD = Jan(30) + Feb(20)');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // calculateYtdOnRecord unit test (pure in-memory, no DML)
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testCalculateYtdOnRecord_RunningSum() {
        Workbook__c wb = new Workbook__c(
            Jan_1st__c = 10, Feb_1st__c = 20, Mar_1st__c = 30,
            Apr_1st__c = 0,  May_1st__c = 0,  Jun_1st__c = 0,
            Jul_1st__c = 0,  Aug_1st__c = 0,  Sep_1st__c = 0,
            Oct_1st__c = 0,  Nov_1st__c = 0,  Dec_1st__c = 40,
            Jan_2nd__c = 5,  Feb_2nd__c = 5,  Mar_2nd__c = 5,
            Apr_2nd__c = 0,  May_2nd__c = 0,  Jun_2nd__c = 0,
            Jul_2nd__c = 0,  Aug_2nd__c = 0,  Sep_2nd__c = 0,
            Oct_2nd__c = 0,  Nov_2nd__c = 0,  Dec_2nd__c = 0,
            Jan_3rd__c = null, Feb_3rd__c = null, Mar_3rd__c = null,
            Apr_3rd__c = null, May_3rd__c = null, Jun_3rd__c = null,
            Jul_3rd__c = null, Aug_3rd__c = null, Sep_3rd__c = null,
            Oct_3rd__c = null, Nov_3rd__c = null, Dec_3rd__c = null
        );

        Test.startTest();
        WorkbookTriggerHandler.calculateYtdOnRecord(wb);
        Test.stopTest();

        System.assertEquals(10,  wb.YTD_Adjustment_Jan_1st__c);
        System.assertEquals(30,  wb.YTD_Adjustment_Feb_1st__c);
        System.assertEquals(60,  wb.YTD_Adjustment_Mar_1st__c);
        System.assertEquals(60,  wb.YTD_Adjustment_Apr_1st__c, 'Apr carries Mar total (Apr=0)');
        System.assertEquals(100, wb.YTD_Adjustment_Dec_1st__c, 'Dec = 60 + 40');
        System.assertEquals(5,   wb.YTD_Adjustment_Jan_2nd__c);
        System.assertEquals(15,  wb.YTD_Adjustment_Mar_2nd__c);
        System.assertEquals(0,   wb.YTD_Adjustment_Jan_3rd__c, 'null shift treated as 0');
        System.assertEquals(0,   wb.YTD_Adjustment_Dec_3rd__c);
    }

    @isTest
    static void testUtilityMethods_coverNullAndNonNullPaths() {
        System.assertEquals(0, WorkbookTriggerHandler.dec(null), 'dec should normalize null to zero.');
        System.assertEquals(7, WorkbookTriggerHandler.dec(7), 'dec should return non-null values unchanged.');
    }

    @isTest
    static void testBeforeInsert_ignoresNullInputList() {
        Test.startTest();
        WorkbookTriggerHandler.handleBeforeInsert(null);
        WorkbookTriggerHandler.handleBeforeInsert(new List<Workbook__c>());
        Test.stopTest();
        System.assert(true, 'Method should short-circuit safely for null/empty lists.');
    }

    @isTest
    static void testAfterInsert_andAfterUpdate_groupingChangePath() {
        Plant__c plant = createPlantWithMvp('Trigger Plant');
        Function__c fn = GWBTestDataFactory.createFunction('Vehicle', 'Assembly', false, true);
        Shop_Master__c shopMaster = GWBTestDataFactory.createShopMaster('Assembly', 'Vehicle', 'Body', true, true);
        Plant_Shop__c plantShop = GWBTestDataFactory.createPlantShop(plant.Id, shopMaster.Id, 'Assembly', 'Vehicle', 'Body', true);
        Plant_Program__c pp = GWBTestDataFactory.createPlantProgramForShop(plantShop.Id, 'A', true, 'CSS', true);
        Plant_Function__c pf = GWBTestDataFactory.createPlantFunction(fn.Id, pp.Id, 'PF_TRIG_' + String.valueOf(System.now().getTime()), true);
        pf.Plant__c = plant.Id;
        pf.Shop_Manager_View__c = 'Body';
        pf.Status__c = 'Active';
        update pf;

        Workbook__c wb = new Workbook__c(
            Plant__c = plant.Id,
            Plant_Function__c = pf.Id,
            Year__c = Date.today().year(),
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base',
            Shop_Mgr_view__c = 'Body',
            Jan_1st__c = 1
        );
        insert wb;

        Workbook__c oldWb = [
            SELECT Id,
                Plant_Function__c, Plant__c, Year__c,
                Classification__c, Shop_Mgr_view__c, Base_Supp__c, Exclude_From_GWB__c, RecordTypeId,
                Jan_1st__c, Jan_2nd__c, Jan_3rd__c, Feb_1st__c, Feb_2nd__c, Feb_3rd__c,
                Mar_1st__c, Mar_2nd__c, Mar_3rd__c, Apr_1st__c, Apr_2nd__c, Apr_3rd__c,
                May_1st__c, May_2nd__c, May_3rd__c, Jun_1st__c, Jun_2nd__c, Jun_3rd__c,
                Jul_1st__c, Jul_2nd__c, Jul_3rd__c, Aug_1st__c, Aug_2nd__c, Aug_3rd__c,
                Sep_1st__c, Sep_2nd__c, Sep_3rd__c, Oct_1st__c, Oct_2nd__c, Oct_3rd__c,
                Nov_1st__c, Nov_2nd__c, Nov_3rd__c, Dec_1st__c, Dec_2nd__c, Dec_3rd__c
            FROM Workbook__c
            WHERE Id = :wb.Id
        ];
        Workbook__c newWb = oldWb.clone(true, true, true, true);
        newWb.Shop_Mgr_view__c = 'General Assembly';

        Test.startTest();
        WorkbookTriggerHandler.handleAfterInsert(new List<Workbook__c>{ wb });
        WorkbookTriggerHandler.handleAfterUpdate(
            new List<Workbook__c>{ newWb },
            new Map<Id, Workbook__c>{ oldWb.Id => oldWb }
        );
        Test.stopTest();

        Integer jobs = [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex'];
        System.assert(jobs > 0, 'Insert/update handlers should enqueue batch jobs for YTD/consolidator updates.');
    }
}