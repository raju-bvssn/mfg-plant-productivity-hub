@IsTest
private class GWBYearTriggerHandlerTest {
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
    static void createPlantShopTargetsForPublishedYearsCreatesDraftTargetsAndItems() {
        Plant__c plant = createPlantWithMvp('Trigger Handler Create Plant');
        GWB_Year__c gwbYear = GWBTestDataFactory.createGwbYearTarget(plant.Id, '2028', 'Draft', true);
        gwbYear.Status__c = 'Published';
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
        GWBYearTriggerHandler.createPlantShopTargetsForPublishedYears(
            new List<GWB_Year__c>{ gwbYear },
            oldYearMap(new List<GWB_Year__c>{ gwbYear }, 'Draft')
        );
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
    static void createPlantShopTargetsForPublishedYearsUsesExistingDraftAndAddsMissingItems() {
        Plant__c plant = createPlantWithMvp('Trigger Handler Existing Plant');
        GWB_Year__c gwbYear = GWBTestDataFactory.createGwbYearTarget(plant.Id, '2028', 'Draft', true);
        gwbYear.Status__c = 'Published';
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
        GWBYearTriggerHandler.createPlantShopTargetsForPublishedYears(
            new List<GWB_Year__c>{ gwbYear },
            oldYearMap(new List<GWB_Year__c>{ gwbYear }, 'Draft')
        );
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
    static void createPlantShopTargetsForPublishedYearsSkipsUnchangedAndInvalidGroups() {
        Plant__c publishedPlant = createPlantWithMvp('Trigger Handler Already Published Plant');
        Plant__c draftPlant = createPlantWithMvp('Trigger Handler Draft Plant');
        GWB_Year__c alreadyPublishedYear = GWBTestDataFactory.createGwbYearTarget(publishedPlant.Id, '2028', 'Draft', true);
        GWB_Year__c draftYear = GWBTestDataFactory.createGwbYearTarget(draftPlant.Id, '2028', 'Draft', true);
        alreadyPublishedYear.Status__c = 'Published';
        insert new List<GWB_Month__c>{
            createMonth(alreadyPublishedYear.Id, publishedPlant.Id, '2028', 'Productivity', 'OTS', 'Jan_Number__c', -10),
            createMonth(draftYear.Id, draftPlant.Id, '2028', 'Productivity', 'OTS', 'Jan_Number__c', -10)
        };

        Test.startTest();
        GWBYearTriggerHandler.createPlantShopTargetsForPublishedYears(
            new List<GWB_Year__c>{ alreadyPublishedYear, draftYear },
            oldYearMap(new List<GWB_Year__c>{ alreadyPublishedYear, draftYear }, 'Published')
        );
        Test.stopTest();

        Set<Id> noOpYearIds = new Set<Id>{ alreadyPublishedYear.Id, draftYear.Id };
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Plant_Shop_Target__c WHERE Target__c IN :noOpYearIds],
            'No queueable should be enqueued when no year newly becomes Published.'
        );
    }

    @IsTest
    static void createPlantShopTargetsForPublishedYearsSkipsYearWithoutPlant() {
        Plant__c plant = createPlantWithMvp('Trigger Handler Missing Plant Source');
        GWB_Year__c deletedYear = GWBTestDataFactory.createGwbYearTarget(plant.Id, '2028', 'Draft', true);
        delete deletedYear;

        Test.startTest();
        GWBYearTriggerHandler.createPlantShopTargetsForPublishedYears(
            new List<GWB_Year__c>{ deletedYear },
            oldYearMap(new List<GWB_Year__c>{ deletedYear }, 'Draft')
        );
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Plant_Shop_Target__c WHERE Target__c = :deletedYear.Id],
            'A deleted year id should not produce target groups.'
        );
    }

    @IsTest
    static void createPlantShopTargetsForPublishedYearsCreatesParentWithoutItemsWhenTypeIsBlank() {
        Plant__c plant = createPlantWithMvp('Trigger Handler Blank Type Plant');
        GWB_Year__c gwbYear = GWBTestDataFactory.createGwbYearTarget(plant.Id, '2028', 'Draft', true);
        gwbYear.Type__c = null;
        update gwbYear;
        gwbYear.Status__c = 'Published';
        insert createMonth(gwbYear.Id, plant.Id, '2028', 'Productivity', 'OTS', 'Jan_Number__c', -7);

        Test.startTest();
        GWBYearTriggerHandler.createPlantShopTargetsForPublishedYears(
            new List<GWB_Year__c>{ gwbYear },
            oldYearMap(new List<GWB_Year__c>{ gwbYear }, 'Draft')
        );
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
    static void createPlantShopTargetsForPublishedYearsHandlesMissingOldMap() {
        Plant__c plant = createPlantWithMvp('Trigger Handler No Old Map Plant');
        GWB_Year__c gwbYear = GWBTestDataFactory.createGwbYearTarget(plant.Id, '2028', 'Draft', true);
        gwbYear.Status__c = 'Published';

        Test.startTest();
        GWBYearTriggerHandler.createPlantShopTargetsForPublishedYears(
            new List<GWB_Year__c>{ gwbYear },
            null
        );
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Plant_Shop_Target__c WHERE Target__c = :gwbYear.Id],
            'A newly published year without month data should enqueue and no-op safely.'
        );
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
            'PST_HANDLER_' + String.valueOf(Crypto.getRandomInteger()),
            false
        );
        plantFunction.Plant__c = plantId;
        plantFunction.Status__c = 'Active';
        plantFunction.Shop_Manager_View__c = shopManagerView;
        insert plantFunction;
        return plantFunction;
    }

    private static Plant__c createPlantWithMvp(String name) {
        Plant__c plant = GWBTestDataFactory.createPlant(name, false);
        plant.MVP__c = UserInfo.getUserId();
        insert plant;
        return plant;
    }

    private static Map<Id, GWB_Year__c> oldYearMap(List<GWB_Year__c> years, String oldStatus) {
        Map<Id, GWB_Year__c> oldMap = new Map<Id, GWB_Year__c>();
        for (GWB_Year__c yearRecord : years) {
            oldMap.put(yearRecord.Id, new GWB_Year__c(Id = yearRecord.Id, Status__c = oldStatus));
        }
        return oldMap;
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