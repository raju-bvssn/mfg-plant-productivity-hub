@isTest
private class GWBConsolidatorBatchTest {
    private static Id getRecordTypeId(String sobjectType, String developerName) {
        return [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = :sobjectType
            AND DeveloperName = :developerName
            LIMIT 1
        ].Id;
    }

    private static Plant_Function__c createPlantFunctionForPlant(Id plantId) {
        Function__c fn = GWBTestDataFactory.createFunction('Vehicle', 'Assembly', false, true);
        Shop_Master__c shopMaster = GWBTestDataFactory.createShopMaster('Assembly', 'Vehicle', 'Body', true, true);
        Plant_Shop__c plantShop = GWBTestDataFactory.createPlantShop(plantId, shopMaster.Id, 'Assembly', 'Vehicle', 'Body', true);
        Plant_Program__c pp = GWBTestDataFactory.createPlantProgramForShop(plantShop.Id, 'A', true, 'CSS', true);
        Plant_Function__c pf = GWBTestDataFactory.createPlantFunction(fn.Id, pp.Id, 'PF_CON_' + String.valueOf(System.now().getTime()), true);
        pf.Plant__c = plantId;
        pf.Status__c = 'Active';
        pf.Shop_Manager_View__c = 'Body';
        update pf;
        return pf;
    }

    private static Workbook__c createWorkbook(
        Id wbRecordTypeId,
        Id plantId,
        Id plantFunctionId,
        Decimal yearValue
    ) {
        Workbook__c wb = new Workbook__c(
            RecordTypeId = wbRecordTypeId,
            Plant__c = plantId,
            Plant_Function__c = plantFunctionId,
            Year__c = yearValue,
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base',
            Shop_Mgr_view__c = 'Body',
            Exclude_From_GWB__c = false,
            Jan_1st__c = 1,
            Jan_2nd__c = 2,
            Jan_3rd__c = 3,
            Feb_1st__c = 4,
            Feb_2nd__c = 5,
            Feb_3rd__c = 6
        );
        insert wb;
        return wb;
    }

    @isTest
    static void executeBatch_withEmptyChangedWorkbookIds_returnsNoRows() {
        Integer beforeCount = [SELECT COUNT() FROM GWB_Consolidator__c];

        Test.startTest();
        Database.executeBatch(new GWBConsolidatorBatch(new Set<Id>()), 200);
        Test.stopTest();

        Integer afterCount = [SELECT COUNT() FROM GWB_Consolidator__c];
        System.assertEquals(beforeCount, afterCount, 'Empty changed-workbook set should not create consolidator rows.');
    }

    @isTest
    static void executeBatch_insertsAndUpdatesConsolidatorWithPrevDecSeed() {
        Id wbTargetsRt = getRecordTypeId('Workbook__c', 'Targets');
        Id conTargetRt = getRecordTypeId('GWB_Consolidator__c', 'Target');

        Plant__c plant = GWBTestDataFactory.createPlant('Consolidator Plant', true);
        Plant_Function__c pf = createPlantFunctionForPlant(plant.Id);
        Decimal planYear = Decimal.valueOf(Date.today().year());

        String decodedClass = ClassificationDecoder.toClassificationGroup('Direct OTS');
        if (String.isBlank(decodedClass)) {
            decodedClass = 'Direct OTS';
        }

        insert new GWB_Consolidator__c(
            RecordTypeId = conTargetRt,
            Plant__c = plant.Id,
            Plant_Function__c = pf.Id,
            Year__c = planYear - 1,
            Classification__c = decodedClass,
            Shop_Manager_View__c = 'Body',
            Base_Supp__c = 'Base',
            Exclude_From_GWB__c = false,
            Dec_Total__c = 25
        );

        Workbook__c wb = createWorkbook(wbTargetsRt, plant.Id, pf.Id, planYear);

        Test.startTest();
        Database.executeBatch(new GWBConsolidatorBatch(new Set<Id>{ wb.Id }), 200);
        Test.stopTest();

        GWB_Consolidator__c con = [
            SELECT Prev_Dec_Total__c, Jan_Total__c, Feb_Total__c, RecordTypeId, Plant_Function__c, Plant__c, Year__c
            FROM GWB_Consolidator__c
            WHERE RecordTypeId = :conTargetRt
            AND Plant_Function__c = :pf.Id
            AND Plant__c = :plant.Id
            AND Year__c = :planYear
            LIMIT 1
        ];
        System.assertEquals(25, con.Prev_Dec_Total__c, 'Prev Dec should seed from prior-year consolidator.');
        System.assertEquals(31, con.Jan_Total__c, 'Jan total should be Prev Dec (25) + Jan shifts (6).');
        System.assertEquals(46, con.Feb_Total__c, 'Feb total should continue running sum with Feb shifts (15).');

    }

