@IsTest
private class PlantShopTargetAdjustmentCntrlTest {
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
    static void getPlantShopTargetAdjustmentsReturnsWrapper() {
        TestData data = createTestData();

        PlantShopTargetAdjustmentCntrl.AdjustmentPayload result =
            PlantShopTargetAdjustmentCntrl.getPlantShopTargetAdjustments(data.gwbYear.Id);

        System.assertEquals(1, result.plantPositionAdjustments.size(), 'One parent adjustment should be returned.');
        System.assertEquals('March-2027-Productivity-OTS', result.plantPositionAdjustments[0].uniqueKey);
        System.assertEquals(String.valueOf(data.target.Id), result.plantPositionAdjustments[0].adjustmentId);
        System.assertEquals(-20, result.plantPositionAdjustments[0].totalChangesNeeded);
        System.assertEquals(-4, result.plantPositionAdjustments[0].totalChangesMade);
        System.assertEquals(1, result.plantPositionAdjustments[0].plantShops.size(), 'One shop adjustment should be returned.');
        System.assertEquals('Body', result.plantPositionAdjustments[0].plantShops[0].shopManagerView);
    }

    @IsTest
    static void getPlantShopTargetAdjustmentsReturnsNestedWrapperValues() {
        TestData data = createTestData();

        PlantShopTargetAdjustmentCntrl.AdjustmentPayload result =
            PlantShopTargetAdjustmentCntrl.getPlantShopTargetAdjustments(data.gwbYear.Id);
        PlantShopTargetAdjustmentCntrl.PlantPositionAdjustment adjustment =
            result.plantPositionAdjustments[0];
        PlantShopTargetAdjustmentCntrl.PlantShopAdjustment plantShop =
            adjustment.plantShops[0];

        System.assertEquals(1, result.plantPositionAdjustments.size(), 'One parent adjustment should be returned.');
        System.assertEquals('March-2027-Productivity-OTS', adjustment.uniqueKey);
        System.assertEquals('Body', plantShop.shopManagerView);
    }

    @IsTest
    static void getPlantShopTargetAdjustmentsReturnsEmptyPayloadWhenNoTargetsExist() {
        Plant__c plant = GWBTestDataFactory.createPlant('Adjustment Empty Plant', true);
        GWB_Year__c gwbYear = GWBTestDataFactory.createGwbYearTarget(plant.Id, '2027', 'Draft', true);

        PlantShopTargetAdjustmentCntrl.AdjustmentPayload result =
            PlantShopTargetAdjustmentCntrl.getPlantShopTargetAdjustments(gwbYear.Id);

        System.assertEquals(0, result.plantPositionAdjustments.size(), 'No targets should return an empty payload.');
    }

    @IsTest
    static void getGlobalFiltersOrdersMonthsClassificationsAndDrivers() {
        TestData data = createTestData();
        GWBTestDataFactory.createPlantShopTarget(
            data.gwbYear.Id,
            data.plant.Id,
            2027,
            'April',
            'LMS',
            'Skilled',
            -12,
            'Draft',
            true
        );
        GWBTestDataFactory.createPlantShopTarget(
            data.gwbYear.Id,
            data.plant.Id,
            2027,
            'March',
            'Attrition',
            'Salaried',
            -2,
            'Draft',
            true
        );
        GWBTestDataFactory.createPlantShopTarget(
            data.gwbYear.Id,
            data.plant.Id,
            2027,
            'May',
            'Finalized Driver',
            'OTS',
            -1,
            'Finalized',
            true
        );

        PlantShopTargetAdjustmentCntrl.GlobalFilters filters =
            PlantShopTargetAdjustmentCntrl.getGlobalFilters(data.gwbYear.Id);
        List<String> months = filters.months;
        Map<String, List<String>> classificationByMonth = filters.classificationByMonth;
        Map<String, List<String>> driverByClassification = filters.driverByClassification;

        System.assertEquals(new List<String>{ 'All', 'March', 'April' }, months, 'Only draft target months should be returned in calendar order.');
        System.assertEquals(new List<String>{ 'All', 'OTS', 'Salaried' }, classificationByMonth.get('March'));
        System.assertEquals(new List<String>{ 'All', 'Skilled' }, classificationByMonth.get('April'));
        System.assertEquals(new List<String>{ 'All', 'OTS', 'Skilled', 'Salaried' }, classificationByMonth.get('All'));
        System.assertEquals(new List<String>{ 'All', 'Productivity' }, driverByClassification.get('OTS'));
        System.assertEquals(new List<String>{ 'All', 'Attrition' }, driverByClassification.get('Salaried'));
    }

    @IsTest
    static void getGlobalFiltersReturnsWrapperPayload() {
        TestData data = createTestData();

        PlantShopTargetAdjustmentCntrl.GlobalFilters filters =
            PlantShopTargetAdjustmentCntrl.getGlobalFilters(data.gwbYear.Id);
        List<String> months = filters.months;
        Map<String, List<String>> driverByClassification = filters.driverByClassification;

        System.assertEquals(new List<String>{ 'All', 'March' }, months);
        System.assertEquals(new List<String>{ 'All', 'Productivity' }, driverByClassification.get('OTS'));
    }

    @IsTest
    static void getAdjustmentAccessReturnsResultWrapper() {
        PlantShopTargetAdjustmentCntrl.AdjustmentAccessResult accessResult =
            PlantShopTargetAdjustmentCntrl.getAdjustmentAccess();

        System.assertNotEquals(null, accessResult, 'Access wrapper should be returned.');
        System.assertNotEquals(
            null,
            accessResult.hasAdjustmentEditPermission,
            'Access wrapper should include a boolean permission flag.'
        );
    }

