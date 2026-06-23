public with sharing class PlantFunctionMatchingHelper {
    public static final String ACTIVE_PLANT_FUNCTION_STATUS = 'Active';
    public static final String DECOMMISSIONED_PLANT_FUNCTION_STATUS = 'Decommissioned';
    public static final String ACTIVE_PLANT_PROGRAM_STATUS = 'Plan_of_Record';

    public static Boolean isEquationFunction(Function__c functionRecord) {
        return (
            functionRecord.Auth_Sector__c == 'Equation' ||
            functionRecord.Product_Type__c == 'Equation' ||
            functionRecord.Shop_Master_View__c == 'Equation'
        );
    }

    public static Plant_Function__c generatePlantFunction(Plant_Program__c program, Function__c functionRecord) {
        Id plantId = program.Auth_Plant_Name__c != null
            ? program.Auth_Plant_Name__c
            : (program.Plant_Shop__r != null ? program.Plant_Shop__r.Auth_Plant_Name__c : null);

        return new Plant_Function__c(
            Plant_Program__c = program.Id,
            Function__c = functionRecord.Id,
            Plant__c = plantId,
            Shift_OR__c = program.Shifts_Def__c,
            Function_Name__c = functionRecord.Name,
            Shop_Manager_View__c = String.valueOf(functionRecord.Shop_Master_View__c),
            Status__c = ACTIVE_PLANT_FUNCTION_STATUS
        );
    }

    public static List<Plant_Function__c> buildPlantFunctions(
        List<Function__c> functions,
        List<Plant_Program__c> programs
    ) {
        List<Plant_Function__c> plantFunctionsToInsert = new List<Plant_Function__c>();
        if (functions == null || programs == null) {
            return plantFunctionsToInsert;
        }

        for (Plant_Program__c program : programs) {
            for (Function__c functionRecord : functions) {
                if (checkMeetsCriteria(functionRecord, program)) {
                    plantFunctionsToInsert.add(generatePlantFunction(program, functionRecord));
                }
            }
        }

        return plantFunctionsToInsert;
    }

    public static Boolean checkMeetsCriteria(Function__c functionRecord, Plant_Program__c program) {
        if (isEquationFunction(functionRecord)) {
            return false;
        }

        String programShop = String.isBlank(program.Shop__c) ? '' : program.Shop__c;

        if (program.Auth_Sector1__c != functionRecord.Auth_Sector__c) {
            return false;
        }
        if (program.Product_Type__c != functionRecord.Product_Type__c) {
            return false;
        }
        if (programShop != functionRecord.Shop_Master_View__c) {
            return false;
        }

        return true;
    }

    public static Boolean checkMeetsCriteria(
        Function__c functionRecord,
        Plant_Program__c program,
        Map<String, List<String>> ignoredShopMap
    ) {
        return checkMeetsCriteria(functionRecord, program);
    }

    public static Map<String, List<String>> getShopWithAllPrefixMap(List<Plant_Program__c> programs) {
        return new Map<String, List<String>>();
    }
}