    @isTest
    static void executeBatch_acceptsAdditionalGroupingSeeds() {
        Id wbTargetsRt = getRecordTypeId('Workbook__c', 'Targets');
        Plant__c plant = GWBTestDataFactory.createPlant('Seed Plant', true);
        Plant_Function__c pf = createPlantFunctionForPlant(plant.Id);
        Decimal planYear = Decimal.valueOf(Date.today().year());
        Workbook__c wb = createWorkbook(wbTargetsRt, plant.Id, pf.Id, planYear);

        GWBConsolidatorBatch.GroupingSeed seed = new GWBConsolidatorBatch.GroupingSeed();
        seed.plantFunctionId = pf.Id;
        seed.plantId = plant.Id;
        seed.year = planYear;
        seed.classification = 'Direct OTS';
        seed.shopMgrView = 'Body';
        seed.baseSupp = 'Base';
        seed.excludeFromGwb = false;
        seed.workbookRecordTypeId = wbTargetsRt;

        Test.startTest();
        Database.executeBatch(new GWBConsolidatorBatch(new Set<Id>{ wb.Id }, new List<GWBConsolidatorBatch.GroupingSeed>{ seed }), 200);
        Test.stopTest();

        System.assert(
            [SELECT COUNT() FROM GWB_Consolidator__c WHERE Plant_Function__c = :pf.Id AND Plant__c = :plant.Id AND Year__c = :planYear] > 0,
            'Batch should process when grouping seeds are supplied.'
        );
    }

    @isTest
    static void helperKeys_areStableWithNulls() {
        Id plantFunctionId = null;
        Id plantId = null;
        Decimal yearValue = null;
        String classification = null;
        String shopMgrView = null;
        String baseSupp = null;
        Boolean excludeFromGwb = null;
        Id conRecordTypeId = null;

        String g1 = GWBConsolidatorBatch.buildGroupKey(
            plantFunctionId,
            plantId,
            yearValue,
            classification,
            shopMgrView,
            baseSupp,
            excludeFromGwb,
            conRecordTypeId
        );
        String g2 = GWBConsolidatorBatch.buildGroupKey(
            plantFunctionId,
            plantId,
            yearValue,
            classification,
            shopMgrView,
            baseSupp,
            false,
            conRecordTypeId
        );
        System.assertEquals(g1, g2, 'Null/false values should normalize in group key builder.');

        String p1 = GWBConsolidatorBatch.buildPrevDecKey(
            plantFunctionId,
            plantId,
            classification,
            shopMgrView,
            baseSupp,
            excludeFromGwb,
            yearValue,
            conRecordTypeId
        );
        String p2 = GWBConsolidatorBatch.buildPrevDecKey(
            plantFunctionId,
            plantId,
            classification,
            shopMgrView,
            baseSupp,
            false,
            yearValue,
            conRecordTypeId
        );
        System.assertEquals(p1, p2, 'Null/false values should normalize in prev-dec key builder.');
    }
}