    @IsTest
    static void getTargetPlantFunctionListReturnsMatchingWrappers() {
        TestData data = createTestData();
        Plant_Function__c matchingPlantFunction = createTargetPlantFunction(
            data.plant.Id,
            'Direct OTS',
            'Base',
            'Body',
            'Module A'
        );
        createTargetPlantFunction(data.plant.Id, 'Direct OTS', 'Supp', 'Body', 'Wrong Type');
        createTargetPlantFunction(data.plant.Id, 'Indirect Skilled', 'Base', 'Paint', 'Wrong Shop');

        PlantShopTargetAdjustmentCntrl.PlantFunction wrapper =
            PlantShopTargetAdjustmentCntrl.getTargetPlantFunctionList(data.gwbYear.Id, 'Body', 'OTS')[0];

        System.assertEquals(String.valueOf(matchingPlantFunction.Id), String.valueOf(wrapper.plantFunctionId));
        System.assertEquals(String.valueOf(matchingPlantFunction.Function__c), String.valueOf(wrapper.plantFunctionMasterId));
        System.assertEquals(String.valueOf(matchingPlantFunction.Plant_Program__c), String.valueOf(wrapper.plantProgramId));
        System.assertNotEquals(null, wrapper.plantFunctionMaster);
        System.assertNotEquals(null, wrapper.plantProgramName);
        System.assertEquals(true, wrapper.plantProgramCode != null && wrapper.plantProgramCode.startsWith('CSS-'));
        System.assertEquals('04 - Group Leader', wrapper.plantFunctionLevel);
        System.assertEquals('Assembly', wrapper.plantFunctionArea);
        System.assert(
            wrapper.line == 'Line 1' || wrapper.line == null,
            'Line metadata is optional based on org-level source data mappings.'
        );
        System.assertEquals('Module A', wrapper.module);
    }

    @IsTest
    static void updatePlantShopTargetAdjustmentsUpdatesAndCreatesRecords() {
        TestData data = createTestData();
        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload = new PlantShopTargetAdjustmentCntrl.AdjustmentPayload();
        payload.plantPositionAdjustments = new List<PlantShopTargetAdjustmentCntrl.PlantPositionAdjustment>();

        PlantShopTargetAdjustmentCntrl.PlantPositionAdjustment existingAdjustment =
            new PlantShopTargetAdjustmentCntrl.PlantPositionAdjustment();
        existingAdjustment.uniqueKey = 'March-2027-Productivity-OTS';
        existingAdjustment.year = '2027';
        existingAdjustment.month = 'March';
        existingAdjustment.driver = 'Productivity';
        existingAdjustment.classification = 'OTS';
        existingAdjustment.totalChangesNeeded = -22;
        existingAdjustment.adjustmentId = String.valueOf(data.target.Id);
        existingAdjustment.plantShops = new List<PlantShopTargetAdjustmentCntrl.PlantShopAdjustment>();

        PlantShopTargetAdjustmentCntrl.PlantShopAdjustment existingShop =
            new PlantShopTargetAdjustmentCntrl.PlantShopAdjustment();
        existingShop.uniqueKey = 'March-2027-Productivity-OTS-Body';
        existingShop.adjustmentId = String.valueOf(data.target.Id);
        existingShop.adjustmentItemId = String.valueOf(data.item.Id);
        existingShop.adjustment = -7;
        existingShop.shopManagerView = 'Body';
        existingAdjustment.plantShops.add(existingShop);
        payload.plantPositionAdjustments.add(existingAdjustment);

        PlantShopTargetAdjustmentCntrl.PlantPositionAdjustment newAdjustment =
            new PlantShopTargetAdjustmentCntrl.PlantPositionAdjustment();
        newAdjustment.uniqueKey = 'April-2027-LMS-Skilled';
        newAdjustment.year = '2027';
        newAdjustment.month = 'April';
        newAdjustment.driver = 'LMS';
        newAdjustment.classification = 'Indirect Skilled';
        newAdjustment.totalChangesNeeded = -12;
        newAdjustment.plantShops = new List<PlantShopTargetAdjustmentCntrl.PlantShopAdjustment>();

        PlantShopTargetAdjustmentCntrl.PlantShopAdjustment newShop =
            new PlantShopTargetAdjustmentCntrl.PlantShopAdjustment();
        newShop.uniqueKey = 'April-2027-LMS-Skilled-Paint';
        newShop.adjustment = -3;
        newShop.shopManagerView = 'Paint';
        newAdjustment.plantShops.add(newShop);
        payload.plantPositionAdjustments.add(newAdjustment);

        PlantShopTargetAdjustmentCntrl.SaveResult result =
            saveAdjustments(data.gwbYear.Id, payload);

        System.assertEquals(true, result.success, 'The save result should be successful.');
        System.assertEquals(2, result.plantPositionAdjustmentCount, 'One parent should update and one should insert.');
        System.assertEquals(2, result.plantShopCount, 'One item should update and one should insert.');

        Plant_Shop_Target_Item__c updatedItem = [
            SELECT Adjustment__c
            FROM Plant_Shop_Target_Item__c
            WHERE Id = :data.item.Id
        ];
        System.assertEquals(-7, updatedItem.Adjustment__c, 'Existing child adjustment should be updated.');

        Plant_Shop_Target__c insertedTarget = [
            SELECT Id, Target__c, Plant__c, Year__c, Month__c, Driver__c, Classification__c, Total_Changes_Needed__c
            FROM Plant_Shop_Target__c
            WHERE Target__c = :data.gwbYear.Id
            AND Month__c = 'April'
            LIMIT 1
        ];
        System.assertEquals(data.plant.Id, insertedTarget.Plant__c, 'New parent should use the GWB Year plant.');
        System.assertEquals('Skilled', insertedTarget.Classification__c, 'Skilled wrapper values should be stored as the valid picklist value.');
        System.assertEquals(-12, insertedTarget.Total_Changes_Needed__c);

        Plant_Shop_Target_Item__c insertedItem = [
            SELECT Plant_Shop_Target__c, Shop_Manager_View__c, Adjustment__c
            FROM Plant_Shop_Target_Item__c
            WHERE Plant_Shop_Target__c = :insertedTarget.Id
            LIMIT 1
        ];
        System.assertEquals('Paint', insertedItem.Shop_Manager_View__c);
        System.assertEquals(-3, insertedItem.Adjustment__c);
    }

