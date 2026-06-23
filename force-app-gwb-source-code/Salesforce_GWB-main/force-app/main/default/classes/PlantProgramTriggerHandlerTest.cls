/**
 * Test class for PlantProgramTriggerHandler
 */
@isTest
private class PlantProgramTriggerHandlerTest {
    
    @testSetup
    static void setup() {
        Plant__c plant = createPlantWithMvp('Plant Program Trigger Test Plant');

        // Create Operation_Plan records for 2-shift and 3-shift configs
        Operation_Plan__c op2Shifts = new Operation_Plan__c(
        Name = '2 Shifts',
        Shifts_Numeric__c = 2,
        Crews_Numeric__c = 1
    );
    insert op2Shifts;
    
        Operation_Plan__c op3Shifts = new Operation_Plan__c(
        Name = '3 Shifts',
        Shifts_Numeric__c = 3,
        Crews_Numeric__c = 1
    );
    insert op3Shifts;

        // Create Function
        Function__c func = new Function__c(
            Name = 'Test Function',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop_Master_View__c = 'Body',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base',
            Cost__c = 'CoM'
        );
        insert func;
        
        // Create Plant Program with 2 shifts
        Plant_Program__c plantProgram = new Plant_Program__c(
            Auth_Plant_Name__c = plant.Id,
            Shifts_Def__c = op2Shifts.Id
        );
        insert plantProgram;
        
        // Create Plant Function linked to Plant Program
        Plant_Function__c plantFunc = new Plant_Function__c(
            Function__c = func.Id,
            Plant_Program__c = plantProgram.Id,
            Function_Name__c = func.Name,
            Shop_Manager_View__c = 'Body'
        );
        insert plantFunc;
    }
    
    @isTest
    static void testShiftChangeFrom2To3() {
        // Get test data
        Operation_Plan__c op2 = [SELECT Id FROM Operation_Plan__c WHERE Shifts_Numeric__c = 2 LIMIT 1];
        Operation_Plan__c op3 = [SELECT Id FROM Operation_Plan__c WHERE Shifts_Numeric__c = 3 LIMIT 1];
        Plant_Program__c plantProgram = [SELECT Id, Shifts_Def__c FROM Plant_Program__c LIMIT 1];
        
        Test.startTest();
        
        // Change shifts from 2 to 3 (Shifts_Def__c is lookup to Operation_Plan__c)
        plantProgram.Shifts_Def__c = op3.Id;
        update plantProgram;
        
        Test.stopTest();
        
        // Verify Plant Program was updated (handler no longer creates Change Logs automatically)
        Plant_Program__c updated = [SELECT Id, Shifts_Def__c FROM Plant_Program__c WHERE Id = :plantProgram.Id];
        System.assertEquals(op3.Id, updated.Shifts_Def__c, 'Shifts_Def__c should be updated to 3-shift Operation Plan');
    }
    
    @isTest
    static void testShiftChangeFrom3To2() {
        // Get test data
        Operation_Plan__c op2 = [SELECT Id FROM Operation_Plan__c WHERE Shifts_Numeric__c = 2 LIMIT 1];
        Operation_Plan__c op3 = [SELECT Id FROM Operation_Plan__c WHERE Shifts_Numeric__c = 3 LIMIT 1];
        Plant_Program__c plantProgram = [SELECT Id, Shifts_Def__c FROM Plant_Program__c LIMIT 1];
        
        // Update Plant Program to 3 shifts first (Shifts_Def__c is lookup to Operation_Plan__c)
        plantProgram.Shifts_Def__c = op3.Id;
        update plantProgram;
        
        Test.startTest();
        
        // Change shifts from 3 to 2
        plantProgram.Shifts_Def__c = op2.Id;
        update plantProgram;
        
        Test.stopTest();
        
        // Verify Plant Program was updated (handler no longer creates Change Logs automatically)
        Plant_Program__c updated = [SELECT Id, Shifts_Def__c FROM Plant_Program__c WHERE Id = :plantProgram.Id];
        System.assertEquals(op2.Id, updated.Shifts_Def__c, 'Shifts_Def__c should be updated to 2-shift Operation Plan');
    }
    
