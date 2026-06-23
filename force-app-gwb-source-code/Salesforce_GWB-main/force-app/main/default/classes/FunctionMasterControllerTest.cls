@isTest
public class FunctionMasterControllerTest {

    @testSetup
    static void setupData() {

        // Create Function
        Function__c func = new Function__c(Name = 'Test Function', Classification__c = 'Direct OTS',
                                           Base_Supp__c = 'Base', Cost__c = 'CoSup');
        insert func;
        
        Plant__c plant = GWBTestDataFactory.createPlant(
            'FM_TestPlant_' + String.valueOf(System.now().getTime()),
            true
        );

        // Get Record Types for Plant Program
        Map<String, Schema.RecordTypeInfo> rtMap = 
            Schema.SObjectType.Plant_Program__c.getRecordTypeInfosByDeveloperName();

        Id porRT = rtMap.containsKey('Plan_of_Record') 
            ? rtMap.get('Plan_of_Record').getRecordTypeId() 
            : null;

        Id studyRT = rtMap.containsKey('Study') 
            ? rtMap.get('Study').getRecordTypeId() 
            : null;

        // Create Plant Programs
        List<Plant_Program__c> programs = new List<Plant_Program__c>();

        if (porRT != null) {
            programs.add(new Plant_Program__c(
                //Name = 'POR Program',
                RecordTypeId = porRT,
                Auth_Plant_Name__c = plant.Id
            ));
        }

        if (studyRT != null) {
            programs.add(new Plant_Program__c(
               // Name = 'Study Program',
                RecordTypeId = studyRT,
                Auth_Plant_Name__c = plant.Id
            ));
        }

        if (programs.isEmpty()) {
            programs.add(new Plant_Program__c(
                Auth_Plant_Name__c = plant.Id,
                Program_Product_Index__c = 'A'
            ));
        }
        insert programs;

        // Create Plant Functions
        List<Plant_Function__c> pfList = new List<Plant_Function__c>();

        for (Plant_Program__c prog : programs) {
            pfList.add(new Plant_Function__c(
                //Name = 'PF - ' + prog.Name,
                Function__c = func.Id,
                Plant_Program__c = prog.Id,
                Function_Name__c = 'Test Function'
            ));
        }

        insert pfList;

        Integer currentYear = Date.today().year();

        // Create Workbook records
        List<Workbook__c> wbList = new List<Workbook__c>();

        for (Plant_Function__c pf : pfList) {

            wbList.add(new Workbook__c(
                Plant_Function__c = pf.Id,
                Year__c = currentYear,
				
                Jan_1st__c = 5,
                Jan_2nd__c = 5,
                Jan_3rd__c = 5,
                Feb_1st__c = 5,
                Feb_2nd__c = 5,
                Feb_3rd__c = 5,
                Mar_1st__c = 5,
                Mar_2nd__c = 5,
                Mar_3rd__c = 5,
                Apr_1st__c = 5,
                Apr_2nd__c = 5,
                Apr_3rd__c = 5,
                May_1st__c = 5,
                May_2nd__c = 5,
                May_3rd__c = 5,
                Jun_1st__c = 5,
                Jun_2nd__c = 5,
                Jun_3rd__c = 5,
                Jul_1st__c = 5,
                Jul_2nd__c = 5,
                Jul_3rd__c = 5,
                Aug_1st__c = 5,
                Aug_2nd__c = 5,
                Aug_3rd__c = 5,
                Sep_1st__c = 5,
                Sep_2nd__c = 5,
                Sep_3rd__c = 5,
                Oct_1st__c = 5,
                Oct_2nd__c = 5,
                Oct_3rd__c = 5,
                Nov_1st__c = 5,
                Nov_2nd__c = 5,
                Nov_3rd__c = 5,
                Dec_1st__c = 5,
                Dec_2nd__c = 5,
                Dec_3rd__c = 5
            ));
        }

        insert wbList;
    }

    @isTest
    static void testGetPlantProgramData() {

        // Fetch Function
        Function__c func = [SELECT Id FROM Function__c LIMIT 1];

        Test.startTest();
        Map<String, Object> result =
            FunctionMasterController.getPlantProgramData(func.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.size() > 0, 'Result should have data');

        // Validate structure
        for (String key : result.keySet()) {

            Map<String, Object> section =
                (Map<String, Object>) result.get(key);

            System.assert(section.containsKey('programCount'));
            System.assert(section.containsKey('programs'));

            List<Object> programs =
                (List<Object>) section.get('programs');

            System.assert(programs.size() > 0, 'Programs should exist');

            for (Object obj : programs) {

                Map<String, Object> prog =
                    (Map<String, Object>) obj;

                System.assert(prog.containsKey('programId'));
                System.assert(prog.containsKey('programName'));
                System.assert(prog.containsKey('positions'));

                Decimal positions = (Decimal) prog.get('positions');
                System.assertNotEquals(null, positions, 'Positions should always be present in response payload.');
                System.assert(positions >= 0, 'Positions should never be negative.');
            }
        }
    }

    @isTest
    static void testNoWorkbookData() {

        // Create new Function (no workbook data)
        Function__c func = new Function__c(Name = 'No Workbook Function', Classification__c = 'Direct OTS',
                                           Base_Supp__c = 'Base', Cost__c = 'CoSup');
        insert func;

        Test.startTest();
        Map<String, Object> result =
            FunctionMasterController.getPlantProgramData(func.Id);
        Test.stopTest();

        // Should not fail even if no data
        System.assertNotEquals(null, result);
    }
}