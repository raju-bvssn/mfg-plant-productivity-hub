@isTest
private class PlantFunctionMatchingHelperTest {
    @testSetup
    static void setupData() {
        Plant__c plant = createPlantWithMvp('Helper Test Plant');

        Operation_Plan__c operationPlan = new Operation_Plan__c(
            Name = 'Helper Test Shift Plan',
            Shifts_Numeric__c = 2
        );
        insert operationPlan;

        Shop_Master__c shopMaster = new Shop_Master__c(
            Name = 'Helper Test Shop Master',
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

        insert new Plant_Program__c(
            Auth_Plant_Name__c = plant.Id,
            Plant_Shop__c = plantShop.Id,
            Program_Product_Index__c = 'A',
            Shifts_Def__c = operationPlan.Id,
            Include__c = true,
            Status__c = 'Plan_of_Record'
        );

        insert new Function__c(
            Name = 'Helper Match Function',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop_Master_View__c = 'Body',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base',
            Included_in_Auth_Plan_of_Record__c = true
        );
    }

    @isTest
    static void testGeneratePlantFunctionAndBuildPlantFunctions() {
        Plant_Program__c program = [
            SELECT Id, Auth_Plant_Name__c, Plant_Shop__r.Auth_Plant_Name__c, Shop__c,
                   Shifts_Def__c,
                   Auth_Sector1__c, Product_Type__c
            FROM Plant_Program__c
            LIMIT 1
        ];
        Function__c functionRecord = [
            SELECT Id, Name, Auth_Sector__c, Product_Type__c, Shop_Master_View__c
            FROM Function__c
            LIMIT 1
        ];

        Plant_Function__c generated = PlantFunctionMatchingHelper.generatePlantFunction(program, functionRecord);
        List<Plant_Function__c> built = PlantFunctionMatchingHelper.buildPlantFunctions(
            new List<Function__c>{ functionRecord },
            new List<Plant_Program__c>{ program }
        );

        System.assertEquals(program.Id, generated.Plant_Program__c, 'Plant Program should be copied.');
        System.assertEquals(functionRecord.Id, generated.Function__c, 'Function should be copied.');
        System.assertEquals(program.Auth_Plant_Name__c, generated.Plant__c, 'Plant should come from Plant Program.');
        System.assertEquals(program.Shifts_Def__c, generated.Shift_OR__c, 'Shift OR should come from Plant Program shifts definition.');
        System.assertEquals(functionRecord.Name, generated.Function_Name__c, 'Function name should copy from Function.');
        System.assertEquals('Body', generated.Shop_Manager_View__c, 'Shop manager view should be text from Function shop master view.');
        System.assertEquals('Active', generated.Status__c, 'Status should be Active.');
        System.assertEquals(1, built.size(), 'A matching program/function pair should build one Plant Function.');
    }

    @isTest
    static void testCriteriaAndEquationBranches() {
        Plant_Program__c program = [
            SELECT Id, Auth_Sector1__c, Product_Type__c, Shop__c
            FROM Plant_Program__c
            LIMIT 1
        ];

        Function__c matchingFunction = new Function__c(
            Name = 'Criteria Match',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop_Master_View__c = 'Body',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base'
        );
        Function__c wrongSectorFunction = new Function__c(
            Name = 'Criteria Wrong Sector',
            Auth_Sector__c = 'GPS',
            Product_Type__c = 'Vehicle',
            Shop_Master_View__c = 'Body',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base'
        );
        Function__c wrongProductFunction = new Function__c(
            Name = 'Criteria Wrong Product',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Battery',
            Shop_Master_View__c = 'Body',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base'
        );
        Function__c wrongShopFunction = new Function__c(
            Name = 'Criteria Wrong Shop',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop_Master_View__c = 'Paint',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base'
        );
        Function__c equationFunction = new Function__c(
            Name = 'Criteria Equation',
            Auth_Sector__c = 'Equation',
            Product_Type__c = 'Vehicle',
            Shop_Master_View__c = 'Body',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base'
        );

        System.assertEquals(true, PlantFunctionMatchingHelper.checkMeetsCriteria(matchingFunction, program), 'Expected a direct match.');
        System.assertEquals(
            true,
            PlantFunctionMatchingHelper.checkMeetsCriteria(matchingFunction, program, new Map<String, List<String>>()),
            'The overload should delegate to the same match logic.'
        );
        System.assertEquals(false, PlantFunctionMatchingHelper.checkMeetsCriteria(wrongSectorFunction, program), 'Wrong sector should not match.');
        System.assertEquals(false, PlantFunctionMatchingHelper.checkMeetsCriteria(wrongProductFunction, program), 'Wrong product should not match.');
        System.assertEquals(false, PlantFunctionMatchingHelper.checkMeetsCriteria(wrongShopFunction, program), 'Wrong shop should not match.');
        System.assertEquals(false, PlantFunctionMatchingHelper.checkMeetsCriteria(equationFunction, program), 'Equation functions should not match.');
        System.assertEquals(true, PlantFunctionMatchingHelper.isEquationFunction(equationFunction), 'Equation helper should detect equation values.');
        System.assertEquals(false, PlantFunctionMatchingHelper.isEquationFunction(matchingFunction), 'Non-equation function should not be flagged.');
        System.assertEquals(0, PlantFunctionMatchingHelper.getShopWithAllPrefixMap(new List<Plant_Program__c>{ program }).size(), 'All-prefix helper should now be empty.');
    }

    @isTest
    static void testBuildPlantFunctionsNullInputs() {
        Plant_Program__c program = [
            SELECT Id, Auth_Sector1__c, Product_Type__c, Shop__c
            FROM Plant_Program__c
            LIMIT 1
        ];
        Function__c functionRecord = [
            SELECT Id, Name, Auth_Sector__c, Product_Type__c, Shop_Master_View__c
            FROM Function__c
            LIMIT 1
        ];

        System.assertEquals(
            0,
            PlantFunctionMatchingHelper.buildPlantFunctions(null, new List<Plant_Program__c>{ program }).size(),
            'Null functions should return an empty result.'
        );
        System.assertEquals(
            0,
            PlantFunctionMatchingHelper.buildPlantFunctions(new List<Function__c>{ functionRecord }, null).size(),
            'Null programs should return an empty result.'
        );
    }

    @isTest
    static void testGeneratePlantFunctionFallsBackToPlantShopPlant() {
        Plant__c fallbackPlant = createPlantWithMvp('Helper Fallback Plant');

        Plant_Program__c program = new Plant_Program__c();
        program.Plant_Shop__r = new Plant_Shop__c(Auth_Plant_Name__c = fallbackPlant.Id);

        Function__c functionRecord = new Function__c(
            Name = 'Fallback Function',
            Auth_Sector__c = 'Assembly',
            Product_Type__c = 'Vehicle',
            Shop_Master_View__c = 'Body',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base'
        );

        Plant_Function__c generated = PlantFunctionMatchingHelper.generatePlantFunction(program, functionRecord);

        System.assertEquals(fallbackPlant.Id, generated.Plant__c, 'Plant should fall back to the Plant Shop plant when the Plant Program plant is null.');
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