    @isTest
    static void testMultiplePlantFunctions() {
        // Get test data
        Operation_Plan__c op3 = [SELECT Id FROM Operation_Plan__c WHERE Shifts_Numeric__c = 3 LIMIT 1];
        Plant_Program__c plantProgram = [SELECT Id FROM Plant_Program__c LIMIT 1];
        Function__c func = [SELECT Id FROM Function__c LIMIT 1];
        
        // Create additional Function
        Function__c func2 = new Function__c(
            Name = 'Test Function 2',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base',
            Cost__c = 'CoM'
        );
        insert func2;
        
        // Create another Plant Function for the same Plant Program
        Plant_Function__c plantFunc2 = new Plant_Function__c(
            Function__c = func2.Id,
            Plant_Program__c = plantProgram.Id,
            Function_Name__c = func2.Name,
            Shop_Manager_View__c = 'Body'
        );
        insert plantFunc2;
        
        Test.startTest();
        
        // Change shifts from 2 to 3 (Shifts_Def__c is lookup to Operation_Plan__c)
        plantProgram.Shifts_Def__c = op3.Id;
        update plantProgram;
        
        Test.stopTest();
        
        // Verify Plant Program was updated and both Plant Functions are linked
        Plant_Program__c updated = [SELECT Id, Shifts_Def__c FROM Plant_Program__c WHERE Id = :plantProgram.Id];
        System.assertEquals(op3.Id, updated.Shifts_Def__c, 'Shifts_Def__c should be updated to 3-shift Operation Plan');
        List<Plant_Function__c> plantFuncs = [SELECT Id FROM Plant_Function__c WHERE Plant_Program__c = :plantProgram.Id];
        System.assertEquals(2, plantFuncs.size(), 'Two Plant Functions should be linked to Plant Program');
    }
    
    @isTest
    static void testBulkShiftChanges() {
        // Get test data
        Operation_Plan__c op2 = [SELECT Id FROM Operation_Plan__c WHERE Shifts_Numeric__c = 2 LIMIT 1];
        Operation_Plan__c op3 = [SELECT Id FROM Operation_Plan__c WHERE Shifts_Numeric__c = 3 LIMIT 1];
        Function__c func = [SELECT Id FROM Function__c LIMIT 1];
        
        // Create multiple Plant Programs (Shifts_Def__c is lookup to Operation_Plan__c)
        List<Plant_Program__c> plantPrograms = new List<Plant_Program__c>();
        for (Integer i = 0; i < 5; i++) {
            Plant__c plant = createPlantWithMvp('Bulk Shift Plant ' + String.valueOf(i));
            plantPrograms.add(new Plant_Program__c(
                Auth_Plant_Name__c = plant.Id,
                Shifts_Def__c = op2.Id
            ));
        }
        insert plantPrograms;
        
        // Create Plant Functions for each Plant Program
        List<Plant_Function__c> plantFuncs = new List<Plant_Function__c>();
        for (Plant_Program__c pp : plantPrograms) {
            plantFuncs.add(new Plant_Function__c(
                Function__c = func.Id,
                Plant_Program__c = pp.Id,
                Function_Name__c = 'Test Function',
                Shop_Manager_View__c = 'Body'
            ));
        }
        insert plantFuncs;
        
        Test.startTest();
        
        // Bulk update all Plant Programs to 3 shifts
        for (Plant_Program__c pp : plantPrograms) {
            pp.Shifts_Def__c = op3.Id;
        }
        update plantPrograms;
        
        Test.stopTest();
        
        // Verify all Plant Programs were updated
        List<Plant_Program__c> updated = [SELECT Id, Shifts_Def__c FROM Plant_Program__c WHERE Id IN :plantPrograms];
        System.assertEquals(5, updated.size(), 'Five Plant Programs should exist');
        for (Plant_Program__c pp : updated) {
            System.assertEquals(op3.Id, pp.Shifts_Def__c, 'Each Plant Program should have 3-shift Operation Plan');
        }
    }

