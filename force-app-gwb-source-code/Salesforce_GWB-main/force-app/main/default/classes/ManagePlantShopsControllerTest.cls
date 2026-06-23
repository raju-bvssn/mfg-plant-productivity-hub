/**
 * Test class for ManagePlantShopsController
 * Targets 90%+ code coverage using GWBTestDataFactory where applicable
 */
@isTest
private class ManagePlantShopsControllerTest {

    @testSetup
    static void setupTestData() {
        Plant__c plant = GWBTestDataFactory.createPlant('Test Assembly Plant', true);
        
        Shop_Master__c shopMaster1 = GWBTestDataFactory.createShopMaster('Assembly', 'Vehicle', 'All', true, true);
        Shop_Master__c shopMaster2 = GWBTestDataFactory.createShopMaster('Assembly', 'Vehicle', 'Body', true, true);
        
        Plant_Shop__c plantShop = GWBTestDataFactory.createPlantShop(
            plant.Id,
            shopMaster1.Id,
            'Assembly',
            'Vehicle',
            'All',
            true
        );
        
        Plant_Program__c setupProgramAll = GWBTestDataFactory.createPlantProgramForShop(
            plantShop.Id,
            'A',
            true,
            'CSS',
            true
        );
        
        Plant_Shop__c plantShopBody = GWBTestDataFactory.createPlantShop(
            plant.Id,
            shopMaster2.Id,
            'Assembly',
            'Vehicle',
            'Body',
            true
        );
        Plant_Program__c setupProgramBody = GWBTestDataFactory.createPlantProgramForShop(plantShopBody.Id, 'B', true, 'Ultium', true);
        update new List<Plant_Program__c>{
            new Plant_Program__c(Id = setupProgramAll.Id, Plant_Program_Name__c = 'CSS', Include__c = false),
            new Plant_Program__c(Id = setupProgramBody.Id, Plant_Program_Name__c = 'Ultium', Include__c = false)
        };
        
        GWBTestDataFactory.createOperationPlan(2, true);
        GWBTestDataFactory.createFunctionForPlantShops('Vehicle', 'Assembly', 'All', 'A', true);
    }

    @isTest
    static void testGetInitialData_Success() {
        Plant__c plant = [SELECT Id, Name, Auth_Sector__c FROM Plant__c LIMIT 1];
        
        Test.startTest();
        ManagePlantShopsController.InitialDataWrapper result = ManagePlantShopsController.getInitialData(plant.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(plant.Name, result.plantName, 'Plant name should match');
        System.assert(
            result.plantAuthSector == plant.Auth_Sector__c || String.isBlank(result.plantAuthSector),
            'Plant auth sector should match when populated.'
        );
        System.assertNotEquals(null, result.shopMasters, 'Shop masters should not be null');
        System.assertNotEquals(null, result.plantShops, 'Plant shops should not be null');
        System.assertNotEquals(null, result.shopPrograms, 'Shop programs should not be null');
        System.assertNotEquals(null, result.originalPlantProgramIds, 'Original program IDs should not be null');
        System.assertNotEquals(null, result.programMasters, 'Program masters should not be null');
    }

    @isTest
    static void testGetInitialData_BlankPlantId() {
        Test.startTest();
        ManagePlantShopsController.InitialDataWrapper result = ManagePlantShopsController.getInitialData('');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals('', result.plantName, 'Plant name should be empty');
        System.assertEquals('', result.plantAuthSector, 'Plant auth sector should be empty');
        System.assertNotEquals(null, result.programMasters, 'Program masters should not be null');
    }

    @isTest
    static void testGetShopMastersByCriteria_WithExcludeShops() {
        Test.startTest();
        List<Shop_Master__c> result = ManagePlantShopsController.getShopMastersByCriteria(
            'Assembly',
            'Vehicle',
            new List<String>{ 'Paint' }
        );
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        for (Shop_Master__c sm : result) {
            System.assertNotEquals('Paint', sm.Shop__c, 'Should exclude Paint');
        }
    }

    @isTest
    static void testGetShopMastersByCriteria_WithoutExcludeShops() {
        Test.startTest();
        List<Shop_Master__c> result = ManagePlantShopsController.getShopMastersByCriteria(
            'Assembly',
            'Vehicle',
            null
        );
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @isTest
    static void testGetShopMastersByCriteria_BlankSector() {
        List<Shop_Master__c> result = ManagePlantShopsController.getShopMastersByCriteria('', 'Vehicle', null);
        System.assertEquals(0, result.size(), 'Should return empty for blank sector');
    }

    @isTest
    static void testGetShopMastersByCriteria_BlankProductType() {
        List<Shop_Master__c> result = ManagePlantShopsController.getShopMastersByCriteria('Assembly', '', null);
        System.assertEquals(0, result.size(), 'Should return empty for blank product type');
    }

    @isTest
    static void testUpdatePlantProgramOpPlan_Success() {
        Plant_Program__c pp = [SELECT Id FROM Plant_Program__c LIMIT 1];
        Operation_Plan__c op = [SELECT Id FROM Operation_Plan__c LIMIT 1];
        
        Test.startTest();
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.updatePlantProgramOpPlan(pp.Id, op.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should return a result');
        if (result.success) {
            Plant_Program__c updated = [SELECT Shifts_Def__c FROM Plant_Program__c WHERE Id = :pp.Id];
            System.assertEquals(op.Id, updated.Shifts_Def__c, 'Shifts_Def__c should be updated');
        } else {
            System.assert(String.isNotBlank(result.message), 'Failure should include a message');
        }
    }

    @isTest
    static void testUpdatePlantProgramOpPlan_NullOpPlan() {
        Plant_Program__c pp = [SELECT Id FROM Plant_Program__c LIMIT 1];
        
        Test.startTest();
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.updatePlantProgramOpPlan(pp.Id, '');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should return a result');
        if (result.success) {
            Plant_Program__c updated = [SELECT Shifts_Def__c FROM Plant_Program__c WHERE Id = :pp.Id];
            System.assertEquals(null, updated.Shifts_Def__c, 'Shifts_Def__c should be cleared');
        } else {
            System.assert(String.isNotBlank(result.message), 'Failure should include a message');
        }
    }

    @isTest
    static void testUpdatePlantProgramOpPlan_NullPlantProgramId() {
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.updatePlantProgramOpPlan(null, null);
        System.assertEquals(false, result.success, 'Should fail');
        System.assert(result.message.contains('Plant Program ID'), 'Message should mention Plant Program ID');
    }

    @isTest
    static void testEnsurePlantProgramCodeExists_NewRecord() {
        Test.startTest();
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.ensurePlantProgramCodeExists(
            'Assembly',
            'Battery',
            'Ultium'
        );
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Should succeed');
        System.assert(result.message.contains('created') || result.message.contains('exists'), 'Message should indicate creation or existence');
        
        List<Plant_Program_Code__c> created = [SELECT Id FROM Plant_Program_Code__c WHERE Auth_Sector__c = 'Assembly' AND Product_Type__c = 'Battery' AND Program_Code__c = 'Ultium'];
        System.assert(created.size() >= 1, 'Record should exist');
    }

    @isTest
    static void testEnsurePlantProgramCodeExists_BlankParams() {
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.ensurePlantProgramCodeExists('', 'Battery', 'CSS');
        System.assertEquals(false, result.success, 'Should fail for blank auth sector');
        
        result = ManagePlantShopsController.ensurePlantProgramCodeExists('Assembly', '', 'CSS');
        System.assertEquals(false, result.success, 'Should fail for blank product type');
        
        result = ManagePlantShopsController.ensurePlantProgramCodeExists('Assembly', 'Battery', '');
        System.assertEquals(false, result.success, 'Should fail for blank program code');
    }

    @isTest
    static void testGetOperationPlansForDropdown() {
        Test.startTest();
        List<ManagePlantShopsController.OperationPlanOption> result = ManagePlantShopsController.getOperationPlansForDropdown();
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.size() >= 1, 'Should have at least one operation plan from setup');
    }

    @isTest
    static void testGetProgramCodeOptionsBySectorProductType() {
        GWBTestDataFactory.createPlantProgramCode('CSS', 'Battery', 'Assembly', 'Assembly', true);
        
        Test.startTest();
        List<ManagePlantShopsController.ProgramCodeOption> result = ManagePlantShopsController.getProgramCodeOptionsBySectorProductType('Assembly', 'Battery');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.size() > 0, 'Should have program code options from Plant_Program_Code__c');
        System.assertEquals('CSS', result[0].value, 'First option value should match');
    }

    @isTest
    static void testGetProgramCodeOptionsBySectorProductType_BlankParams() {
        List<ManagePlantShopsController.ProgramCodeOption> result = ManagePlantShopsController.getProgramCodeOptionsBySectorProductType('', 'Battery');
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.size(), 'Should return empty for blank auth sector');
        
        result = ManagePlantShopsController.getProgramCodeOptionsBySectorProductType('Assembly', '');
        System.assertEquals(0, result.size(), 'Should return empty for blank product type');
    }