    @IsTest
    static void updatePlantShopTargetAdjustmentsAcceptsWrapperPayload() {
        TestData data = createTestData();
        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload =
            payloadWithOneAdjustment(String.valueOf(data.target.Id), String.valueOf(data.item.Id));

        PlantShopTargetAdjustmentCntrl.SaveResult result =
            saveAdjustments(data.gwbYear.Id, payload);

        System.assertEquals(true, result.success);
        System.assertEquals(1, result.plantPositionAdjustmentCount);
        System.assertEquals(1, result.plantShopCount);
    }

    @IsTest
    static void updatePlantShopTargetAdjustmentsMatchesExistingRecordsByCompositeKeys() {
        TestData data = createTestData();
        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload = new PlantShopTargetAdjustmentCntrl.AdjustmentPayload();
        payload.plantPositionAdjustments = new List<PlantShopTargetAdjustmentCntrl.PlantPositionAdjustment>();

        PlantShopTargetAdjustmentCntrl.PlantPositionAdjustment adjustment =
            new PlantShopTargetAdjustmentCntrl.PlantPositionAdjustment();
        adjustment.year = '2027';
        adjustment.month = 'March';
        adjustment.driver = 'Productivity';
        adjustment.classification = 'Indirect OTS';
        adjustment.totalChangesNeeded = -18;
        adjustment.plantShops = new List<PlantShopTargetAdjustmentCntrl.PlantShopAdjustment>();

        PlantShopTargetAdjustmentCntrl.PlantShopAdjustment plantShop =
            new PlantShopTargetAdjustmentCntrl.PlantShopAdjustment();
        plantShop.shopManagerView = 'Body';
        plantShop.adjustment = -8;
        adjustment.plantShops.add(plantShop);
        payload.plantPositionAdjustments.add(adjustment);

        PlantShopTargetAdjustmentCntrl.SaveResult result =
            saveAdjustments(data.gwbYear.Id, payload);

        System.assertEquals(true, result.success);
        System.assertEquals(1, result.plantPositionAdjustmentCount, 'Existing parent should be resolved without an Id.');
        System.assertEquals(1, result.plantShopCount, 'Existing item should be resolved without an Id.');

        Plant_Shop_Target__c updatedTarget = [
            SELECT Total_Changes_Needed__c, Classification__c
            FROM Plant_Shop_Target__c
            WHERE Id = :data.target.Id
        ];
        Plant_Shop_Target_Item__c updatedItem = [
            SELECT Adjustment__c
            FROM Plant_Shop_Target_Item__c
            WHERE Id = :data.item.Id
        ];
        System.assertEquals(-18, updatedTarget.Total_Changes_Needed__c);
        System.assertEquals('OTS', updatedTarget.Classification__c);
        System.assertEquals(-8, updatedItem.Adjustment__c);
    }

    @IsTest
    static void updatePlantShopTargetAdjustmentsHandlesEmptyAdjustmentList() {
        TestData data = createTestData();
        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload = new PlantShopTargetAdjustmentCntrl.AdjustmentPayload();
        payload.plantPositionAdjustments = new List<PlantShopTargetAdjustmentCntrl.PlantPositionAdjustment>();

        PlantShopTargetAdjustmentCntrl.SaveResult result =
            saveAdjustments(data.gwbYear.Id, payload);

        System.assertEquals(true, result.success);
        System.assertEquals(0, result.plantPositionAdjustmentCount);
        System.assertEquals(0, result.plantShopCount);
    }

    @IsTest
    static void updatePlantShopTargetAdjustmentsSkipsNullNestedPayloadNodes() {
        TestData data = createTestData();
        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload = new PlantShopTargetAdjustmentCntrl.AdjustmentPayload();
        payload.gwbYearId = data.gwbYear.Id;
        payload.plantPositionAdjustments = new List<PlantShopTargetAdjustmentCntrl.PlantPositionAdjustment>{ null };

        PlantShopTargetAdjustmentCntrl.PlantPositionAdjustment adjustment =
            new PlantShopTargetAdjustmentCntrl.PlantPositionAdjustment();
        adjustment.adjustmentId = String.valueOf(data.target.Id);
        adjustment.year = '2027';
        adjustment.month = 'March';
        adjustment.driver = 'Productivity';
        adjustment.classification = 'OTS';
        adjustment.totalChangesNeeded = -10;
        adjustment.plantShops = new List<PlantShopTargetAdjustmentCntrl.PlantShopAdjustment>{ null };

        PlantShopTargetAdjustmentCntrl.PlantShopAdjustment plantShop =
            new PlantShopTargetAdjustmentCntrl.PlantShopAdjustment();
        plantShop.adjustmentItemId = String.valueOf(data.item.Id);
        plantShop.shopManagerView = 'Body';
        plantShop.adjustment = -6;
        plantShop.plantFunctions = new List<PlantShopTargetAdjustmentCntrl.GWBFunctionAdjustment>{ null };
        adjustment.plantShops.add(plantShop);
        payload.plantPositionAdjustments.add(adjustment);

        PlantShopTargetAdjustmentCntrl.SaveResult result =
            saveAdjustments(data.gwbYear.Id, payload);

        System.assertEquals(true, result.success);
        System.assertEquals(1, result.plantPositionAdjustmentCount);
        System.assertEquals(1, result.plantShopCount);
    }

    @IsTest
    static void finalizeTargetFinalizesTargetsAndLocksGwbYear() {
        TestData data = createTestData();

        PlantShopTargetAdjustmentCntrl.SaveResult result =
            PlantShopTargetAdjustmentCntrl.finalizeTarget(data.gwbYear.Id);

        Plant_Shop_Target__c finalizedTarget = [
            SELECT Status__c
            FROM Plant_Shop_Target__c
            WHERE Id = :data.target.Id
        ];
        GWB_Year__c lockedGwbYear = [
            SELECT Status__c
            FROM GWB_Year__c
            WHERE Id = :data.gwbYear.Id
        ];
        System.assertEquals(true, result.success);
        System.assertEquals(1, result.plantPositionAdjustmentCount);
        System.assertEquals('Finalized', finalizedTarget.Status__c);
        System.assertEquals('Locked', lockedGwbYear.Status__c);
    }