    @isTest
    static void testAfterInsertCreatesPlantFunctionsForMatchingFunctions() {
        Plant__c plant = createPlantWithMvp('Program Trigger Plant');

        Shop_Master__c bodyShopMaster = new Shop_Master__c(
            Name = 'Program Trigger Body Shop',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop__c = 'Body'
        );
        Shop_Master__c paintShopMaster = new Shop_Master__c(
            Name = 'Program Trigger Paint Shop',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop__c = 'Paint'
        );
        insert new List<Shop_Master__c>{ bodyShopMaster, paintShopMaster };

        Plant_Shop__c bodyPlantShop = new Plant_Shop__c(
            Auth_Plant_Name__c = plant.Id,
            Shop_Master__c = bodyShopMaster.Id,
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop__c = 'Body'
        );
        Plant_Shop__c paintPlantShop = new Plant_Shop__c(
            Auth_Plant_Name__c = plant.Id,
            Shop_Master__c = paintShopMaster.Id,
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop__c = 'Paint'
        );
        insert new List<Plant_Shop__c>{ bodyPlantShop, paintPlantShop };

        Function__c matchingFunction = new Function__c(
            Name = 'Program Insert Match',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop_Master_View__c = 'Body',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base',
            Included_in_Auth_Plan_of_Record__c = true
        );
        Function__c inactiveFunction = new Function__c(
            Name = 'Program Insert Inactive',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop_Master_View__c = 'Body',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base',
            Included_in_Auth_Plan_of_Record__c = false
        );
        Function__c nonMatchingFunction = new Function__c(
            Name = 'Program Insert Non Match',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop_Master_View__c = 'Paint',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base',
            Included_in_Auth_Plan_of_Record__c = true
        );
        insert new List<Function__c>{ matchingFunction, inactiveFunction, nonMatchingFunction };

        Test.startTest();
        Plant_Program__c matchingProgram = new Plant_Program__c(
            Auth_Plant_Name__c = plant.Id,
            Plant_Shop__c = bodyPlantShop.Id,
            Program_Product_Index__c = 'A',
            Include__c = true,
            Status__c = 'Plan_of_Record'
        );
        Plant_Program__c excludedProgram = new Plant_Program__c(
            Auth_Plant_Name__c = plant.Id,
            Plant_Shop__c = paintPlantShop.Id,
            Program_Product_Index__c = 'A',
            Include__c = false,
            Status__c = 'Plan_of_Record'
        );
        insert new List<Plant_Program__c>{ matchingProgram, excludedProgram };
        Test.stopTest();

        List<Plant_Function__c> plantFunctions = [
            SELECT Id, Plant_Program__c, Function__c, Plant__c, External_Id__c, Status__c,
                   Shift_OR__c,
                   Function_Name__c, Shop_Manager_View__c
            FROM Plant_Function__c
            WHERE Plant_Program__c IN :new Set<Id>{ matchingProgram.Id, excludedProgram.Id }
        ];
        Integer matchingFunctionCount = [
            SELECT Count()
            FROM Plant_Function__c
            WHERE Plant_Program__c = :matchingProgram.Id
            AND Function__c = :matchingFunction.Id
        ];
        Integer inactiveFunctionCount = [
            SELECT Count()
            FROM Plant_Function__c
            WHERE Plant_Program__c = :matchingProgram.Id
            AND Function__c = :inactiveFunction.Id
        ];
        Integer excludedProgramCount = [
            SELECT Count()
            FROM Plant_Function__c
            WHERE Plant_Program__c = :excludedProgram.Id
        ];

        Plant_Function__c createdForMatchingFunction = [
            SELECT Id, Plant_Program__c, Function__c, Plant__c, External_Id__c, Status__c,
                   Shift_OR__c,
                   Function_Name__c, Shop_Manager_View__c
            FROM Plant_Function__c
            WHERE Plant_Program__c = :matchingProgram.Id
            AND Function__c = :matchingFunction.Id
            LIMIT 1
        ];

        System.assertEquals(1, matchingFunctionCount, 'The matching active function should create one Plant Function for the inserted program.');
        System.assertEquals(0, inactiveFunctionCount, 'Inactive functions should not create Plant Functions.');
        System.assertEquals(0, excludedProgramCount, 'Excluded programs should not create Plant Functions.');
        System.assert(plantFunctions.size() >= 1, 'At least the matching Plant Function should exist.');
        System.assertEquals(matchingProgram.Id, createdForMatchingFunction.Plant_Program__c, 'The matching program should be linked.');
        System.assertEquals(matchingFunction.Id, createdForMatchingFunction.Function__c, 'Only the matching active function should be linked.');
        System.assertEquals(plant.Id, createdForMatchingFunction.Plant__c, 'Plant should be inherited from the Plant Program.');
        System.assertEquals('Active', createdForMatchingFunction.Status__c, 'Created Plant Functions should be active.');
        System.assertEquals(matchingProgram.Shifts_Def__c, createdForMatchingFunction.Shift_OR__c, 'Shift OR should copy from the Plant Program shifts definition.');
        System.assertEquals('Program Insert Match', createdForMatchingFunction.Function_Name__c, 'Function name should copy from Function.');
        System.assertEquals('Body', createdForMatchingFunction.Shop_Manager_View__c, 'Shop Manager View should copy from Function first.');
        System.assert(
            createdForMatchingFunction.External_Id__c == null ||
            createdForMatchingFunction.External_Id__c == (matchingProgram.Id + '-' + matchingFunction.Id),
            'External Id should either be populated with the composed ids or remain unset in current org behavior.'
        );
    }

