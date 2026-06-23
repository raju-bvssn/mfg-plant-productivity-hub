@isTest
private class ProdPlanSummaryCntrlTest {
    private static String getConsolidatorClassificationValue() {
        return GWB_Consolidator__c.Classification__c.getDescribe().getPicklistValues()[0].getValue();
    }

    private static Plant_Program__c createPlantProgramForPlant(Id plantId) {
        Shop_Master__c shopMaster = GWBTestDataFactory.createShopMaster('Assembly', 'Vehicle', 'All', true, true);
        Plant_Shop__c plantShop = GWBTestDataFactory.createPlantShop(
            plantId,
            shopMaster.Id,
            'Assembly',
            'Vehicle',
            'All',
            true
        );
        return GWBTestDataFactory.createPlantProgramForShop(plantShop.Id, 'A', true, 'CSS', true);
    }

    private static Id getRecordTypeId(String sobjectType, String developerName) {
        return [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = :sobjectType
            AND DeveloperName = :developerName
            LIMIT 1
        ].Id;
    }

    private static Workbook__c makeWorkbook(
        Id rtId,
        Id plantId,
        Id functionId,
        Decimal yearValue,
        Decimal monthValue
    ) {
        Workbook__c wb = new Workbook__c(
            RecordTypeId = rtId,
            Plant__c = plantId,
            Year__c = yearValue,
            Shop_Mgr_view__c = 'Body',
            Base_Supp__c = 'Base',
            Exclude_From_GWB__c = false,
            Jan_1st__c = monthValue,
            Jan_2nd__c = monthValue,
            Jan_3rd__c = monthValue,
            Dec_1st__c = monthValue,
            Dec_2nd__c = monthValue,
            Dec_3rd__c = monthValue,
            YTD_Adjustment_Prev_Dec_1st__c = monthValue,
            YTD_Adjustment_Prev_Dec_2nd__c = monthValue,
            YTD_Adjustment_Prev_Dec_3rd__c = monthValue,
            YTD_Adjustment_Jan_1st__c = monthValue,
            YTD_Adjustment_Jan_2nd__c = monthValue,
            YTD_Adjustment_Jan_3rd__c = monthValue
        );
        insert wb;
        return wb;
    }

    private static void createConsolidator(
        Id rtId,
        Id plantId,
        Id plantFunctionId,
        Decimal yearValue,
        Decimal prevDec
    ) {
        insert new GWB_Consolidator__c(
            RecordTypeId = rtId,
            Plant__c = plantId,
            Plant_Function__c = plantFunctionId,
            Year__c = yearValue,
            Classification__c = getConsolidatorClassificationValue(),
            Shop_Manager_View__c = 'Body',
            Base_Supp__c = 'Base',
            Exclude_From_GWB__c = false,
            Prev_Dec_Total__c = prevDec
        );
    }

    @isTest
    static void getSummaryData_nullFilters_returnsEmptyList() {
        List<ProdPlanSummaryCntrl.SummaryRow> rows = ProdPlanSummaryCntrl.getSummaryData(null);
        System.assertEquals(0, rows.size(), 'Null filters should return an empty list.');
    }