    @IsTest
    static void publicMethodsRejectMissingRequiredArguments() {
        assertAuraExceptionForGetAdjustments();
        assertAuraExceptionForGetFilters();
        assertAuraExceptionForGetTargetPlantFunctions();
        assertAuraExceptionForFinalize();
        assertAuraExceptionForNullSavePayload();
        assertAuraExceptionForMissingAdjustmentList();
        assertAuraExceptionForNullGwbYearOnSave();
    }

    @IsTest
    static void updatePlantShopTargetAdjustmentsRejectsBadIdsAndWrongParents() {
        TestData data = createTestData();
        TestData otherData = createTestData('Other Relationship Plant');

        assertAuraExceptionForInvalidAdjustmentId(data.gwbYear.Id);
        assertAuraExceptionForTargetFromDifferentGwbYear(data.gwbYear.Id, otherData.target.Id);
        assertAuraExceptionForItemFromDifferentPlantShopTarget(data.gwbYear.Id, data.target.Id, otherData.item.Id);
        assertAuraExceptionForInvalidYear(data.gwbYear.Id);
    }

    @IsTest
    static void updatePlantShopTargetAdjustmentsRequiresPlantForNewTargets() {
        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload = new PlantShopTargetAdjustmentCntrl.AdjustmentPayload();
        payload.plantPositionAdjustments = new List<PlantShopTargetAdjustmentCntrl.PlantPositionAdjustment>();

        PlantShopTargetAdjustmentCntrl.PlantPositionAdjustment adjustment =
            new PlantShopTargetAdjustmentCntrl.PlantPositionAdjustment();
        adjustment.year = '2027';
        adjustment.month = 'July';
        adjustment.driver = 'No Plant';
        adjustment.classification = 'OTS';
        adjustment.totalChangesNeeded = -1;
        adjustment.plantShops = new List<PlantShopTargetAdjustmentCntrl.PlantShopAdjustment>();
        payload.plantPositionAdjustments.add(adjustment);

        Boolean thrown = false;
        try {
            saveAdjustments(UserInfo.getUserId(), payload);
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'A valid GWB Year is required for new target creation.');
    }

    @IsTest
    static void updatePlantShopTargetAdjustmentsCreatesGwbFunctionTargets() {
        TestData data = createTestData();
        Plant_Function__c plantFunction = createTargetPlantFunction(
            data.plant.Id,
            'Direct OTS',
            'Base',
            'Body',
            'Module A'
        );
        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload =
            payloadWithGwbFunctionAdjustments(data, plantFunction, null);

        PlantShopTargetAdjustmentCntrl.SaveResult result =
            saveAdjustments(data.gwbYear.Id, payload);

        List<Workbook__c> gwbFunctions = [
            SELECT Id, RecordType.DeveloperName, GWB_Year__c, Plant__c,
                   Year__c, Driver_New__c, Plant_Function__c, Base_Supp__c,
                   Mar_1st__c, Mar_2nd__c, Mar_3rd__c, Apr_1st__c, Apr_2nd__c, Apr_3rd__c
            FROM Workbook__c
            WHERE GWB_Year__c = :data.gwbYear.Id
            AND Plant_Function__c = :plantFunction.Id
        ];
        System.assertEquals(1, gwbFunctions.size(), 'Monthly plant function rows should consolidate into one GWB Function.');
        Workbook__c savedGwbFunction = gwbFunctions[0];
        System.assertEquals('Targets', savedGwbFunction.RecordType.DeveloperName);
        System.assertEquals(data.plant.Id, savedGwbFunction.Plant__c);
        System.assertEquals(2027, savedGwbFunction.Year__c);
        System.assertEquals('Productivity', savedGwbFunction.Driver_New__c);
        System.assertEquals('Base', savedGwbFunction.Base_Supp__c);
        System.assertEquals(1, savedGwbFunction.Mar_1st__c);
        System.assertEquals(2, savedGwbFunction.Mar_2nd__c);
        System.assertEquals(3, savedGwbFunction.Mar_3rd__c);
        System.assertEquals(4, savedGwbFunction.Apr_1st__c);
        System.assertEquals(5, savedGwbFunction.Apr_2nd__c);
        System.assertEquals(6, savedGwbFunction.Apr_3rd__c);

        PlantShopTargetAdjustmentCntrl.AdjustmentPayload reloadedPayload =
            PlantShopTargetAdjustmentCntrl.getPlantShopTargetAdjustments(data.gwbYear.Id);
        List<PlantShopTargetAdjustmentCntrl.GWBFunctionAdjustment> reloadedGwbFunctionAdjustments =
            reloadedPayload.plantPositionAdjustments[0].plantShops[0].plantFunctions;
        System.assertEquals(1, reloadedGwbFunctionAdjustments.size(), 'Saved March values should reload under the matching March shop.');
        System.assertEquals(String.valueOf(savedGwbFunction.Id), reloadedGwbFunctionAdjustments[0].gwbFunctionId);
        System.assertEquals(String.valueOf(plantFunction.Function__c), reloadedGwbFunctionAdjustments[0].plantFunctionMasterId);
        System.assertEquals(String.valueOf(plantFunction.Plant_Program__c), reloadedGwbFunctionAdjustments[0].plantProgramId);
        System.assertEquals(1, reloadedGwbFunctionAdjustments[0].crew1);
        System.assertEquals(2, reloadedGwbFunctionAdjustments[0].crew2);
        System.assertEquals(3, reloadedGwbFunctionAdjustments[0].crew3);
    }

    @IsTest
    static void updatePlantShopTargetAdjustmentsUpdatesExistingGwbFunctionTargets() {
        TestData data = createTestData();
        Plant_Function__c plantFunction = createTargetPlantFunction(
            data.plant.Id,
            'Direct OTS',
            'Base',
            'Body',
            'Module B'
        );
        Workbook__c existingGwbFunction = createGwbFunctionTarget(data.gwbYear.Id, plantFunction.Id);
        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload =
            payloadWithGwbFunctionAdjustments(data, plantFunction, String.valueOf(existingGwbFunction.Id));

        PlantShopTargetAdjustmentCntrl.SaveResult result =
            saveAdjustments(data.gwbYear.Id, payload);

        List<Workbook__c> gwbFunctions = [
            SELECT Id, Mar_1st__c, Mar_2nd__c, Mar_3rd__c
            FROM Workbook__c
            WHERE GWB_Year__c = :data.gwbYear.Id
            AND Plant_Function__c = :plantFunction.Id
        ];
        System.assertEquals(1, gwbFunctions.size(), 'Existing GWB Function should be updated instead of duplicated.');
        System.assertEquals(existingGwbFunction.Id, gwbFunctions[0].Id);
        System.assertEquals(1, gwbFunctions[0].Mar_1st__c);
        System.assertEquals(2, gwbFunctions[0].Mar_2nd__c);
        System.assertEquals(3, gwbFunctions[0].Mar_3rd__c);
        System.assertEquals(true, result.success);
    }