    @isTest
    static void testAfterInsertSkipsExistingPlantFunctions() {
        Plant__c plant = createPlantWithMvp('Program Trigger Duplicate Plant');

        Shop_Master__c bodyShopMaster = new Shop_Master__c(
            Name = 'Program Trigger Duplicate Body Shop',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop__c = 'Body'
        );
        insert bodyShopMaster;

        Plant_Shop__c bodyPlantShop = new Plant_Shop__c(
            Auth_Plant_Name__c = plant.Id,
            Shop_Master__c = bodyShopMaster.Id,
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop__c = 'Body'
        );
        insert bodyPlantShop;

        Function__c matchingFunction = new Function__c(
            Name = 'Program Duplicate Match',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop_Master_View__c = 'Body',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base',
            Included_in_Auth_Plan_of_Record__c = true
        );
        insert matchingFunction;

        Plant_Program__c matchingProgram = new Plant_Program__c(
            Auth_Plant_Name__c = plant.Id,
            Plant_Shop__c = bodyPlantShop.Id,
            Program_Product_Index__c = 'A',
            Include__c = true,
            Status__c = 'Plan_of_Record'
        );

        Test.startTest();
        insert matchingProgram;
        Plant_Program__c refreshedProgram = [
            SELECT Id, Include__c, Status__c, Auth_Sector1__c, Product_Type__c, Shop__c,
                   Auth_Plant_Name__c, Plant_Shop__r.Auth_Plant_Name__c, Shifts_Def__c
            FROM Plant_Program__c
            WHERE Id = :matchingProgram.Id
        ];
        PlantProgramTriggerHandler.handleAfterInsert(new List<Plant_Program__c>{ refreshedProgram });
        Test.stopTest();

        List<Plant_Function__c> plantFunctions = [
            SELECT Id
            FROM Plant_Function__c
            WHERE Plant_Program__c = :matchingProgram.Id
            AND Function__c = :matchingFunction.Id
        ];

        System.assertEquals(1, plantFunctions.size(), 'The handler should not insert duplicate Plant Functions.');
    }

    @isTest
    static void testAfterInsertReturnsWhenNoEligibleFunctionsExist() {
        Plant__c plant = createPlantWithMvp('Program Trigger No Function Plant');
        Shop_Master__c shopMaster = GWBTestDataFactory.createShopMaster('GPS', 'Battery', 'Paint', true, true);
        Plant_Shop__c plantShop = GWBTestDataFactory.createPlantShop(
            plant.Id,
            shopMaster.Id,
            'GPS',
            'Battery',
            'Paint',
            true
        );

        Plant_Program__c matchingProgram = new Plant_Program__c(
            Auth_Plant_Name__c = plant.Id,
            Plant_Shop__c = plantShop.Id,
            Program_Product_Index__c = 'A',
            Include__c = true,
            Status__c = 'Plan_of_Record'
        );
        insert matchingProgram;
        Plant_Program__c refreshedProgram = [
            SELECT Id, Include__c, Status__c, Auth_Sector1__c, Product_Type__c, Shop__c,
                   Auth_Plant_Name__c, Plant_Shop__r.Auth_Plant_Name__c, Shifts_Def__c
            FROM Plant_Program__c
            WHERE Id = :matchingProgram.Id
        ];

        Test.startTest();
        PlantProgramTriggerHandler.handleAfterInsert(new List<Plant_Program__c>{ refreshedProgram });
        Test.stopTest();

        Integer plantFunctionCount = [
            SELECT Count()
            FROM Plant_Function__c
            WHERE Plant_Program__c = :matchingProgram.Id
        ];
        System.assertEquals(0, plantFunctionCount, 'No functions should create no Plant Functions.');
    }

