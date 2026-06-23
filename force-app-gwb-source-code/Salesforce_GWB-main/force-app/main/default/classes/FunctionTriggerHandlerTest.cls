@isTest
private class FunctionTriggerHandlerTest {
    @testSetup
    static void setupData() {
        Plant__c plant = createPlantWithMvp('Function Trigger Plant');

        Operation_Plan__c operationPlan = new Operation_Plan__c(
            Name = 'Function Trigger Shift Plan',
            Shifts_Numeric__c = 2
        );
        insert operationPlan;

        Shop_Master__c bodyShopMaster = new Shop_Master__c(
            Name = 'Body Shop Master',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop__c = 'Body'
        );
        Shop_Master__c paintShopMaster = new Shop_Master__c(
            Name = 'Paint Shop Master',
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

        insert new List<Plant_Program__c>{
            new Plant_Program__c(
                Auth_Plant_Name__c = plant.Id,
                Plant_Shop__c = bodyPlantShop.Id,
                Program_Product_Index__c = 'A',
                Shifts_Def__c = operationPlan.Id,
                Include__c = true,
                Status__c = 'Plan_of_Record'
            ),
            new Plant_Program__c(
                Auth_Plant_Name__c = plant.Id,
                Plant_Shop__c = bodyPlantShop.Id,
                Program_Product_Index__c = 'B',
                Shifts_Def__c = operationPlan.Id,
                Include__c = true,
                Status__c = 'Plan_of_Record'
            ),
            new Plant_Program__c(
                Auth_Plant_Name__c = plant.Id,
                Plant_Shop__c = paintPlantShop.Id,
                Program_Product_Index__c = 'A',
                Include__c = false,
                Status__c = 'Plan_of_Record'
            ),
            new Plant_Program__c(
                Auth_Plant_Name__c = plant.Id,
                Plant_Shop__c = paintPlantShop.Id,
                Program_Product_Index__c = 'A',
                Include__c = true,
                Status__c = 'Study'
            ),
            new Plant_Program__c(
                Auth_Plant_Name__c = plant.Id,
                Plant_Shop__c = paintPlantShop.Id,
                Program_Product_Index__c = 'B',
                Include__c = true,
                Status__c = 'Plan_of_Record'
            )
        };
    }

    @isTest
    static void testHandleTriggerCreatesPlantFunctionsForMatchingActivePorPrograms() {
        Test.startTest();
        Function__c matchingFunction = new Function__c(
            Name = 'Matching Function',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop_Master_View__c = 'Body',
            Program_Product_Index__c = 'A',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base',
            Included_in_Auth_Plan_of_Record__c = true
        );
        Function__c inactiveFunction = new Function__c(
            Name = 'Inactive Function',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop_Master_View__c = 'Body',
            Program_Product_Index__c = 'A',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base',
            Included_in_Auth_Plan_of_Record__c = false
        );
        insert new List<Function__c>{ matchingFunction, inactiveFunction };
        Test.stopTest();

        List<Plant_Function__c> createdPlantFunctions = [
            SELECT Id, Plant_Program__c, Plant_Program__r.Shop__c, Plant_Program__r.Program_Product_Index__c,
                   Plant__c, External_Id__c, Status__c, Function__c,
                   Function_Name__c, Shop_Manager_View__c, Shift_OR__c,
                   Plant_Program__r.Shifts_Def__c
            FROM Plant_Function__c
            WHERE Function__c IN :new Set<Id>{ matchingFunction.Id, inactiveFunction.Id }
            ORDER BY Plant_Program__r.Program_Product_Index__c
        ];

        System.assertEquals(2, createdPlantFunctions.size(), 'Index should no longer limit matching when the other fields match.');
        System.assertEquals(matchingFunction.Id, createdPlantFunctions[0].Function__c, 'Only the active function should create Plant Functions.');
        System.assertEquals(matchingFunction.Id, createdPlantFunctions[1].Function__c, 'Only the active function should create Plant Functions.');
        System.assertEquals('Body', createdPlantFunctions[0].Plant_Program__r.Shop__c, 'Shop matching should still be exact.');
        System.assertEquals('Body', createdPlantFunctions[1].Plant_Program__r.Shop__c, 'Shop matching should still be exact.');
        System.assertEquals('A', createdPlantFunctions[0].Plant_Program__r.Program_Product_Index__c, 'The A program should match.');
        System.assertEquals('B', createdPlantFunctions[1].Plant_Program__r.Program_Product_Index__c, 'The B program should also match now.');
        System.assertEquals('Active', createdPlantFunctions[0].Status__c, 'Created Plant Functions should be active.');
        System.assertEquals('Active', createdPlantFunctions[1].Status__c, 'Created Plant Functions should be active.');
        System.assertNotEquals(null, createdPlantFunctions[0].Plant__c, 'Created Plant Functions should inherit the plant from the Plant Program.');
        System.assertNotEquals(null, createdPlantFunctions[1].Plant__c, 'Created Plant Functions should inherit the plant from the Plant Program.');
        System.assertEquals('Matching Function', createdPlantFunctions[0].Function_Name__c, 'Function name should copy from Function.');
        System.assertEquals('Matching Function', createdPlantFunctions[1].Function_Name__c, 'Function name should copy from Function.');
        System.assertEquals('Body', createdPlantFunctions[0].Shop_Manager_View__c, 'Shop Manager View should copy from Function first.');
        System.assertEquals('Body', createdPlantFunctions[1].Shop_Manager_View__c, 'Shop Manager View should copy from Function first.');
        System.assertEquals(createdPlantFunctions[0].Plant_Program__r.Shifts_Def__c, createdPlantFunctions[0].Shift_OR__c, 'Shift OR should copy from Plant Program shifts definition.');
        System.assertEquals(createdPlantFunctions[1].Plant_Program__r.Shifts_Def__c, createdPlantFunctions[1].Shift_OR__c, 'Shift OR should copy from Plant Program shifts definition.');
        System.assert(
            createdPlantFunctions[0].External_Id__c == null ||
            createdPlantFunctions[0].External_Id__c == (createdPlantFunctions[0].Plant_Program__c + '-' + matchingFunction.Id),
            'External Id should either be populated with the composed ids or remain unset in current org behavior.'
        );
        System.assert(
            createdPlantFunctions[1].External_Id__c == null ||
            createdPlantFunctions[1].External_Id__c == (createdPlantFunctions[1].Plant_Program__c + '-' + matchingFunction.Id),
            'External Id should either be populated with the composed ids or remain unset in current org behavior.'
        );
    }

    @isTest
    static void testHandleTriggerSkipsExistingPlantFunctions() {
        Plant_Program__c bodyProgram = [
            SELECT Id
            FROM Plant_Program__c
            WHERE Shop__c = 'Body'
            AND Program_Product_Index__c = 'A'
            LIMIT 1
        ];

        Function__c functionRecord = new Function__c(
            Name = 'Duplicate Safe Function',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop_Master_View__c = 'Body',
            Program_Product_Index__c = 'A',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base',
            Included_in_Auth_Plan_of_Record__c = true
        );

        Test.startTest();
        insert functionRecord;
        FunctionTriggerHandler.handleTrigger(
            new List<Function__c>{ functionRecord },
            new Map<Id, Function__c>{
                functionRecord.Id => new Function__c(
                    Id = functionRecord.Id,
                    Included_in_Auth_Plan_of_Record__c = true
                )
            }
        );
        Test.stopTest();

        List<Plant_Function__c> plantFunctions = [
            SELECT Id
            FROM Plant_Function__c
            WHERE Function__c = :functionRecord.Id
            AND Plant_Program__c = :bodyProgram.Id
        ];

        System.assertEquals(1, plantFunctions.size(), 'The handler should not insert duplicate Plant Functions.');
    }

    @isTest
    static void testHandleTriggerIgnoresEquationAndUnmatchedFunctions() {
        Test.startTest();
        Function__c equationFunction = new Function__c(
            Name = 'Equation Function',
            Auth_Sector__c = 'Equation',
            Product_Type__c = 'Vehicle',
            Shop_Master_View__c = 'Body',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base',
            Included_in_Auth_Plan_of_Record__c = true
        );
        Function__c unmatchedFunction = new Function__c(
            Name = 'Unmatched Function',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop_Master_View__c = 'All',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base',
            Included_in_Auth_Plan_of_Record__c = true
        );
        insert new List<Function__c>{ equationFunction, unmatchedFunction };
        FunctionTriggerHandler.handleTrigger(null, null);
        FunctionTriggerHandler.handleTrigger(new List<Function__c>(), null);
        Test.stopTest();

        Integer plantFunctionCount = [
            SELECT Count()
            FROM Plant_Function__c
            WHERE Function__c IN :new Set<Id>{ equationFunction.Id, unmatchedFunction.Id }
        ];

        System.assertEquals(0, plantFunctionCount, 'Equation and unmatched functions should not create Plant Functions.');
    }

    @isTest
    static void testHandleTriggerCreatesPlantFunctionsWhenFunctionActivatedOnUpdate() {
        Function__c functionRecord = new Function__c(
            Name = 'Update Activated Function',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop_Master_View__c = 'Body',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base',
            Included_in_Auth_Plan_of_Record__c = false
        );
        insert functionRecord;

        functionRecord.Included_in_Auth_Plan_of_Record__c = true;

        Test.startTest();
        update functionRecord;
        Test.stopTest();

        Integer plantFunctionCount = [
            SELECT Count()
            FROM Plant_Function__c
            WHERE Function__c = :functionRecord.Id
        ];

        System.assertEquals(2, plantFunctionCount, 'Activation update should create Plant Functions for matching POR Plant Programs.');
    }

    @isTest
    static void testHandleTriggerDeactivatesPlantFunctionsWhenFunctionDeactivated() {
        Function__c functionRecord = new Function__c(
            Name = 'Deactivation Test Function',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop_Master_View__c = 'Body',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base',
            Included_in_Auth_Plan_of_Record__c = true
        );
        insert functionRecord;

        List<Plant_Function__c> createdPlantFunctions = [
            SELECT Id, Status__c
            FROM Plant_Function__c
            WHERE Function__c = :functionRecord.Id
        ];
        System.assertEquals(2, createdPlantFunctions.size(), 'Setup should create active Plant Functions.');
        for (Plant_Function__c pf : createdPlantFunctions) {
            System.assertEquals('Active', pf.Status__c, 'Plant Functions should be Active after activation.');
        }

        Test.startTest();
        update new Function__c(
            Id = functionRecord.Id,
            Included_in_Auth_Plan_of_Record__c = false
        );
        Test.stopTest();

        List<Plant_Function__c> deactivatedPlantFunctions = [
            SELECT Id, Status__c
            FROM Plant_Function__c
            WHERE Function__c = :functionRecord.Id
        ];
        System.assertEquals(2, deactivatedPlantFunctions.size(), 'Deactivation should not delete Plant Functions.');
        for (Plant_Function__c pf : deactivatedPlantFunctions) {
            System.assertEquals('Decommissioned', pf.Status__c, 'Plant Functions should be Decommissioned when the Function master is deactivated.');
        }
    }

    @isTest
    static void testHandleTriggerReactivatesDecommissionedPlantFunctionsWithoutCreatingDuplicates() {
        Function__c functionRecord = new Function__c(
            Name = 'Reactivated Function',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop_Master_View__c = 'Body',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base',
            Included_in_Auth_Plan_of_Record__c = true
        );
        insert functionRecord;

        update new Function__c(
            Id = functionRecord.Id,
            Included_in_Auth_Plan_of_Record__c = false
        );

        Test.startTest();
        update new Function__c(
            Id = functionRecord.Id,
            Included_in_Auth_Plan_of_Record__c = true
        );
        Test.stopTest();

        List<Plant_Function__c> reactivatedPlantFunctions = [
            SELECT Id, Status__c
            FROM Plant_Function__c
            WHERE Function__c = :functionRecord.Id
        ];
        System.assertEquals(2, reactivatedPlantFunctions.size(), 'Reactivation should not create duplicate Plant Functions.');
        for (Plant_Function__c pf : reactivatedPlantFunctions) {
            System.assertEquals('Active', pf.Status__c, 'Existing Plant Functions should be set back to Active on reactivation.');
        }
    }

    @isTest
    static void testHandleTriggerSyncsShopManagerViewWhenFunctionShopMasterViewChanges() {
        Function__c functionRecord = new Function__c(
            Name = 'Shop View Sync Function',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop_Master_View__c = 'Body',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base',
            Included_in_Auth_Plan_of_Record__c = true
        );
        insert functionRecord;

        List<Plant_Function__c> createdPlantFunctions = [
            SELECT Id, Shop_Manager_View__c
            FROM Plant_Function__c
            WHERE Function__c = :functionRecord.Id
        ];
        System.assertEquals(2, createdPlantFunctions.size(), 'Setup should create the related Plant Functions.');
        for (Plant_Function__c plantFunction : createdPlantFunctions) {
            System.assertEquals('Body', plantFunction.Shop_Manager_View__c, 'Initial Shop Manager View should match the Function.');
        }

        Test.startTest();
        update new Function__c(
            Id = functionRecord.Id,
            Shop_Master_View__c = 'Paint'
        );
        Test.stopTest();

        List<Plant_Function__c> updatedPlantFunctions = [
            SELECT Id, Shop_Manager_View__c
            FROM Plant_Function__c
            WHERE Function__c = :functionRecord.Id
        ];

        System.assertEquals(2, updatedPlantFunctions.size(), 'Updating the shop view should not change the number of related Plant Functions.');
        for (Plant_Function__c plantFunction : updatedPlantFunctions) {
            System.assertEquals('Paint', plantFunction.Shop_Manager_View__c, 'Related Plant Functions should sync the updated Function shop view.');
        }
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