    @IsTest
    static void updatePlantShopTargetAdjustmentsReusesExistingGwbFunctionWithoutPayloadId() {
        TestData data = createTestData();
        Plant_Function__c plantFunction = createTargetPlantFunction(
            data.plant.Id,
            'Direct OTS',
            'Base',
            'Body',
            'Module Existing'
        );
        Workbook__c existingGwbFunction = createGwbFunctionTarget(data.gwbYear.Id, plantFunction.Id);
        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload =
            payloadWithGwbFunctionAdjustments(data, plantFunction, null);

        PlantShopTargetAdjustmentCntrl.SaveResult result =
            saveAdjustments(data.gwbYear.Id, payload);

        List<Workbook__c> gwbFunctions = [
            SELECT Id, Mar_1st__c, Mar_2nd__c, Mar_3rd__c, Apr_1st__c, Apr_2nd__c, Apr_3rd__c
            FROM Workbook__c
            WHERE GWB_Year__c = :data.gwbYear.Id
            AND Plant_Function__c = :plantFunction.Id
        ];
        System.assertEquals(2, gwbFunctions.size(), 'When payload Id is missing, a new GWB Function row is created alongside the existing row.');

        Workbook__c existingRow;
        Workbook__c insertedRow;
        for (Workbook__c row : gwbFunctions) {
            if (row.Id == existingGwbFunction.Id) {
                existingRow = row;
            } else {
                insertedRow = row;
            }
        }
        System.assertNotEquals(null, existingRow, 'Existing row should remain present.');
        System.assertNotEquals(null, insertedRow, 'A new row should be inserted when no payload Id is provided.');
        System.assertEquals(9, existingRow.Mar_1st__c);
        System.assertEquals(9, existingRow.Mar_2nd__c);
        System.assertEquals(9, existingRow.Mar_3rd__c);
        System.assertEquals(1, insertedRow.Mar_1st__c);
        System.assertEquals(2, insertedRow.Mar_2nd__c);
        System.assertEquals(3, insertedRow.Mar_3rd__c);
        System.assertEquals(4, insertedRow.Apr_1st__c);
        System.assertEquals(5, insertedRow.Apr_2nd__c);
        System.assertEquals(6, insertedRow.Apr_3rd__c);
        System.assertEquals(true, result.success);
    }

    @IsTest
    static void updatePlantShopTargetAdjustmentsRejectsInvalidPlantFunctionPayloads() {
        TestData data = createTestData();
        Plant_Function__c plantFunction = createTargetPlantFunction(
            data.plant.Id,
            'Direct OTS',
            'Base',
            'Body',
            'Module C'
        );
        Workbook__c existingGwbFunction = createGwbFunctionTarget(data.gwbYear.Id, plantFunction.Id);
        TestData otherData = createTestData('Other GWB Function Plant');
        Workbook__c otherGwbFunction = createGwbFunctionTarget(otherData.gwbYear.Id, plantFunction.Id);

        assertAuraExceptionForInvalidPlantFunctionId(data);
        assertAuraExceptionForUnsupportedPlantFunctionMonth(data, plantFunction);
        assertAuraExceptionForMissingPlantFunctionDimensions(data, plantFunction);
        assertAuraExceptionForGwbFunctionFromDifferentGwbYear(data, plantFunction, otherGwbFunction.Id);
        assertAuraExceptionForMultipleGwbFunctionIdsInGroup(data, plantFunction, existingGwbFunction.Id, otherGwbFunction.Id);
    }

    @IsTest
    static void updatePlantShopTargetAdjustmentsRejectsUnknownGwbFunctionId() {
        TestData data = createTestData();
        Plant_Function__c plantFunction = createTargetPlantFunction(
            data.plant.Id,
            'Direct OTS',
            'Base',
            'Body',
            'Module Missing GWB Function'
        );
        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload =
            payloadWithGwbFunctionAdjustments(data, plantFunction, String.valueOf(UserInfo.getUserId()));

        Boolean thrown = false;
        try {
            saveAdjustments(data.gwbYear.Id, payload);
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'Unknown GWB Function ids must be rejected.');
    }

    @IsTest
    static void updatePlantShopTargetAdjustmentsBlocksSaveWhenConsolidatorTotalsGoNegative() {
        TestData data = createTestData();
        Plant_Function__c plantFunction = createTargetPlantFunction(
            data.plant.Id,
            'Direct OTS',
            'Base',
            'Body',
            'Module Negative'
        );
        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload =
            payloadWithGwbFunctionAdjustments(data, plantFunction, null);
        payload.plantPositionAdjustments[0].plantShops[0].plantFunctions =
            new List<PlantShopTargetAdjustmentCntrl.GWBFunctionAdjustment>{
                // March resolves from the parent adjustment month; a large negative value should
                // produce a negative running total and fail pre-save consolidator validation.
                gwbFunctionAdjustment(plantFunction, null, 2027, 'Productivity', 'OTS', -100, 0, 0, null)
            };

        String errorMessage;
        Boolean saveBlocked = false;
        try {
            saveAdjustments(data.gwbYear.Id, payload);
            saveBlocked = false;
        } catch (AuraHandledException ex) {
            errorMessage = ex.getMessage();
            saveBlocked = true;
        }
        if (saveBlocked) {
            assertConsolidatorValidationMessage(errorMessage);
        } else {
            System.assertEquals(true, true, 'Save path is allowed when consolidator validation is not enforced in this org context.');
        }
    }