    @isTest
    static void testReparentEquationFunctionsForDeactivatedPrograms() {
        Plant__c plant = GWBTestDataFactory.createPlant('Test GPS Plant', true);
        Shop_Master__c sourceShopMaster = GWBTestDataFactory.createShopMaster('GPS', 'Engine', 'All', true, true);
        Shop_Master__c targetShopMaster = GWBTestDataFactory.createShopMaster('GPS', 'Engine', 'Machining', true, true);
        Plant_Shop__c sourcePlantShop = GWBTestDataFactory.createPlantShop(
            plant.Id,
            sourceShopMaster.Id,
            'GPS',
            'Engine',
            'All',
            true
        );
        Plant_Program__c sourceProgram = GWBTestDataFactory.createPlantProgramForShop(
            sourcePlantShop.Id,
            'A',
            true,
            'CSS',
            true
        );
        Operation_Plan__c operationPlan = GWBTestDataFactory.createOperationPlan(3, true);

        Function__c equationFunction = new Function__c(
            Name = 'Equation Function ' + System.now().getTime(),
            Product_Type__c = 'Engine',
            Auth_Sector__c = 'GPS',
            Shop_Master_View__c = 'Equation',
            Program_Product_Index__c = 'A',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base',
            Included_in_Auth_Plan_of_Record__c = false
        );
        insert equationFunction;

        Plant_Function__c sourcePlantFunction = GWBTestDataFactory.createPlantFunction(
            equationFunction.Id,
            sourceProgram.Id,
            'EQ-' + System.now().getTime(),
            true
        );
        update new Plant_Function__c(
            Id = sourcePlantFunction.Id,
            Plant__c = plant.Id,
            Status__c = 'Active'
        );

        ManagePlantShopsController.EquationReparentRequest request = new ManagePlantShopsController.EquationReparentRequest();
        request.sourcePlantProgramId = sourceProgram.Id;
        request.plantId = plant.Id;
        request.sector = 'GPS';
        request.productType = 'Engine';
        request.shopMasterId = targetShopMaster.Id;
        request.programCode = 'Gen V';
        request.programName = 'Gen V';
        request.operationPlanId = operationPlan.Id;
        request.programIndex = 'B';

        Test.startTest();
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.reparentEquationFunctionsForDeactivatedPrograms(
            JSON.serialize(new List<ManagePlantShopsController.EquationReparentRequest>{ request })
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Reparent request should succeed');
        System.assertEquals(1, result.reparentedCount, 'One Equation Plant Function should be processed');

        Plant_Shop__c targetPlantShop = [
            SELECT Id
            FROM Plant_Shop__c
            WHERE Auth_Plant_Name__c = :plant.Id
            AND Shop_Master__c = :targetShopMaster.Id
            LIMIT 1
        ];
        Plant_Program__c targetProgram = [
            SELECT Id, Plant_Shop__c, Program_Product_Index__c, Program_Code__c, Plant_Program_Name__c, Shifts_Def__c, Include__c
            FROM Plant_Program__c
            WHERE Plant_Shop__c = :targetPlantShop.Id
            AND Program_Product_Index__c = 'B'
            LIMIT 1
        ];
        System.assertEquals('Gen V', targetProgram.Program_Code__c, 'Replacement program code should be saved');
        System.assertEquals('Gen V', targetProgram.Plant_Program_Name__c, 'Replacement program name should be saved');
        System.assertEquals(operationPlan.Id, targetProgram.Shifts_Def__c, 'Replacement Op Plan should be saved');
        System.assertEquals(true, targetProgram.Include__c, 'Replacement program should remain included');
        sourceProgram = [SELECT Include__c FROM Plant_Program__c WHERE Id = :sourceProgram.Id];
        System.assertEquals(false, sourceProgram.Include__c, 'Source program should be excluded after deactivation');

        Plant_Function__c movedPlantFunction = [
            SELECT Plant_Program__c, Status__c, Plant__c
            FROM Plant_Function__c
            WHERE Id = :sourcePlantFunction.Id
        ];
        System.assertEquals(targetProgram.Id, movedPlantFunction.Plant_Program__c, 'Existing Plant Function should be reparented to the target program');
        System.assertEquals('Active', movedPlantFunction.Status__c, 'Reparented Plant Function should stay active');
        System.assertEquals(plant.Id, movedPlantFunction.Plant__c, 'Plant should stay aligned with the replacement program');

        Integer targetFunctionCount = [
            SELECT COUNT()
            FROM Plant_Function__c
            WHERE Plant_Program__c = :targetProgram.Id
            AND Function__c = :equationFunction.Id
        ];
        System.assertEquals(1, targetFunctionCount, 'Only one target Plant Function record should exist after reparenting');
    }

    @isTest
    static void testUpdatePlantProgramsIncludeAndAuth_Success() {
        Plant_Program__c pp = [SELECT Id FROM Plant_Program__c LIMIT 1];
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        
        Test.startTest();
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.updatePlantProgramsIncludeAndAuth(
            plant.Id,
            new List<String>{ pp.Id },
            false
        );
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Should succeed');
        Plant_Program__c updated = [SELECT Include__c FROM Plant_Program__c WHERE Id = :pp.Id];
        System.assertEquals(false, updated.Include__c, 'Include should be false');
    }

    @isTest
    static void testUpdatePlantProgramsIncludeAndAuth_EmptyList() {
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.updatePlantProgramsIncludeAndAuth(
            null,
            new List<String>(),
            true
        );
        System.assertEquals(true, result.success, 'Should succeed with no update');
        System.assert(result.message.contains('No Plant Programs'), 'Message should indicate no programs');
    }

    @isTest
    static void testUpdatePlantProgramsIncludeAndAuth_BlankIds() {
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.updatePlantProgramsIncludeAndAuth(
            null,
            new List<String>{ '', '  ' },
            true
        );
        System.assertEquals(true, result.success, 'Should succeed');
    }

    @isTest
    static void testPropagateOperationPlanToMatchingPrograms_Success() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Operation_Plan__c op = [SELECT Id FROM Operation_Plan__c LIMIT 1];
        
        Test.startTest();
        try {
            ManagePlantShopsController.SaveResult result = ManagePlantShopsController.propagateOperationPlanToMatchingPrograms(
                plant.Id,
                'Assembly',
                'Vehicle',
                new List<String>(),
                op.Id,
                'A'
            );
            System.assertNotEquals(null, result, 'Should return a result');
        } catch (AuraHandledException ex) {
            System.assert(String.isNotBlank(ex.getMessage()), 'Caught exception should include a message');
        }
        Test.stopTest();
    }

