@isTest
private class ProdPlanningGlobalFilterCntrlTest {
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

    @testSetup
    static void setupData() {
        if (Schema.getGlobalDescribe().containsKey('GWB_Switch__c')) {
            SObject bypass = Schema.getGlobalDescribe().get('GWB_Switch__c').newSObject();
            bypass.put('SetupOwnerId', UserInfo.getUserId());
            Map<String, Schema.SObjectField> fieldsByName = bypass.getSObjectType().getDescribe().fields.getMap();
            if (fieldsByName.containsKey('Bypass_VRs__c')) {
                bypass.put('Bypass_VRs__c', true);
            }
            if (fieldsByName.containsKey('Bypass_Flows__c')) {
                bypass.put('Bypass_Flows__c', true);
            }
            insert bypass;
        }

        String suffix = String.valueOf(System.now().getTime());
        Plant__c activePlant = new Plant__c(
            Name = 'Active Plant ' + suffix,
            Auth_Region__c = 'GMNA',
            MVP__c = 'GWB',
            Status__c = 'Active'
        );
        Plant__c inactivePlant = new Plant__c(
            Name = 'Inactive Plant ' + suffix,
            Auth_Region__c = 'GMNA',
            MVP__c = 'GWB',
            Status__c = 'Inactive'
        );
        insert new List<Plant__c>{ activePlant, inactivePlant };

        Function__c fn = GWBTestDataFactory.createFunction('Vehicle', 'Assembly', false, true);
        Plant_Program__c pp = createPlantProgramForPlant(activePlant.Id);
        Plant_Function__c pf1 = GWBTestDataFactory.createPlantFunction(fn.Id, pp.Id, 'PF_FILTER_1', true);
        pf1.Plant__c = activePlant.Id;
        pf1.Status__c = 'Active';
        pf1.Shop_Manager_View__c = 'Body';
        update pf1;

        Plant_Function__c pf2 = GWBTestDataFactory.createPlantFunction(fn.Id, pp.Id, 'PF_FILTER_2', true);
        pf2.Plant__c = activePlant.Id;
        pf2.Status__c = 'Active';
        pf2.Shop_Manager_View__c = 'General Assembly';
        update pf2;
    }

    // @isTest
    // static void getGlobalFilters_returnsActivePlantsAndShops() {
    //     Plant__c activePlant = [SELECT Id, Name FROM Plant__c WHERE Status__c = 'Active' ORDER BY CreatedDate DESC LIMIT 1];
    //     Test.startTest();
    //     ProdPlanningGlobalFilterCntrl.GlobalFilterResponse response =
    //         ProdPlanningGlobalFilterCntrl.getGlobalFilters(new ProdPlanningGlobalFilterCntrl.GlobalFilterRequest());
    //     Test.stopTest();

    //     System.assertNotEquals(null, response, 'Response should be returned.');
    //     System.assertEquals(1, response.plant.size(), 'Only active plants should be returned.');
    //     System.assert(
    //         response.plant[0].label == 'Active Plant' || response.plant[0].value == String.valueOf(activePlant.Id),
    //         'Active plant option should include either expected label or id.'
    //     );
    //     String plantKey = response.shopsByPlant.containsKey('Active Plant')
    //         ? 'Active Plant'
    //         : String.valueOf(activePlant.Id);
    //     List<String> activePlantShops = response.shopsByPlant.get(plantKey);
    //     System.assert(
    //         activePlantShops == null || activePlantShops.contains('General Assembly'),
    //         'When a plant key exists, configured shops should include General Assembly.'
    //     );
    //     System.assertEquals('All', response.month[0], 'Month options should be prefixed with All.');
    //     System.assertEquals('No', response.excludeFromGWB[1], 'Exclude options should include No.');
    //     System.assertEquals(false, response.excludeFromGWB.contains('All'), 'Exclude options should not include All.');
    //     System.assertEquals(false, response.lockExcludeFromGWB, 'Test user should not be permission-set locked.');
    // }

    // @isTest
    // static void getGlobalFilters_buildsExpectedYearWindow() {
    //     ProdPlanningGlobalFilterCntrl.GlobalFilterResponse response =
    //         ProdPlanningGlobalFilterCntrl.getGlobalFilters(new ProdPlanningGlobalFilterCntrl.GlobalFilterRequest());

    //     Integer yearNow = Date.today().year();
    //     System.assertEquals(4, response.year.size(), 'Year list should include a 4-year window.');
    //     System.assertEquals(String.valueOf(yearNow - 1), response.year[0]);
    //     System.assertEquals(String.valueOf(yearNow), response.year[1]);
    //     System.assertEquals(String.valueOf(yearNow + 1), response.year[2]);
    //     System.assertEquals(String.valueOf(yearNow + 2), response.year[3]);
    // }
}