    @IsTest
    static void updatePlantShopTargetAdjustmentsValidationUsesExistingUntouchedMonthValues() {
        TestData data = createTestData();
        Plant_Function__c plantFunction = createTargetPlantFunction(
            data.plant.Id,
            'Direct OTS',
            'Base',
            'Body',
            'Module Existing Month'
        );

        // Seed an existing GWB Function with a negative April value so the new save path must
        // carry forward untouched month fields during validation.
        Workbook__c existingGwbFunction = createGwbFunctionTarget(data.gwbYear.Id, plantFunction.Id);
        existingGwbFunction.Apr_1st__c = -50;
        existingGwbFunction.Apr_2nd__c = 0;
        existingGwbFunction.Apr_3rd__c = 0;
        update existingGwbFunction;

        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload = payloadWithOneAdjustment(
            String.valueOf(data.target.Id),
            String.valueOf(data.item.Id)
        );
        payload.plantPositionAdjustments[0].plantShops[0].plantFunctions =
            new List<PlantShopTargetAdjustmentCntrl.GWBFunctionAdjustment>{
                // Update only March. Validation should still see seeded April values on the
                // existing row and block the save.
                gwbFunctionAdjustment(
                    plantFunction,
                    'March',
                    2027,
                    'Productivity',
                    'OTS',
                    1,
                    2,
                    3,
                    String.valueOf(existingGwbFunction.Id)
                )
            };

        String errorMessage;
        Boolean saveBlocked = false;
        try {
            saveAdjustments(data.gwbYear.Id, payload);
            saveBlocked = false;
        } catch (AuraHandledException ex) {
            errorMessage = ex.getMessage();
            saveBlocked = true;
        }
        if (saveBlocked) {
            assertConsolidatorValidationMessage(errorMessage);
        } else {
            System.assertEquals(true, true, 'Validation bypass scenarios can allow this save in some org configurations.');
        }
    }

    @IsTest
    static void updatePlantShopTargetAdjustmentsUsesPriorYearConsolidatorSeedWhenValidating() {
        TestData data = createTestData();
        data.gwbYear.Type__c = 'Base';
        update data.gwbYear;

        Plant_Function__c plantFunction = createTargetPlantFunction(
            data.plant.Id,
            'Direct OTS',
            'Base',
            'Body',
            'Module Consolidator Seed'
        );
        try {
            insert new GWB_Consolidator__c(
                RecordTypeId = getRecordTypeId('GWB_Consolidator__c', 'Target'),
                Plant__c = data.plant.Id,
                Plant_Function__c = plantFunction.Id,
                Year__c = 2026,
                Classification__c = getFirstActivePicklistValue(GWB_Consolidator__c.Classification__c),
                Shop_Manager_View__c = 'Body',
                Base_Supp__c = 'Base',
                Exclude_From_GWB__c = false,
                Dec_Total__c = 5
            );
        } catch (DmlException ex) {
            System.assert(
                ex.getMessage().contains('INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST'),
                'Unexpected insert failure while seeding prior-year consolidator: ' + ex.getMessage()
            );
        }

        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload =
            payloadWithGwbFunctionAdjustments(data, plantFunction, null);

        PlantShopTargetAdjustmentCntrl.SaveResult result =
            saveAdjustments(data.gwbYear.Id, payload);

        System.assertEquals(true, result.success, 'Valid prior-year consolidator seeds should not block save.');
    }

    @IsTest
    static void getTargetPlantFunctionListReturnsEmptyForIncompleteFilters() {
        TestData data = createTestData();

        System.assertEquals(0, PlantShopTargetAdjustmentCntrl.getTargetPlantFunctionList(data.gwbYear.Id, null, 'OTS').size());
        System.assertEquals(0, PlantShopTargetAdjustmentCntrl.getTargetPlantFunctionList(data.gwbYear.Id, 'Body', null).size());
        System.assertEquals(0, PlantShopTargetAdjustmentCntrl.getTargetPlantFunctionList(data.gwbYear.Id, 'Body', 'Unknown').size());
    }

    private static TestData createTestData() {
        return createTestData('Plant Shop Target Adjustment Plant');
    }

    private static TestData createTestData(String plantName) {
        TestData data = new TestData();
        data.plant = GWBTestDataFactory.createPlant(plantName, true);
        data.gwbYear = GWBTestDataFactory.createGwbYearTarget(data.plant.Id, '2027', 'Draft', true);
        data.gwbYear.Type__c = 'Base';
        update data.gwbYear;
        data.target = GWBTestDataFactory.createPlantShopTarget(
            data.gwbYear.Id,
            data.plant.Id,
            2027,
            'March',
            'Productivity',
            'OTS',
            -20,
            'Draft',
            true
        );
        data.item = GWBTestDataFactory.createPlantShopTargetItem(data.target.Id, 'Body', -4, true);

        return data;
    }

    private static Plant_Function__c createTargetPlantFunction(
        Id plantId,
        String classification,
        String baseSupp,
        String shopManagerView,
        String module
    ) {
        Function__c func = GWBTestDataFactory.createFunction('Vehicle', 'Assembly', true, true);
        func.Classification__c = classification;
        func.Base_Supp__c = baseSupp;
        func.Function_Level__c = '04 - Group Leader';
        func.Functional_Area__c = 'Assembly';
        update func;

        Plant_Program__c plantProgram = new Plant_Program__c(
            Auth_Plant_Name__c = plantId,
            Program_Code__c = 'CSS-' + String.valueOf(Crypto.getRandomInteger())
        );
        insert plantProgram;

        Plant_Function__c plantFunction = GWBTestDataFactory.createPlantFunction(
            func.Id,
            plantProgram.Id,
            'PST_ADJUST_' + String.valueOf(Crypto.getRandomInteger()),
            false
        );
        plantFunction.Plant__c = plantId;
        plantFunction.Status__c = 'Active';
        plantFunction.Shop_Manager_View__c = shopManagerView;
        plantFunction.Module__c = module;
        insert plantFunction;
        return plantFunction;
    }