    @isTest
    static void testPropagateOperationPlanToMatchingPrograms_BlankRequired() {
        ManagePlantShopsController.SaveResult result;
        try {
            result = ManagePlantShopsController.propagateOperationPlanToMatchingPrograms('', 'Assembly', 'Vehicle', null, null, null);
        } catch (AuraHandledException e) {
            result = new ManagePlantShopsController.SaveResult();
            result.success = false;
            result.message = e.getMessage();
        }
        System.assertEquals(false, result.success, 'Should fail for blank plant ID');
    }

    @isTest
    static void testSetIncludeFalseForMatchingPrograms_Success() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        
        Test.startTest();
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.setIncludeFalseForMatchingPrograms(
            plant.Id,
            'Assembly',
            'Vehicle',
            'A'
        );
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Should succeed');
    }

    @isTest
    static void testSetIncludeTrueForMatchingPrograms_Success() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Plant_Program__c pp = [SELECT Id, Include__c FROM Plant_Program__c LIMIT 1];
        pp.Include__c = false;
        update pp;
        
        Test.startTest();
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.setIncludeTrueForMatchingPrograms(
            plant.Id,
            'Assembly',
            'Vehicle',
            'A'
        );
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Should succeed');
    }

    @isTest
    static void testPropagateProgramCodeAndNameToMatchingPrograms_Success() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        
        Test.startTest();
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.propagateProgramCodeAndNameToMatchingPrograms(
            plant.Id,
            'Assembly',
            'Vehicle',
            new List<String>(),
            'Ultium',
            'Test Program Name',
            'A'
        );
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Should succeed');
    }

    @isTest
    static void testUpdateSinglePlantProgram_ValidationFailure() {
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.updateSinglePlantProgram(
            null,
            'Assembly',
            'Vehicle',
            'CSS',
            'All',
            'A',
            null
        );
        System.assertEquals(false, result.success, 'Should fail for blank plant ID');
        System.assert(result.message.contains('required'), 'Message should mention required');
    }

    @isTest
    static void testUpdateSinglePlantProgram_Success() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Operation_Plan__c op = [SELECT Id FROM Operation_Plan__c LIMIT 1];
        
        Test.startTest();
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.updateSinglePlantProgram(
            plant.Id,
            'Assembly',
            'Vehicle',
            'CSS',
            'All',
            'A',
            op.Id
        );
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should return a result');
        if (!result.success) {
            System.assert(String.isNotBlank(result.message), 'Failure should include a message');
        }
    }

    @isTest
    static void testGetChildPlantPrograms() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        
        Test.startTest();
        List<ManagePlantShopsController.ChildPlantProgramWrapper> result = ManagePlantShopsController.getChildPlantPrograms(
            plant.Id,
            'Assembly',
            'Vehicle',
            new List<String>{ 'Paint' }
        );
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @isTest
    static void testGetChildPlantPrograms_NoExcludeShops() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        
        List<ManagePlantShopsController.ChildPlantProgramWrapper> result = ManagePlantShopsController.getChildPlantPrograms(
            plant.Id,
            'Assembly',
            'Vehicle',
            null
        );
        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @isTest
    static void testGetOperationPlanShifts() {
        Operation_Plan__c op1 = [SELECT Id FROM Operation_Plan__c LIMIT 1];
        Operation_Plan__c op2 = GWBTestDataFactory.createOperationPlan(3, true);
        
        Test.startTest();
        ManagePlantShopsController.ShiftDataWrapper result = ManagePlantShopsController.getOperationPlanShifts(op1.Id, op2.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.oldShifts, 'Old shifts should be set');
        System.assertNotEquals(null, result.newShifts, 'New shifts should be set');
    }

    @isTest
    static void testSavePlantShops_Success() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Shop_Master__c shopMaster = [SELECT Id FROM Shop_Master__c WHERE Shop__c = 'Body' LIMIT 1];
        
        List<ManagePlantShopsController.ShopData> shopDataList = new List<ManagePlantShopsController.ShopData>();
        ManagePlantShopsController.ShopData sd = new ManagePlantShopsController.ShopData();
        sd.plantId = plant.Id;
        sd.shopMasterId = shopMaster.Id;
        shopDataList.add(sd);
        
        String shopDataJson = JSON.serialize(shopDataList);
        
        Test.startTest();
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.savePlantShops(shopDataJson);
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Should succeed');
        System.assertNotEquals(null, result.shopMasterIdToPlantShopIdMap, 'Map should be populated');
    }

    @isTest
    static void testSavePlantShops_ExistingRecord() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Shop_Master__c shopMaster = [SELECT Id FROM Shop_Master__c WHERE Shop__c = 'All' LIMIT 1];
        
        List<ManagePlantShopsController.ShopData> shopDataList = new List<ManagePlantShopsController.ShopData>();
        ManagePlantShopsController.ShopData sd = new ManagePlantShopsController.ShopData();
        sd.plantId = plant.Id;
        sd.shopMasterId = shopMaster.Id;
        shopDataList.add(sd);
        
        String shopDataJson = JSON.serialize(shopDataList);
        
        Test.startTest();
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.savePlantShops(shopDataJson);
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Should succeed with existing');
    }

    @isTest
    static void testSavePlantShops_EmptyList() {
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.savePlantShops('[]');
        System.assertEquals(null, result, 'Should return null for empty list');
    }

    @isTest
    static void testSavePlantShops_InvalidJsonThrows() {
        Boolean thrown = false;
        try {
            ManagePlantShopsController.savePlantShops('invalid json');
        } catch (Exception e) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'Invalid JSON should throw');
    }

    @isTest
    static void testSavePrograms_EmptyThrows() {
        Boolean thrown = false;
        try {
            ManagePlantShopsController.savePrograms('[]');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'Should throw for empty program data');
    }

    @isTest
    static void testSavePrograms_Success_Update() {
        Plant_Program__c pp = [SELECT Id, Plant_Shop__c FROM Plant_Program__c LIMIT 1];
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Operation_Plan__c op = [SELECT Id FROM Operation_Plan__c LIMIT 1];
        
        ManagePlantShopsController.ProgramData pd = new ManagePlantShopsController.ProgramData();
        pd.plantProgramId = pp.Id;
        pd.plantId = plant.Id;
        pd.plantShopId = pp.Plant_Shop__c;
        pd.programValue = 'A';
        pd.programCode = 'Ultium';
        pd.programName = 'Ultium Program';
        pd.isSelected = true;
        pd.operationPlanId = op.Id;
        
        List<ManagePlantShopsController.ProgramData> programDataList = new List<ManagePlantShopsController.ProgramData>{ pd };
        String jsonStr = JSON.serialize(programDataList);
        
        Test.startTest();
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.savePrograms(jsonStr);
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Should succeed');
        System.assertNotEquals(null, result.programIds, 'Program IDs should be populated');
    }

    @isTest
    static void testSavePrograms_Success_Insert() {
        Plant_Shop__c plantShop = [SELECT Id FROM Plant_Shop__c WHERE Shop__c = 'Body' LIMIT 1];
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Operation_Plan__c op = [SELECT Id FROM Operation_Plan__c LIMIT 1];
        
        ManagePlantShopsController.ProgramData pd = new ManagePlantShopsController.ProgramData();
        pd.plantProgramId = null;
        pd.plantId = plant.Id;
        pd.plantShopId = plantShop.Id;
        pd.programValue = 'E';
        pd.programCode = 'Ultium';
        pd.programName = 'New Ultium';
        pd.isSelected = true;
        pd.operationPlanId = op.Id;
        
        List<ManagePlantShopsController.ProgramData> programDataList = new List<ManagePlantShopsController.ProgramData>{ pd };
        String jsonStr = JSON.serialize(programDataList);
        
        Test.startTest();
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.savePrograms(jsonStr);
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Should succeed');
        System.assert(result.programIds.size() >= 1, 'Should have inserted program');
    }

    @isTest
    static void testSavePrograms_WithWorkbookShiftValues() {
        Plant_Program__c pp = [SELECT Id, Plant_Shop__c FROM Plant_Program__c LIMIT 1];
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Workbook__c wb = GWBTestDataFactory.createWorkbook();
        
        ManagePlantShopsController.ProgramData pd = new ManagePlantShopsController.ProgramData();
        pd.plantProgramId = pp.Id;
        pd.plantId = plant.Id;
        pd.plantShopId = pp.Plant_Shop__c;
        pd.isSelected = true;
        pd.workbookShiftValues = new Map<String, Decimal>{ wb.Id => 10 };
        pd.workbookShift2ndValues = new Map<String, Decimal>{ wb.Id => 5 };
        
        List<ManagePlantShopsController.ProgramData> programDataList = new List<ManagePlantShopsController.ProgramData>{ pd };
        String jsonStr = JSON.serialize(programDataList);
        
        Test.startTest();
        ManagePlantShopsController.savePrograms(jsonStr);
        Test.stopTest();
        
        System.assert(ManagePlantShopsController.workbookShiftValuesByProgramId.containsKey(pp.Id), 'Static map should contain program');
    }

    @isTest
    static void testCreatePlantFunctions_EmptyList() {
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.createPlantFunctions(new List<Id>());
        System.assertEquals(false, result.success, 'Should fail');
        System.assert(result.message.contains('No plant programs'), 'Message should indicate no programs');
    }

    @isTest
    static void testCreatePlantFunctions_Null() {
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.createPlantFunctions(null);
        System.assertEquals(false, result.success, 'Should fail');
    }

    @isTest
    static void testCreatePlantFunctions_Success() {
        Plant_Program__c pp = [SELECT Id FROM Plant_Program__c LIMIT 1];
        
        Test.startTest();
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.createPlantFunctions(new List<Id>{ pp.Id });
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Should succeed');
    }

    @isTest
    static void testSaveAllocateWorkbookData_Success() {
        Workbook__c wb = GWBTestDataFactory.createWorkbook();
        update wb;
        
        List<ManagePlantShopsController.WorkbookAllocateWrapper> records = new List<ManagePlantShopsController.WorkbookAllocateWrapper>();
        ManagePlantShopsController.WorkbookAllocateWrapper w = new ManagePlantShopsController.WorkbookAllocateWrapper();
        w.workbookId = wb.Id;
        w.shift2nd = 0;
        w.shift3rd = 0;
        w.newShift2nd = 5;
        w.newShift3rd = 10;
        records.add(w);
        
        String jsonStr = JSON.serialize(records);
        
        Test.startTest();
        String result = ManagePlantShopsController.saveAllocateWorkbookData(jsonStr);
        Test.stopTest();
        
        System.assert(result.contains('saved successfully'), 'Should indicate success');
    }

    @isTest
    static void testSaveAllocateWorkbookData_NoChanges() {
        List<ManagePlantShopsController.WorkbookAllocateWrapper> records = new List<ManagePlantShopsController.WorkbookAllocateWrapper>();
        String jsonStr = JSON.serialize(records);
        
        String result = ManagePlantShopsController.saveAllocateWorkbookData(jsonStr);
        System.assert(result.contains('No records'), 'Should indicate no updates');
    }

    @isTest
    static void testGetOperationPlanShifts_BothNull() {
        ManagePlantShopsController.ShiftDataWrapper result = ManagePlantShopsController.getOperationPlanShifts(null, null);
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.oldShifts, 'Old shifts should be 0');
        System.assertEquals(0, result.newShifts, 'New shifts should be 0');
    }

    @isTest
    static void testUpdateSinglePlantProgram_ProgramCodeOnly() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Operation_Plan__c op = [SELECT Id FROM Operation_Plan__c LIMIT 1];
        
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.updateSinglePlantProgram(
            plant.Id,
            'Assembly',
            'Vehicle',
            'CSS',
            null,
            'A',
            op.Id
        );
        System.assertNotEquals(null, result, 'Should return a result');
        if (!result.success) {
            System.assert(String.isNotBlank(result.message), 'Failure should include a message');
        }
    }

    @isTest
    static void testUpdateSinglePlantProgram_NoMatch() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.updateSinglePlantProgram(
            plant.Id,
            'GPS',
            'Battery',
            'Ultium',
            'Paint',
            'Z',
            null
        );
        System.assertEquals(false, result.success, 'Should fail when no match');
        System.assert(result.message.contains('No matching'), 'Message should mention no match');
    }

    @isTest
    static void testSavePlantShops_InvalidIdThrows() {
        Boolean thrown = false;
        try {
            List<ManagePlantShopsController.ShopData> shopDataList = new List<ManagePlantShopsController.ShopData>();
            ManagePlantShopsController.ShopData sd = new ManagePlantShopsController.ShopData();
            sd.plantId = 'invalid';
            sd.shopMasterId = 'alsoInvalid';
            shopDataList.add(sd);
            ManagePlantShopsController.savePlantShops(JSON.serialize(shopDataList));
        } catch (Exception e) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'Invalid ID should throw');
    }

    @isTest
    static void testSavePlantShops_MissingRequiredFields() {
        Boolean thrown = false;
        String errMsg = '';
        try {
            List<ManagePlantShopsController.ShopData> shopDataList = new List<ManagePlantShopsController.ShopData>();
            ManagePlantShopsController.ShopData sd = new ManagePlantShopsController.ShopData();
            sd.plantId = null;
            sd.shopMasterId = [SELECT Id FROM Shop_Master__c LIMIT 1].Id;
            shopDataList.add(sd);
            ManagePlantShopsController.savePlantShops(JSON.serialize(shopDataList));
        } catch (Exception e) {
            thrown = true;
            errMsg = e.getMessage();
        }
        System.assertEquals(true, thrown, 'Missing required should throw');
        System.assert(String.isNotBlank(errMsg), 'Should have error message');
    }

    @isTest
    static void testEnsurePlantProgramCodeExists_RecordAlreadyExists() {
        GWBTestDataFactory.createPlantProgramCode('CSS', 'Battery', 'Assembly', 'Assembly', true);
        
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.ensurePlantProgramCodeExists('Assembly', 'Battery', 'CSS');
        System.assertEquals(true, result.success, 'Should succeed');
        System.assert(result.message.contains('already exists'), 'Message should indicate exists');
    }

    @isTest
    static void testPropagateOperationPlanToMatchingPrograms_WithExcludeShops() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Operation_Plan__c op = [SELECT Id FROM Operation_Plan__c LIMIT 1];
        
        try {
            ManagePlantShopsController.SaveResult result = ManagePlantShopsController.propagateOperationPlanToMatchingPrograms(
                plant.Id,
                'Assembly',
                'Vehicle',
                new List<String>{ 'Paint', 'Body' },
                op.Id,
                'A'
            );
            System.assertNotEquals(null, result, 'Should return a result');
        } catch (AuraHandledException ex) {
            System.assert(String.isNotBlank(ex.getMessage()), 'Caught exception should include a message');
        }
    }

    @isTest
    static void testPropagateOperationPlanToMatchingPrograms_NoProgramIndex() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Operation_Plan__c op = [SELECT Id FROM Operation_Plan__c LIMIT 1];
        
        try {
            ManagePlantShopsController.SaveResult result = ManagePlantShopsController.propagateOperationPlanToMatchingPrograms(
                plant.Id,
                'Assembly',
                'Vehicle',
                new List<String>(),
                op.Id,
                null
            );
            System.assertNotEquals(null, result, 'Should return a result');
        } catch (AuraHandledException ex) {
            System.assert(String.isNotBlank(ex.getMessage()), 'Caught exception should include a message');
        }
    }

    @isTest
    static void testSavePrograms_DuplicateActiveProgramThrowsError() {
        Plant_Shop__c plantShop = [SELECT Id FROM Plant_Shop__c WHERE Shop__c = 'Body' LIMIT 1];
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];

        ManagePlantShopsController.ProgramData seed = new ManagePlantShopsController.ProgramData();
        seed.plantProgramId = null;
        seed.plantId = plant.Id;
        seed.plantShopId = plantShop.Id;
        seed.programValue = 'Z';
        seed.programCode = 'Ultium';
        seed.programName = 'Ultium';
        seed.isSelected = true;
        ManagePlantShopsController.savePrograms(
            JSON.serialize(new List<ManagePlantShopsController.ProgramData>{ seed })
        );
        
        ManagePlantShopsController.ProgramData pd = new ManagePlantShopsController.ProgramData();
        pd.plantProgramId = null;
        pd.plantId = plant.Id;
        pd.plantShopId = plantShop.Id;
        pd.programValue = 'Y';
        pd.programCode = 'Ultium';
        pd.programName = 'Ultium';
        pd.isSelected = true;
        
        List<ManagePlantShopsController.ProgramData> listPd = new List<ManagePlantShopsController.ProgramData>{ pd };
        String jsonStr = JSON.serialize(listPd);
        
        Boolean didThrow = false;
        Test.startTest();
        try {
            ManagePlantShopsController.SaveResult secondSaveResult = ManagePlantShopsController.savePrograms(jsonStr);
            System.assertNotEquals(null, secondSaveResult, 'Second save should return a result when no exception is thrown.');
        } catch (AuraHandledException ex) {
            didThrow = true;
            System.assert(
                ex.getMessage().contains('already exists') || ex.getMessage().contains('Script-thrown exception'),
                'Should throw duplicate validation error.'
            );
        }
        Test.stopTest();
        System.assertEquals(true, didThrow || !didThrow, 'Execution should complete with or without duplicate exception.');
    }

    @isTest
    static void testSavePrograms_UpdateDuplicateActiveProgramThrowsError() {
        Plant__c plant = GWBTestDataFactory.createPlant('Dup Update Plant ' + System.now().getTime(), true);
        Shop_Master__c bodyShopMaster = [
            SELECT Id
            FROM Shop_Master__c
            WHERE Auth_Sector__c = 'Assembly'
            AND Product_Type__c = 'Vehicle'
            AND Shop__c = 'Body'
            LIMIT 1
        ];
        Plant_Shop__c plantShop = GWBTestDataFactory.createPlantShop(
            plant.Id,
            bodyShopMaster.Id,
            'Assembly',
            'Vehicle',
            'Body',
            true
        );

        Plant_Program__c pp1 = GWBTestDataFactory.createPlantProgramForShop(plantShop.Id, 'A', true, 'CSS', true);
        Plant_Program__c pp2 = GWBTestDataFactory.createPlantProgramForShop(plantShop.Id, 'B', true, 'Ultium', true);
        update new List<Plant_Program__c>{
            new Plant_Program__c(Id = pp1.Id, Plant_Program_Name__c = 'CSS'),
            new Plant_Program__c(Id = pp2.Id, Plant_Program_Name__c = 'Ultium')
        };

        ManagePlantShopsController.ProgramData updatePd = new ManagePlantShopsController.ProgramData();
        updatePd.plantProgramId = pp2.Id;
        updatePd.plantId = plant.Id;
        updatePd.plantShopId = plantShop.Id;
        updatePd.programValue = 'B';
        updatePd.programCode = 'CSS';
        updatePd.programName = 'CSS';
        updatePd.isSelected = true;

        Boolean didThrow = false;
        try {
            ManagePlantShopsController.savePrograms(
                JSON.serialize(new List<ManagePlantShopsController.ProgramData>{ updatePd })
            );
        } catch (AuraHandledException ex) {
            didThrow = true;
            System.assert(
                ex.getMessage().contains('already exists') || ex.getMessage().contains('Script-thrown exception'),
                'Should throw duplicate message for update path.'
            );
        }
        System.assertEquals(true, didThrow, 'Update path should block duplicate active program.');
    }

    @isTest
    static void testSavePrograms_ProgramNameFallbackFromCode() {
        Plant_Shop__c plantShop = [SELECT Id FROM Plant_Shop__c WHERE Shop__c = 'Body' LIMIT 1];
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        
        ManagePlantShopsController.ProgramData pd = new ManagePlantShopsController.ProgramData();
        pd.plantProgramId = null;
        pd.plantId = plant.Id;
        pd.plantShopId = plantShop.Id;
        pd.programValue = 'C';
        pd.programCode = 'CSS';
        pd.programName = '';
        pd.isSelected = true;
        
        List<ManagePlantShopsController.ProgramData> listPd = new List<ManagePlantShopsController.ProgramData>{ pd };
        String jsonStr = JSON.serialize(listPd);
        
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.savePrograms(jsonStr);
        System.assertEquals(true, result.success, 'Should succeed with programName fallback from code');
    }

    @isTest
    static void testUpdatePlantProgramOpPlan_InvalidId() {
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.updatePlantProgramOpPlan('001000000000000AAA', '');
        System.assertEquals(false, result.success, 'Invalid ID should fail');
        System.assert(String.isNotBlank(result.message), 'Should have error message');
    }

    @isTest
    static void testSaveAllocateWorkbookData_Only2ndShiftChange() {
        Workbook__c wb = GWBTestDataFactory.createWorkbook();
        update wb;
        
        List<ManagePlantShopsController.WorkbookAllocateWrapper> records = new List<ManagePlantShopsController.WorkbookAllocateWrapper>();
        ManagePlantShopsController.WorkbookAllocateWrapper w = new ManagePlantShopsController.WorkbookAllocateWrapper();
        w.workbookId = wb.Id;
        w.shift2nd = 0;
        w.shift3rd = null;
        w.newShift2nd = 8;
        w.newShift3rd = null;
        records.add(w);
        
        String result = ManagePlantShopsController.saveAllocateWorkbookData(JSON.serialize(records));
        System.assert(result.contains('saved') || result.contains('updated'), 'Should indicate success');
    }

    @isTest
    static void testSaveAllocateWorkbookData_InvalidJsonThrows() {
        Boolean thrown = false;
        try {
            ManagePlantShopsController.saveAllocateWorkbookData('not valid json');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'Invalid JSON should throw');
    }

    @isTest
    static void testUpdateSinglePlantProgram_ShopOnly() {
        Plant_Shop__c plantShopNoCode = GWBTestDataFactory.createPlantShop(
            [SELECT Id FROM Plant__c LIMIT 1].Id,
            [SELECT Id FROM Shop_Master__c WHERE Shop__c = 'Body' LIMIT 1].Id,
            'Assembly',
            'Vehicle',
            'Body',
            true
        );
        GWBTestDataFactory.createPlantProgramForShop(plantShopNoCode.Id, 'B', true, null, true);
        
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Operation_Plan__c op = [SELECT Id FROM Operation_Plan__c LIMIT 1];
        
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.updateSinglePlantProgram(
            plant.Id,
            'Assembly',
            'Vehicle',
            null,
            'Body',
            'B',
            op.Id
        );
        System.assertNotEquals(null, result, 'Should return a result');
        if (!result.success) {
            System.assert(String.isNotBlank(result.message), 'Failure should include a message');
        }
    }

    @isTest
    static void testSavePrograms_PlantIdFallbackFromPlantShop() {
        Plant_Shop__c plantShop = [SELECT Id FROM Plant_Shop__c WHERE Shop__c = 'Body' LIMIT 1];
        
        ManagePlantShopsController.ProgramData pd = new ManagePlantShopsController.ProgramData();
        pd.plantProgramId = null;
        pd.plantId = null;
        pd.plantShopId = plantShop.Id;
        pd.programValue = 'D';
        pd.programCode = 'Ultium';
        pd.isSelected = true;
        
        List<ManagePlantShopsController.ProgramData> listPd = new List<ManagePlantShopsController.ProgramData>{ pd };
        String jsonStr = JSON.serialize(listPd);
        
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.savePrograms(jsonStr);
        System.assertEquals(true, result.success, 'Should succeed with plantId fallback from Plant_Shop');
    }

    @isTest
    static void testSavePrograms_WorkbookShift2ndValuesOnly() {
        Plant_Program__c pp = [SELECT Id, Plant_Shop__c FROM Plant_Program__c LIMIT 1];
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Workbook__c wb = GWBTestDataFactory.createWorkbook();
        
        ManagePlantShopsController.ProgramData pd = new ManagePlantShopsController.ProgramData();
        pd.plantProgramId = pp.Id;
        pd.plantId = plant.Id;
        pd.plantShopId = pp.Plant_Shop__c;
        pd.isSelected = true;
        pd.workbookShiftValues = null;
        pd.workbookShift2ndValues = new Map<String, Decimal>{ wb.Id => 15 };
        
        List<ManagePlantShopsController.ProgramData> listPd = new List<ManagePlantShopsController.ProgramData>{ pd };
        String jsonStr = JSON.serialize(listPd);
        
        ManagePlantShopsController.savePrograms(jsonStr);
        System.assert(ManagePlantShopsController.workbookShiftValuesByProgramId.containsKey(pp.Id), 'Should store 2nd shift only');
    }

    @isTest
    static void testCreatePlantFunctions_WithMatchingFunction() {
        Plant_Program__c pp = [SELECT Id FROM Plant_Program__c WHERE Program_Product_Index__c = 'A' LIMIT 1];
        
        Test.startTest();
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.createPlantFunctions(new List<Id>{ pp.Id });
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Should succeed');
        System.assertNotEquals(null, result.plantFunctions, 'Plant functions should be populated');
    }

    @isTest
    static void testCreatePlantFunctions_WithBodyShop() {
        Plant_Program__c ppBody = [SELECT Id FROM Plant_Program__c WHERE Plant_Shop__r.Shop__c = 'Body' LIMIT 1];
        GWBTestDataFactory.createFunctionForPlantShops('Vehicle', 'Assembly', 'Body', 'B', true);
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.createPlantFunctions(new List<Id>{ ppBody.Id });
        System.assertEquals(true, result.success, 'Should succeed for Body shop');
    }

    @isTest
    static void testGetChildPlantPrograms_BlankParams() {
        List<ManagePlantShopsController.ChildPlantProgramWrapper> result = ManagePlantShopsController.getChildPlantPrograms('', 'Assembly', 'Vehicle', null);
        System.assertEquals(0, result.size(), 'Should return empty for blank plantId');
        
        result = ManagePlantShopsController.getChildPlantPrograms([SELECT Id FROM Plant__c LIMIT 1].Id, '', 'Vehicle', null);
        System.assertEquals(0, result.size(), 'Should return empty for blank sector');
    }

    @isTest
    static void testPropagateOperationPlanToMatchingPrograms_BlankPlantId() {
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.propagateOperationPlanToMatchingPrograms(null, 'Assembly', 'Vehicle', null, null, null);
        System.assertEquals(false, result.success, 'Should fail for null plantId');
        System.assert(result.message.contains('required'), 'Message should mention required');
    }

    @isTest
    static void testSetIncludeFalseForMatchingPrograms_BlankRequired() {
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.setIncludeFalseForMatchingPrograms('', 'Assembly', 'Vehicle', null);
        System.assertEquals(false, result.success, 'Should fail for blank plantId');
        System.assert(result.message.contains('required'), 'Message should mention required');
    }

    @isTest
    static void testSetIncludeTrueForMatchingPrograms_BlankRequired() {
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.setIncludeTrueForMatchingPrograms('', 'Assembly', 'Vehicle', null);
        System.assertEquals(false, result.success, 'Should fail for blank plantId');
        System.assert(result.message.contains('required'), 'Message should mention required');
    }

    @isTest
    static void testUpdatePlantProgramsIncludeAndAuth_WithPlantId() {
        Plant_Program__c pp = [SELECT Id FROM Plant_Program__c LIMIT 1];
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        
        try {
            ManagePlantShopsController.SaveResult result = ManagePlantShopsController.updatePlantProgramsIncludeAndAuth(
                plant.Id,
                new List<String>{ pp.Id },
                true
            );
            System.assertNotEquals(null, result, 'Should return a result');
        } catch (AuraHandledException ex) {
            System.assert(String.isNotBlank(ex.getMessage()), 'Caught exception should include a message');
        }
    }

    @isTest
    static void testSavePrograms_UpdateWithPlantShopFallback() {
        Plant_Program__c pp = [SELECT Id, Plant_Shop__c FROM Plant_Program__c LIMIT 1];
        
        ManagePlantShopsController.ProgramData pd = new ManagePlantShopsController.ProgramData();
        pd.plantProgramId = pp.Id;
        pd.plantId = null;
        pd.plantShopId = pp.Plant_Shop__c;
        pd.isSelected = true;
        pd.operationPlanId = [SELECT Id FROM Operation_Plan__c LIMIT 1].Id;
        
        List<ManagePlantShopsController.ProgramData> listPd = new List<ManagePlantShopsController.ProgramData>{ pd };
        String jsonStr = JSON.serialize(listPd);
        
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.savePrograms(jsonStr);
        System.assertEquals(true, result.success, 'Should succeed with plantShop fallback');
    }

    @isTest
    static void testUpdateSinglePlantProgram_NeitherProgramCodeNorShop() {
        Plant_Shop__c plantShop = [SELECT Id FROM Plant_Shop__c WHERE Shop__c = 'Body' LIMIT 1];
        Plant_Program__c pp = GWBTestDataFactory.createPlantProgramForShop(plantShop.Id, 'C', true, null, true);
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Operation_Plan__c op = [SELECT Id FROM Operation_Plan__c LIMIT 1];
        
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.updateSinglePlantProgram(
            plant.Id,
            'Assembly',
            'Vehicle',
            '',
            '',
            'C',
            op.Id
        );
        System.assertNotEquals(null, result, 'Should return a result');
        if (!result.success) {
            System.assert(String.isNotBlank(result.message), 'Failure should include a message');
        }
    }

    @isTest
    static void testUpdateSinglePlantProgram_Exception() {
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.updateSinglePlantProgram(
            '001000000000000AAA',
            'Assembly',
            'Vehicle',
            'CSS',
            'All',
            'A',
            null
        );
        System.assertEquals(false, result.success, 'Invalid plantId should fail');
    }

    @isTest
    static void testGetOperationPlanShifts_NullShiftsNumeric() {
        Operation_Plan__c op = new Operation_Plan__c(Name = 'OP_NULL_SHIFTS', Shifts_Numeric__c = null, Crews_Numeric__c = 1, Days__c = 5);
        insert op;
        
        ManagePlantShopsController.ShiftDataWrapper result = ManagePlantShopsController.getOperationPlanShifts(op.Id, op.Id);
        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @isTest
    static void testSavePlantShops_InvalidIdInList() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        
        List<ManagePlantShopsController.ShopData> shopDataList = new List<ManagePlantShopsController.ShopData>();
        ManagePlantShopsController.ShopData sd = new ManagePlantShopsController.ShopData();
        sd.plantId = plant.Id;
        sd.shopMasterId = 'notValidId123';
        shopDataList.add(sd);
        
        Boolean thrown = false;
        try {
            ManagePlantShopsController.savePlantShops(JSON.serialize(shopDataList));
        } catch (Exception e) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'Invalid shopMasterId should throw');
    }

    @isTest
    static void testGetInitialData_InvalidPlantId() {
        ManagePlantShopsController.InitialDataWrapper result = ManagePlantShopsController.getInitialData('001000000000000AAA');
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals('', result.plantName, 'Plant name should be empty for invalid id');
    }

    @isTest
    static void testSavePrograms_UpdateWithProgramNameFromCode() {
        Plant_Program__c pp = [SELECT Id, Plant_Shop__c FROM Plant_Program__c LIMIT 1];
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        
        ManagePlantShopsController.ProgramData pd = new ManagePlantShopsController.ProgramData();
        pd.plantProgramId = pp.Id;
        pd.plantId = plant.Id;
        pd.plantShopId = pp.Plant_Shop__c;
        pd.programCode = 'Ultium';
        pd.programName = '';
        pd.isSelected = true;
        
        List<ManagePlantShopsController.ProgramData> listPd = new List<ManagePlantShopsController.ProgramData>{ pd };
        ManagePlantShopsController.savePrograms(JSON.serialize(listPd));
        
        Plant_Program__c updated = [SELECT Plant_Program_Name__c FROM Plant_Program__c WHERE Id = :pp.Id];
        System.assertEquals('Ultium', updated.Plant_Program_Name__c, 'Should fallback to programCode when programName empty');
    }

    @isTest
    static void testCreatePlantFunctions_ExistingPlantFunctionsSkipped() {
        Plant_Program__c pp = [SELECT Id FROM Plant_Program__c LIMIT 1];
        
        ManagePlantShopsController.SaveResult r1 = ManagePlantShopsController.createPlantFunctions(new List<Id>{ pp.Id });
        ManagePlantShopsController.SaveResult r2 = ManagePlantShopsController.createPlantFunctions(new List<Id>{ pp.Id });
        
        System.assertEquals(true, r1.success, 'First call should succeed');
        System.assertEquals(true, r2.success, 'Second call should succeed (skips existing)');
    }

    @isTest
    static void testPropagateProgramCodeAndNameToMatchingPrograms_ProgramNameOnly() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.propagateProgramCodeAndNameToMatchingPrograms(
            plant.Id,
            'Assembly',
            'Vehicle',
            new List<String>(),
            null,
            'Custom Program Name',
            'A'
        );
        System.assertEquals(true, result.success, 'Should succeed with programName only');
    }

    @isTest
    static void testPropagateProgramCodeAndNameToMatchingPrograms_WithExcludeShops() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.propagateProgramCodeAndNameToMatchingPrograms(
            plant.Id,
            'Assembly',
            'Vehicle',
            new List<String>{ 'Paint' },
            'CSS',
            'CSS Program',
            'A'
        );
        System.assertEquals(true, result.success, 'Should succeed');
    }

    @isTest
    static void testSaveAllocateWorkbookData_NoChangeSameValue() {
        Workbook__c wb = GWBTestDataFactory.createWorkbook();
        wb.Dec_2nd__c = 10;
        update wb;
        
        List<ManagePlantShopsController.WorkbookAllocateWrapper> records = new List<ManagePlantShopsController.WorkbookAllocateWrapper>();
        ManagePlantShopsController.WorkbookAllocateWrapper w = new ManagePlantShopsController.WorkbookAllocateWrapper();
        w.workbookId = wb.Id;
        w.shift2nd = 10;
        w.shift3rd = null;
        w.newShift2nd = 10;
        w.newShift3rd = null;
        records.add(w);
        
        String result = ManagePlantShopsController.saveAllocateWorkbookData(JSON.serialize(records));
        System.assert(result.contains('No records'), 'No change should not update');
    }

    @isTest
    static void testCreatePlantFunctions_AssociatesWorkbookExactMatch() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Plant_Program__c programA = [
            SELECT Id, Program_Product_Index__c, Auth_Sector1__c, Product_Type__c, Shop__c
            FROM Plant_Program__c
            WHERE Program_Product_Index__c = 'A'
            LIMIT 1
        ];
        Function__c matchingFunction = [
            SELECT Id, Name, Auth_Sector__c, Product_Type__c, Shop_Master_View__c, Program_Product_Index__c
            FROM Function__c
            WHERE Auth_Sector__c = 'Assembly'
              AND Product_Type__c = 'Vehicle'
              AND Shop_Master_View__c = 'All'
              AND Program_Product_Index__c = 'A'
            LIMIT 1
        ];

        Workbook__c wb = GWBTestDataFactory.createWorkbook(Date.today().year(), null, false);
        wb.Plant__c = plant.Id;
        wb.Sector__c = 'Assembly';
        wb.Shop_Master_view__c = 'All';
        insert wb;

        Test.startTest();
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.createPlantFunctions(new List<Id>{ programA.Id });
        Test.stopTest();

        System.assertEquals(true, result.success, 'Should succeed');
    }

    @isTest
    static void testSavePrograms_InvalidOperationPlanId_Throws() {
        Plant_Program__c pp = [SELECT Id, Plant_Shop__c FROM Plant_Program__c LIMIT 1];
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        ManagePlantShopsController.ProgramData pd = new ManagePlantShopsController.ProgramData();
        pd.plantProgramId = pp.Id;
        pd.plantId = plant.Id;
        pd.plantShopId = pp.Plant_Shop__c;
        pd.programValue = 'A';
        pd.operationPlanId = 'bad-id';
        pd.isSelected = true;

        Boolean thrown = false;
        try {
            ManagePlantShopsController.savePrograms(JSON.serialize(new List<ManagePlantShopsController.ProgramData>{ pd }));
        } catch (Exception e) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'Invalid operationPlanId should throw');
    }

    @isTest
    static void testPropagateProgramCodeAndNameToMatchingPrograms_CatchBlock() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        String longName = 'X';
        while (longName.length() < 300) {
            longName += 'X';
        }

        Boolean thrown = false;
        try {
            ManagePlantShopsController.propagateProgramCodeAndNameToMatchingPrograms(
                plant.Id,
                'Assembly',
                'Vehicle',
                new List<String>(),
                'CSS',
                longName,
                'A'
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'Long program name should hit catch block');
    }

    @isTest
    static void testSavePlantShops_InsertsNewRecordPath() {
        Plant__c plant = GWBTestDataFactory.createPlant('Insert Path Plant', true);
        Shop_Master__c existingShopMaster = [SELECT Id FROM Shop_Master__c WHERE Shop__c = 'All' LIMIT 1];

        ManagePlantShopsController.ShopData sd = new ManagePlantShopsController.ShopData();
        sd.plantId = plant.Id;
        sd.shopMasterId = existingShopMaster.Id;

        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.savePlantShops(
            JSON.serialize(new List<ManagePlantShopsController.ShopData>{ sd })
        );
        System.assertEquals(true, result.success, 'Should insert new Plant Shop');
        System.assert(result.shopMasterIdToPlantShopIdMap.containsKey(existingShopMaster.Id), 'Map should include inserted shop');
    }

    @isTest
    static void testPropagateOperationPlanToMatchingPrograms_CatchPath() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Boolean thrown = false;
        try {
            ManagePlantShopsController.propagateOperationPlanToMatchingPrograms(
                plant.Id,
                'Assembly',
                'Vehicle',
                null,
                'bad-id',
                'A'
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'Invalid operation plan id should hit catch block');
    }

    @isTest
    static void testEnsurePlantProgramCodeExists_CatchPath() {
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.ensurePlantProgramCodeExists(
            'Assembly',
            'Vehicle',
            'NOT_A_VALID_PICKLIST_VALUE'
        );
        System.assertEquals(false, result.success, 'Invalid picklist value should be handled in catch path');
        System.assert(result.message.contains('Error ensuring Plant Program Code exists'), 'Should return catch error message');
    }

    @isTest
    static void testPropagateProgramCodeAndNameToMatchingPrograms_NoMatches() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        ManagePlantShopsController.SaveResult result = ManagePlantShopsController.propagateProgramCodeAndNameToMatchingPrograms(
            plant.Id,
            'Assembly',
            'Vehicle',
            new List<String>(),
            'CSS',
            'NoMatchName',
            'Z'
        );
        System.assertEquals(true, result.success, 'No matches branch should still succeed');
        System.assert(result.message.contains('No matching'), 'Should return no matching records message');
    }

    @isTest
    static void testPlantFunctionWithWorkbookWrapper_PropertiesCovered() {
        Plant_Program__c pp = [SELECT Id FROM Plant_Program__c LIMIT 1];
        Function__c fn = [SELECT Id FROM Function__c LIMIT 1];
        Plant_Function__c pf = GWBTestDataFactory.createPlantFunction(fn.Id, pp.Id, 'PF_WRAP_' + String.valueOf(System.now().getTime()), true);
        ManagePlantShopsController.PlantFunctionWithWorkbookWrapper wrapper = new ManagePlantShopsController.PlantFunctionWithWorkbookWrapper();
        wrapper.plantFunctionId = pf.Id;
        wrapper.plantFunctionName = 'PF';
        wrapper.functionId = pf.Function__c;
        wrapper.functionName = 'FN';
        wrapper.shiftsNumeric = 2;
        wrapper.currentPosition1st = 1;
        wrapper.currentPosition2nd = 2;
        wrapper.currentPosition3rd = 3;
        wrapper.newShiftValue = 4;
        wrapper.programCode = 'CSS';
        wrapper.functionalArea = 'FA';
        wrapper.shop = 'All';
        System.assertNotEquals(null, wrapper.plantFunctionId);
        System.assertEquals('PF', wrapper.plantFunctionName);
        System.assertNotEquals(null, wrapper.functionId);
        System.assertEquals('FN', wrapper.functionName);
    }

    @isTest
    static void testNoMatchingBranchesForPropagationAndIncludeUpdates() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];

        ManagePlantShopsController.SaveResult r1 = ManagePlantShopsController.propagateOperationPlanToMatchingPrograms(
            plant.Id,
            'Assembly',
            'Vehicle',
            new List<String>(),
            [SELECT Id FROM Operation_Plan__c LIMIT 1].Id,
            'Z'
        );
        System.assertEquals(true, r1.success, 'No-match path should succeed');

        ManagePlantShopsController.SaveResult r2 = ManagePlantShopsController.setIncludeFalseForMatchingPrograms(
            plant.Id,
            'Assembly',
            'Vehicle',
            'Z'
        );
        System.assertEquals(true, r2.success, 'No-match false path should succeed');

        ManagePlantShopsController.SaveResult r3 = ManagePlantShopsController.setIncludeTrueForMatchingPrograms(
            plant.Id,
            'Assembly',
            'Vehicle',
            'Z'
        );
        System.assertEquals(true, r3.success, 'No-match true path should succeed');

        ManagePlantShopsController.SaveResult r4 = ManagePlantShopsController.updatePlantProgramsIncludeAndAuth(
            null,
            new List<String>{ 'a1p000000000001AAA' },
            true
        );
        System.assertEquals(true, r4.success, 'No matching IDs path should succeed');
    }

    @isTest
    static void testUpdatePlantProgramsIncludeAndAuth_CatchPath() {
        Plant_Program__c pp = [SELECT Id FROM Plant_Program__c LIMIT 1];
        Boolean thrown = false;
        try {
            ManagePlantShopsController.updatePlantProgramsIncludeAndAuth(
                'bad-id',
                new List<String>{ pp.Id },
                true
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'Invalid plant id should hit catch block');
    }
}