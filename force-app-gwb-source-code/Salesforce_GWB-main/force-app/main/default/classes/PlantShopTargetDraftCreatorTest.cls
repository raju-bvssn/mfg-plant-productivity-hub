@IsTest
private class PlantShopTargetDraftCreatorTest {
    @TestSetup
    static void setupValidationBypass() {
        Schema.SObjectType bypassSettingType = Schema.getGlobalDescribe().get('Onstar_Switch__c');
        if (bypassSettingType == null) {
            return;
        }
        SObject bypassSetting = bypassSettingType.newSObject();
        bypassSetting.put('SetupOwnerId', UserInfo.getUserId());
        bypassSetting.put('Bypass_VRs__c', true);
        insert bypassSetting;
    }

    @IsTest
    static void createDraftPlantShopTargetsCreatesDraftTargetsAndItems() {
        Plant__c plant = createPlantWithMvp('Draft Creator Create Plant');
        GWB_Year__c gwbYear = GWBTestDataFactory.createGwbYearTarget(plant.Id, '2028', 'Draft', true);
        createPlantFunction(plant.Id, 'Direct OTS', 'Base', 'Body');
        createPlantFunction(plant.Id, 'Indirect Skilled', 'Base', 'Paint');
        createPlantFunction(plant.Id, 'Direct OTS', 'Supp', 'Supp Should Not Match');
        createPlantFunction(plant.Id, 'Direct OTS', 'Base', null);

        insert new List<GWB_Month__c>{
            createMonth(gwbYear.Id, plant.Id, '2028', 'Productivity', 'OTS', 'Jan_Number__c', -10),
            createMonth(gwbYear.Id, plant.Id, '2028', 'LMS', 'Skilled', 'Apr_Decimal__c', 2.5),
            createMonth(gwbYear.Id, plant.Id, '2028', 'Mfg Opt', 'Salaried', 'May_Number__c', 0)
        };

        Test.startTest();
        PlantShopTargetDraftCreator.createDraftPlantShopTargets(new Set<Id>{ gwbYear.Id });
        Test.stopTest();

        Map<String, Plant_Shop_Target__c> targetsByKey = getTargetsByKey(gwbYear.Id);
        System.assertEquals(2, targetsByKey.size(), 'Only non-zero monthly values should create draft targets.');
        System.assertEquals(-10, targetsByKey.get('January-Productivity-OTS').Total_Changes_Needed__c);
        System.assertEquals(2.5, targetsByKey.get('April-LMS-Skilled').Total_Changes_Needed__c);
        System.assertEquals('Draft', targetsByKey.get('January-Productivity-OTS').Status__c);
        System.assertEquals(2028, targetsByKey.get('January-Productivity-OTS').Year__c);

        Set<Id> targetIds = new Map<Id, Plant_Shop_Target__c>(targetsByKey.values()).keySet();
        List<Plant_Shop_Target_Item__c> items = [
            SELECT Plant_Shop_Target__c, Shop_Manager_View__c, Adjustment__c
            FROM Plant_Shop_Target_Item__c
            WHERE Plant_Shop_Target__c IN :targetIds
        ];
        System.assertEquals(2, items.size(), 'One matching active plant function should create one item per target.');
        assertItemExists(items, targetsByKey.get('January-Productivity-OTS').Id, 'Body');
        assertItemExists(items, targetsByKey.get('April-LMS-Skilled').Id, 'Paint');
    }