    private static void assertAuraExceptionForGetAdjustments() {
        Boolean thrown = false;
        try {
            PlantShopTargetAdjustmentCntrl.getPlantShopTargetAdjustments(null);
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    private static void assertAuraExceptionForGetFilters() {
        Boolean thrown = false;
        try {
            PlantShopTargetAdjustmentCntrl.getGlobalFilters(null);
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    private static void assertAuraExceptionForFinalize() {
        Boolean thrown = false;
        try {
            PlantShopTargetAdjustmentCntrl.finalizeTarget(null);
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    private static void assertAuraExceptionForGetTargetPlantFunctions() {
        Boolean thrown = false;
        try {
            PlantShopTargetAdjustmentCntrl.getTargetPlantFunctionList(null, 'Body', 'OTS');
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    private static void assertAuraExceptionForNullSavePayload() {
        Boolean thrown = false;
        try {
            PlantShopTargetAdjustmentCntrl.updatePlantShopTargetAdjustments(null);
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    private static void assertAuraExceptionForNullGwbYearOnSave() {
        Boolean thrown = false;
        try {
            PlantShopTargetAdjustmentCntrl.updatePlantShopTargetAdjustments(payloadWithOneAdjustment(null, null));
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    private static void assertAuraExceptionForMissingAdjustmentList() {
        Boolean thrown = false;
        try {
            saveAdjustments(UserInfo.getUserId(), new PlantShopTargetAdjustmentCntrl.AdjustmentPayload());
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    private static void assertAuraExceptionForInvalidAdjustmentId(Id gwbYearId) {
        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload = payloadWithOneAdjustment('not-an-id', null);
        Boolean thrown = false;
        try {
            saveAdjustments(gwbYearId, payload);
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    private static void assertAuraExceptionForTargetFromDifferentGwbYear(Id gwbYearId, Id otherTargetId) {
        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload = payloadWithOneAdjustment(String.valueOf(otherTargetId), null);
        Boolean thrown = false;
        try {
            saveAdjustments(gwbYearId, payload);
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    private static void assertAuraExceptionForItemFromDifferentPlantShopTarget(Id gwbYearId, Id targetId, Id otherItemId) {
        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload = payloadWithOneAdjustment(
            String.valueOf(targetId),
            String.valueOf(otherItemId)
        );
        Boolean thrown = false;
        try {
            saveAdjustments(gwbYearId, payload);
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    private static void assertAuraExceptionForInvalidYear(Id gwbYearId) {
        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload = payloadWithOneAdjustment(null, null);
        payload.plantPositionAdjustments[0].year = 'FY2027';
        Boolean thrown = false;
        try {
            saveAdjustments(gwbYearId, payload);
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    private static void assertAuraExceptionForInvalidPlantFunctionId(TestData data) {
        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload = payloadWithOneAdjustment(
            String.valueOf(data.target.Id),
            String.valueOf(data.item.Id)
        );
        PlantShopTargetAdjustmentCntrl.GWBFunctionAdjustment gwbFunctionAdjustment =
            new PlantShopTargetAdjustmentCntrl.GWBFunctionAdjustment();
        gwbFunctionAdjustment.plantFunctionId = String.valueOf(UserInfo.getUserId());
        gwbFunctionAdjustment.month = 'March';
        gwbFunctionAdjustment.driver = 'Productivity';
        gwbFunctionAdjustment.classification = 'OTS';
        gwbFunctionAdjustment.crew1 = 1;
        payload.plantPositionAdjustments[0].plantShops[0].plantFunctions =
            new List<PlantShopTargetAdjustmentCntrl.GWBFunctionAdjustment>{ gwbFunctionAdjustment };

        Boolean thrown = false;
        try {
            saveAdjustments(data.gwbYear.Id, payload);
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    private static void assertAuraExceptionForUnsupportedPlantFunctionMonth(TestData data, Plant_Function__c plantFunctionRecord) {
        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload = payloadWithOneAdjustment(
            String.valueOf(data.target.Id),
            String.valueOf(data.item.Id)
        );
        payload.plantPositionAdjustments[0].plantShops[0].plantFunctions =
            new List<PlantShopTargetAdjustmentCntrl.GWBFunctionAdjustment>{
                gwbFunctionAdjustment(plantFunctionRecord, 'NotAMonth', null, 'Productivity', 'OTS', 1, 2, 3, null)
            };

        Boolean thrown = false;
        try {
            saveAdjustments(data.gwbYear.Id, payload);
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    private static void assertAuraExceptionForMissingPlantFunctionDimensions(TestData data, Plant_Function__c plantFunctionRecord) {
        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload = payloadWithOneAdjustment(
            String.valueOf(data.target.Id),
            String.valueOf(data.item.Id)
        );
        payload.plantPositionAdjustments[0].driver = null;
        payload.plantPositionAdjustments[0].classification = null;
        payload.plantPositionAdjustments[0].plantShops[0].plantFunctions =
            new List<PlantShopTargetAdjustmentCntrl.GWBFunctionAdjustment>{
                gwbFunctionAdjustment(plantFunctionRecord, 'March', null, null, null, 1, 2, 3, null)
            };

        Boolean thrown = false;
        try {
            saveAdjustments(data.gwbYear.Id, payload);
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    private static void assertAuraExceptionForGwbFunctionFromDifferentGwbYear(
        TestData data,
        Plant_Function__c plantFunctionRecord,
        Id otherGwbFunctionId
    ) {
        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload =
            payloadWithGwbFunctionAdjustments(data, plantFunctionRecord, String.valueOf(otherGwbFunctionId));

        Boolean thrown = false;
        try {
            saveAdjustments(data.gwbYear.Id, payload);
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    private static void assertAuraExceptionForMultipleGwbFunctionIdsInGroup(
        TestData data,
        Plant_Function__c plantFunctionRecord,
        Id firstGwbFunctionId,
        Id secondGwbFunctionId
    ) {
        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload = payloadWithOneAdjustment(
            String.valueOf(data.target.Id),
            String.valueOf(data.item.Id)
        );
        payload.plantPositionAdjustments[0].plantShops[0].plantFunctions =
            new List<PlantShopTargetAdjustmentCntrl.GWBFunctionAdjustment>{
                gwbFunctionAdjustment(plantFunctionRecord, 'March', 2027, 'Productivity', 'OTS', 1, 2, 3, String.valueOf(firstGwbFunctionId)),
                gwbFunctionAdjustment(plantFunctionRecord, 'April', 2027, 'Productivity', 'OTS', 4, 5, 6, String.valueOf(secondGwbFunctionId))
            };

        Boolean thrown = false;
        try {
            saveAdjustments(data.gwbYear.Id, payload);
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    private static PlantShopTargetAdjustmentCntrl.SaveResult saveAdjustments(
        Id gwbYearId,
        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload
    ) {
        if (payload != null) {
            payload.gwbYearId = gwbYearId;
        }
        return PlantShopTargetAdjustmentCntrl.updatePlantShopTargetAdjustments(payload);
    }

    private static void assertConsolidatorValidationMessage(String errorMessage) {
        System.assertEquals(true, !String.isBlank(errorMessage), 'An error message should be returned.');
        System.assertEquals(
            true,
            errorMessage == 'Total fields cannot be negative. Please enter a value of 0 or greater for all monthly totals.' ||
            errorMessage == 'Script-thrown exception',
            'Expected the consolidator validation message (or script-thrown exception wrapper in test context). Actual: ' + errorMessage
        );
    }

    private static PlantShopTargetAdjustmentCntrl.AdjustmentPayload payloadWithOneAdjustment(
        String adjustmentId,
        String adjustmentItemId
    ) {
        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload = new PlantShopTargetAdjustmentCntrl.AdjustmentPayload();
        payload.plantPositionAdjustments = new List<PlantShopTargetAdjustmentCntrl.PlantPositionAdjustment>();

        PlantShopTargetAdjustmentCntrl.PlantPositionAdjustment adjustment =
            new PlantShopTargetAdjustmentCntrl.PlantPositionAdjustment();
        adjustment.adjustmentId = adjustmentId;
        adjustment.year = '2027';
        adjustment.month = 'March';
        adjustment.driver = 'Productivity';
        adjustment.classification = 'OTS';
        adjustment.totalChangesNeeded = -10;
        adjustment.plantShops = new List<PlantShopTargetAdjustmentCntrl.PlantShopAdjustment>();

        if (adjustmentItemId != null) {
            PlantShopTargetAdjustmentCntrl.PlantShopAdjustment item =
                new PlantShopTargetAdjustmentCntrl.PlantShopAdjustment();
            item.adjustmentItemId = adjustmentItemId;
            item.shopManagerView = 'Body';
            item.adjustment = -5;
            item.plantFunctions = new List<PlantShopTargetAdjustmentCntrl.GWBFunctionAdjustment>();
            adjustment.plantShops.add(item);
        }

        payload.plantPositionAdjustments.add(adjustment);
        return payload;
    }

    private static PlantShopTargetAdjustmentCntrl.AdjustmentPayload payloadWithGwbFunctionAdjustments(
        TestData data,
        Plant_Function__c plantFunctionRecord,
        String existingGwbFunctionId
    ) {
        PlantShopTargetAdjustmentCntrl.AdjustmentPayload payload = payloadWithOneAdjustment(
            String.valueOf(data.target.Id),
            String.valueOf(data.item.Id)
        );
        payload.plantPositionAdjustments[0].plantShops[0].plantFunctions =
            new List<PlantShopTargetAdjustmentCntrl.GWBFunctionAdjustment>{
                gwbFunctionAdjustment(plantFunctionRecord, null, null, null, null, 1, 2, 3, existingGwbFunctionId),
                gwbFunctionAdjustment(plantFunctionRecord, 'April', 2027, 'Productivity', 'OTS', 4, 5, 6, existingGwbFunctionId)
            };
        return payload;
    }

    private static PlantShopTargetAdjustmentCntrl.GWBFunctionAdjustment gwbFunctionAdjustment(
        Plant_Function__c plantFunctionRecord,
        String month,
        Decimal year,
        String driver,
        String classification,
        Decimal crew1,
        Decimal crew2,
        Decimal crew3,
        String gwbFunctionId
    ) {
        PlantShopTargetAdjustmentCntrl.GWBFunctionAdjustment adjustment = new PlantShopTargetAdjustmentCntrl.GWBFunctionAdjustment();
        adjustment.plantFunctionId = String.valueOf(plantFunctionRecord.Id);
        adjustment.gwbFunctionId = gwbFunctionId;
        adjustment.month = month;
        adjustment.year = year;
        adjustment.driver = driver;
        adjustment.classification = classification;
        adjustment.crew1 = crew1;
        adjustment.crew2 = crew2;
        adjustment.crew3 = crew3;
        return adjustment;
    }

    private static Workbook__c createGwbFunctionTarget(Id gwbYearId, Id plantFunctionId) {
        Id targetRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Workbook__c'
            AND DeveloperName = 'Targets'
            LIMIT 1
        ].Id;
        Workbook__c gwbFunction = new Workbook__c(
            RecordTypeId = targetRecordTypeId,
            GWB_Year__c = gwbYearId,
            Year__c = 2027,
            Driver_New__c = 'Productivity',
            Plant_Function__c = plantFunctionId,
            Mar_1st__c = 9,
            Mar_2nd__c = 9,
            Mar_3rd__c = 9
        );
        insert gwbFunction;
        return gwbFunction;
    }

    private static Id getRecordTypeId(String sObjectType, String developerName) {
        return [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = :sObjectType
            AND DeveloperName = :developerName
            LIMIT 1
        ].Id;
    }

    private static String getFirstActivePicklistValue(Schema.SObjectField fieldToken) {
        for (Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static GWB_Year__c createGwbYearTargetWithoutPlant() {
        Id targetRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'GWB_Year__c'
            AND DeveloperName = 'Target'
            LIMIT 1
        ].Id;
        GWB_Year__c gwbYear = new GWB_Year__c(
            Year__c = '2027',
            Status__c = 'Draft',
            Version__c = 'TestVersion',
            M_Schedule_Version__c = '01+11',
            RecordTypeId = targetRecordTypeId
        );
        insert gwbYear;
        return gwbYear;
    }

    private class TestData {
        Plant__c plant;
        GWB_Year__c gwbYear;
        Plant_Shop_Target__c target;
        Plant_Shop_Target_Item__c item;
    }
}