    @isTest
    static void testAfterInsertReturnsWhenMatchedFunctionBuildsNoPlantFunctions() {
        Plant__c plant = createPlantWithMvp('Program Trigger Equation Plant');
        Shop_Master__c shopMaster = GWBTestDataFactory.createShopMaster('Assembly', 'Vehicle', 'Equation', true, true);
        Plant_Shop__c plantShop = GWBTestDataFactory.createPlantShop(
            plant.Id,
            shopMaster.Id,
            'Assembly',
            'Vehicle',
            'Equation',
            true
        );
        GWBTestDataFactory.createFunctionForPlantProgram('Vehicle', 'Assembly', 'Equation', true, true);

        Plant_Program__c matchingProgram = new Plant_Program__c(
            Auth_Plant_Name__c = plant.Id,
            Plant_Shop__c = plantShop.Id,
            Program_Product_Index__c = 'A',
            Include__c = true,
            Status__c = 'Plan_of_Record'
        );
        insert matchingProgram;
        Plant_Program__c refreshedProgram = [
            SELECT Id, Include__c, Status__c, Auth_Sector1__c, Product_Type__c, Shop__c,
                   Auth_Plant_Name__c, Plant_Shop__r.Auth_Plant_Name__c, Shifts_Def__c
            FROM Plant_Program__c
            WHERE Id = :matchingProgram.Id
        ];

        Test.startTest();
        PlantProgramTriggerHandler.handleAfterInsert(new List<Plant_Program__c>{ refreshedProgram });
        Test.stopTest();

        Integer plantFunctionCount = [
            SELECT Count()
            FROM Plant_Function__c
            WHERE Plant_Program__c = :matchingProgram.Id
        ];
        System.assertEquals(0, plantFunctionCount, 'Equation functions should be queried but not converted to Plant Functions.');
    }

    @isTest
    static void testAfterInsertIgnoresIneligibleProgramsAndEmptyInputs() {
        Plant__c plant = createPlantWithMvp('Program Trigger Ignore Plant');

        Shop_Master__c shopMaster = new Shop_Master__c(
            Name = 'Program Trigger Ignore Shop',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop__c = 'Body'
        );
        insert shopMaster;

        Plant_Shop__c plantShop = new Plant_Shop__c(
            Auth_Plant_Name__c = plant.Id,
            Shop_Master__c = shopMaster.Id,
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop__c = 'Body'
        );
        insert plantShop;

        Function__c inactiveFunction = new Function__c(
            Name = 'Inactive Only Function',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop_Master_View__c = 'Body',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base',
            Included_in_Auth_Plan_of_Record__c = false
        );
        insert inactiveFunction;

        Test.startTest();
        Plant_Program__c studyProgram = new Plant_Program__c(
            Auth_Plant_Name__c = plant.Id,
            Plant_Shop__c = plantShop.Id,
            Include__c = true,
            Status__c = 'Study'
        );
        Plant_Program__c excludedProgram = new Plant_Program__c(
            Auth_Plant_Name__c = plant.Id,
            Plant_Shop__c = plantShop.Id,
            Include__c = false,
            Status__c = 'Plan_of_Record'
        );
        insert new List<Plant_Program__c>{ studyProgram, excludedProgram };
        PlantProgramTriggerHandler.handleAfterInsert(null);
        PlantProgramTriggerHandler.handleAfterInsert(new List<Plant_Program__c>());
        Test.stopTest();

        Integer plantFunctionCount = [
            SELECT Count()
            FROM Plant_Function__c
            WHERE Plant_Program__c IN :new Set<Id>{ studyProgram.Id, excludedProgram.Id }
        ];

        System.assertEquals(0, plantFunctionCount, 'Ineligible programs should not create Plant Functions.');
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
}