    @IsTest
    static void createDraftPlantShopTargetsContinuesWhenRowBudgetIsReached() {
        Plant__c plant = createPlantWithMvp('Draft Creator Chunk Plant');
        GWB_Year__c gwbYear = GWBTestDataFactory.createGwbYearTarget(plant.Id, '2028', 'Draft', true);
        createPlantFunction(plant.Id, 'Direct OTS', 'Base', 'Body');

        GWB_Month__c monthRecord = createMonth(gwbYear.Id, plant.Id, '2028', 'Productivity', 'OTS', 'Jan_Number__c', -10);
        monthRecord.Feb_Number__c = -8;
        insert monthRecord;

        Test.startTest();
        PlantShopTargetDraftCreator.dmlRowBudget = 2;
        PlantShopTargetDraftCreator.createDraftPlantShopTargets(new Set<Id>{ gwbYear.Id });

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Plant_Shop_Target__c WHERE Target__c = :gwbYear.Id],
            'Only one parent and one child should fit in the first two-row chunk.'
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Plant_Shop_Target_Item__c
                WHERE Plant_Shop_Target__r.Target__c = :gwbYear.Id
            ],
            'Only the first chunk item should be inserted before the continuation runs.'
        );

        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM Plant_Shop_Target__c WHERE Target__c = :gwbYear.Id]);
        System.assertEquals(
            2,
            [
                SELECT COUNT()
                FROM Plant_Shop_Target_Item__c
                WHERE Plant_Shop_Target__r.Target__c = :gwbYear.Id
            ]
        );
    }

    @IsTest
    static void createDraftPlantShopTargetsUsesExistingDraftAndAddsMissingItems() {
        Plant__c plant = createPlantWithMvp('Draft Creator Existing Plant');
        GWB_Year__c gwbYear = GWBTestDataFactory.createGwbYearTarget(plant.Id, '2028', 'Draft', true);
        createPlantFunction(plant.Id, 'Direct OTS', 'Base', 'Body');
        createPlantFunction(plant.Id, 'Indirect OTS', 'Base', 'Trim');
        insert createMonth(gwbYear.Id, plant.Id, '2028', 'Productivity', 'OTS', 'Jan_Number__c', -12);

        Plant_Shop_Target__c existingTarget = GWBTestDataFactory.createPlantShopTarget(
            gwbYear.Id,
            plant.Id,
            2028,
            'January',
            'Productivity',
            'OTS',
            -99,
            'Draft',
            true
        );
        GWBTestDataFactory.createPlantShopTargetItem(existingTarget.Id, 'Body', -4, true);

        Test.startTest();
        PlantShopTargetDraftCreator.createDraftPlantShopTargets(new Set<Id>{ gwbYear.Id });
        Test.stopTest();

        List<Plant_Shop_Target__c> targets = [
            SELECT Id, Total_Changes_Needed__c
            FROM Plant_Shop_Target__c
            WHERE Target__c = :gwbYear.Id
        ];
        System.assertEquals(1, targets.size(), 'The matching draft target should be reused.');
        System.assertEquals(-99, targets[0].Total_Changes_Needed__c, 'Existing draft parent values should not be overwritten.');

        List<Plant_Shop_Target_Item__c> items = [
            SELECT Plant_Shop_Target__c, Shop_Manager_View__c, Adjustment__c
            FROM Plant_Shop_Target_Item__c
            WHERE Plant_Shop_Target__c = :existingTarget.Id
            ORDER BY Shop_Manager_View__c
        ];
        System.assertEquals(2, items.size(), 'Only the missing shop manager view should be added.');
        System.assertEquals('Body', items[0].Shop_Manager_View__c);
        System.assertEquals(-4, items[0].Adjustment__c);
        System.assertEquals('Trim', items[1].Shop_Manager_View__c);
        System.assertEquals(0, items[1].Adjustment__c);
    }

    @IsTest
    static void createDraftPlantShopTargetsSkipsInvalidGroups() {
        Plant__c plant = createPlantWithMvp('Draft Creator Invalid Plant');
        GWB_Year__c gwbYear = GWBTestDataFactory.createGwbYearTarget(plant.Id, '2028', 'Draft', true);
        insert createMonth(gwbYear.Id, plant.Id, '2028', 'Mfg Opt', 'Salaried', 'May_Number__c', 0);

        Test.startTest();
        PlantShopTargetDraftCreator.createDraftPlantShopTargets(new Set<Id>{ gwbYear.Id });
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Plant_Shop_Target__c WHERE Target__c = :gwbYear.Id],
            'Zero monthly values should not create targets.'
        );
    }

    @IsTest
    static void createDraftPlantShopTargetsSkipsYearWithoutPlant() {
        Plant__c plant = createPlantWithMvp('Draft Creator Missing Plant Source');
        GWB_Year__c deletedYear = GWBTestDataFactory.createGwbYearTarget(plant.Id, '2028', 'Draft', true);
        delete deletedYear;

        Test.startTest();
        PlantShopTargetDraftCreator.createDraftPlantShopTargets(new Set<Id>{ deletedYear.Id });
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Plant_Shop_Target__c WHERE Target__c = :deletedYear.Id],
            'A deleted year id should not produce target groups.'
        );
    }

    @IsTest
    static void createDraftPlantShopTargetsCreatesParentWithoutItemsWhenTypeIsBlank() {
        Plant__c plant = createPlantWithMvp('Draft Creator Blank Type Plant');
        GWB_Year__c gwbYear = GWBTestDataFactory.createGwbYearTarget(plant.Id, '2028', 'Draft', true);
        gwbYear.Type__c = null;
        update gwbYear;
        insert createMonth(gwbYear.Id, plant.Id, '2028', 'Productivity', 'OTS', 'Jan_Number__c', -7);

        Test.startTest();
        PlantShopTargetDraftCreator.createDraftPlantShopTargets(new Set<Id>{ gwbYear.Id });
        Test.stopTest();

        Plant_Shop_Target__c target = [
            SELECT Id, Year__c, Total_Changes_Needed__c
            FROM Plant_Shop_Target__c
            WHERE Target__c = :gwbYear.Id
            LIMIT 1
        ];
        System.assertEquals(2028, target.Year__c);
        System.assertEquals(-7, target.Total_Changes_Needed__c);
        System.assertEquals(0, [SELECT COUNT() FROM Plant_Shop_Target_Item__c WHERE Plant_Shop_Target__c = :target.Id]);
    }

    @IsTest
    static void createDraftPlantShopTargetsNoOpsForEmptyInput() {
        Test.startTest();
        PlantShopTargetDraftCreator.createDraftPlantShopTargets(null);
        PlantShopTargetDraftCreator.createDraftPlantShopTargets(new Set<Id>());
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Plant_Shop_Target__c]);
    }

    private static GWB_Month__c createMonth(
        Id gwbYearId,
        Id plantId,
        String year,
        String driver,
        String classification,
        String valueField,
        Decimal value
    ) {
        GWB_Month__c monthRecord = new GWB_Month__c(
            GWB_Year__c = gwbYearId,
            Plant__c = plantId,
            Sector__c = 'Assembly',
            Year__c = year,
            Driver__c = driver,
            Classification__c = classification
        );
        monthRecord.put(valueField, value);
        return monthRecord;
    }

    private static Plant__c createPlantWithMvp(String name) {
        Plant__c plant = GWBTestDataFactory.createPlant(name, false);
        plant.MVP__c = UserInfo.getUserId();
        insert plant;
        return plant;
    }

    private static Plant_Function__c createPlantFunction(
        Id plantId,
        String classification,
        String baseSupp,
        String shopManagerView
    ) {
        Function__c func = GWBTestDataFactory.createFunction('Vehicle', 'Assembly', true, true);
        func.Classification__c = classification;
        func.Base_Supp__c = baseSupp;
        update func;

        List<Plant_Program__c> existingPrograms = [
            SELECT Id
            FROM Plant_Program__c
            WHERE Auth_Plant_Name__c = :plantId
            LIMIT 1
        ];
        Plant_Program__c plantProgram;
        if (!existingPrograms.isEmpty()) {
            plantProgram = existingPrograms[0];
        } else {
            plantProgram = new Plant_Program__c(Auth_Plant_Name__c = plantId);
            insert plantProgram;
        }

        Plant_Function__c plantFunction = GWBTestDataFactory.createPlantFunction(
            func.Id,
            plantProgram.Id,
            'PST_CREATOR_' + String.valueOf(Crypto.getRandomInteger()),
            false
        );
        plantFunction.Plant__c = plantId;
        plantFunction.Status__c = 'Active';
        plantFunction.Shop_Manager_View__c = shopManagerView;
        insert plantFunction;
        return plantFunction;
    }

    private static Map<String, Plant_Shop_Target__c> getTargetsByKey(Id gwbYearId) {
        Map<String, Plant_Shop_Target__c> targetsByKey = new Map<String, Plant_Shop_Target__c>();
        for (Plant_Shop_Target__c target : [
            SELECT Id, Year__c, Month__c, Driver__c, Classification__c, Total_Changes_Needed__c, Status__c
            FROM Plant_Shop_Target__c
            WHERE Target__c = :gwbYearId
        ]) {
            targetsByKey.put(target.Month__c + '-' + target.Driver__c + '-' + target.Classification__c, target);
        }
        return targetsByKey;
    }

    private static void assertItemExists(List<Plant_Shop_Target_Item__c> items, Id targetId, String shopManagerView) {
        for (Plant_Shop_Target_Item__c item : items) {
            if (item.Plant_Shop_Target__c == targetId && item.Shop_Manager_View__c == shopManagerView) {
                System.assertEquals(0, item.Adjustment__c);
                return;
            }
        }
        System.assert(false, 'Expected item for shop manager view ' + shopManagerView);
    }

}