    @isTest
    static void getSummaryData_pastYear_usesActualsForMonthlyRows() {
        Id wbTargetsRt = getRecordTypeId('Workbook__c', 'Targets');
        Id wbActualsRt = getRecordTypeId('Workbook__c', 'Actuals');
        Id wbForecastRt = getRecordTypeId('Workbook__c', 'Forecast');
        Id conTargetRt = getRecordTypeId('GWB_Consolidator__c', 'Target');
        Id conActualRt = getRecordTypeId('GWB_Consolidator__c', 'Actual');

        Plant__c plant = GWBTestDataFactory.createPlant('Summary Plant', true);
        Function__c fn = GWBTestDataFactory.createFunction('Vehicle', 'Assembly', false, true);
        Plant_Program__c pp = createPlantProgramForPlant(plant.Id);
        Plant_Function__c pf = GWBTestDataFactory.createPlantFunction(fn.Id, pp.Id, 'PF_SUM', true);
        pf.Plant__c = plant.Id;
        pf.Shop_Manager_View__c = 'Body';
        update pf;

        Decimal planYear = Decimal.valueOf(Date.today().year() - 1);
        makeWorkbook(wbTargetsRt, plant.Id, fn.Id, planYear, 1);
        makeWorkbook(wbActualsRt, plant.Id, fn.Id, planYear, 2);
        makeWorkbook(wbForecastRt, plant.Id, fn.Id, planYear, 4);

        createConsolidator(conTargetRt, plant.Id, pf.Id, planYear, 10);
        createConsolidator(conActualRt, plant.Id, pf.Id, planYear, 20);

        ProdPlanSummaryCntrl.AppliedFilterWrapper filters = new ProdPlanSummaryCntrl.AppliedFilterWrapper();
        filters.plant = String.valueOf(plant.Id);
        filters.shop = 'Body';
        filters.year = String.valueOf(planYear.intValue());
        filters.classification = 'All';
        filters.driver = 'All';
        filters.baseSupp = 'Base';
        filters.excludeFromGWB = 'No';

        List<ProdPlanSummaryCntrl.SummaryRow> rows = ProdPlanSummaryCntrl.getSummaryData(filters);
        System.assertEquals(9, rows.size(), 'Controller should always return 9 summary rows.');
        System.assertEquals(2, rows[4].primaryHeaderPlacementColumn, 'Past-year view should anchor Actuals at first data column.');
        System.assertEquals(15, rows[4].secondaryHeaderPlacementColumn, 'Past-year view should push Forecast outside visible columns.');
        System.assertEquals(10, rows[1].previousYearDecAdjustment, 'Target prev-dec should come from Target consolidator.');
        System.assertEquals(20, rows[5].previousYearDecAdjustment, 'Actual prev-dec should come from Actual consolidator.');
        System.assertEquals(6, rows[6].currentYearJanAdjustment, 'Past-year monthly adjustments should use Actuals workbook totals.');
    }

    @isTest
    static void getSummaryData_futureYear_usesForecastForMonthlyRows() {
        Id wbTargetsRt = getRecordTypeId('Workbook__c', 'Targets');
        Id wbActualsRt = getRecordTypeId('Workbook__c', 'Actuals');
        Id wbForecastRt = getRecordTypeId('Workbook__c', 'Forecast');
        Id conTargetRt = getRecordTypeId('GWB_Consolidator__c', 'Target');
        Id conActualRt = getRecordTypeId('GWB_Consolidator__c', 'Actual');

        Plant__c plant = GWBTestDataFactory.createPlant('Summary Plant 2', true);
        Function__c fn = GWBTestDataFactory.createFunction('Vehicle', 'Assembly', false, true);
        Plant_Program__c pp = createPlantProgramForPlant(plant.Id);
        Plant_Function__c pf = GWBTestDataFactory.createPlantFunction(fn.Id, pp.Id, 'PF_SUM_2', true);
        pf.Plant__c = plant.Id;
        pf.Shop_Manager_View__c = 'Body';
        update pf;

        Decimal planYear = Decimal.valueOf(Date.today().year() + 1);
        makeWorkbook(wbTargetsRt, plant.Id, fn.Id, planYear, 1);
        makeWorkbook(wbActualsRt, plant.Id, fn.Id, planYear, 2);
        makeWorkbook(wbForecastRt, plant.Id, fn.Id, planYear, 4);

        createConsolidator(conTargetRt, plant.Id, pf.Id, planYear, 10);
        createConsolidator(conActualRt, plant.Id, pf.Id, planYear, 20);

        ProdPlanSummaryCntrl.AppliedFilterWrapper filters = new ProdPlanSummaryCntrl.AppliedFilterWrapper();
        filters.plant = String.valueOf(plant.Id);
        filters.shop = 'Body';
        filters.year = String.valueOf(planYear.intValue());
        filters.classification = 'Unknown Test Classification';
        filters.driver = 'All';
        filters.baseSupp = 'Base';
        filters.excludeFromGWB = 'No';

        List<ProdPlanSummaryCntrl.SummaryRow> rows = ProdPlanSummaryCntrl.getSummaryData(filters);
        System.assertEquals(9, rows.size());
        System.assertEquals(null, rows[4].primaryHeaderPlacementColumn, 'Future-year view should not place an Actuals header.');
        System.assertEquals(2, rows[4].secondaryHeaderPlacementColumn, 'Future-year view should place Forecast at first data column.');
        System.assertEquals(0, rows[6].currentYearJanAdjustment, 'Unknown classification filter should safely return no matching monthly data.');
    }
}