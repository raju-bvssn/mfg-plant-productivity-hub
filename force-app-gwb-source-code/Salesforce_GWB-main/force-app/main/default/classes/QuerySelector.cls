/**
 * @description       : Query Selector class for Manage Plant Shops functionality
 * @last modified on  : 01-15-2025
 **/
public with sharing class QuerySelector {
    
    /**
     * Get all active Shop_Master__c records
     */
    public static List<Shop_Master__c> getActiveShopMasters() {
        return [
            SELECT Id, 
                   Name,
                   Auth_Sector__c,
                   Product_Type__c,
                   Shop__c,
                   Program_Product__c,
                   Default_Program__c,
                   Active__c
            FROM Shop_Master__c
            WHERE Active__c = true
            ORDER BY Auth_Sector__c, Product_Type__c, Shop__c
        ];
    }
    
    /**
     * Get Plant_Shop__c records for a specific plant with related Plant_Programs
     */
    public static List<Plant_Shop__c> getPlantShopsByPlantId(String plantId) {
        return [
            SELECT Id,
                   Name,
                   Auth_Plant_Name__c,
                   Shop_Master__c,
                   Auth_Sector__c,
                   Product_Type__c,
                   Shop__c,
                   (SELECT Id,
                           Name,
                           Program_Product_Index__c,
                           Program_Code__c,
                           Plant_Program_Name__c,
                           Include__c,
                           Shifts_Def__c,
                           Plant_Shop__c
                    FROM Plant_Programs__r)
            FROM Plant_Shop__c
            WHERE Auth_Plant_Name__c = :plantId
            ORDER BY Auth_Sector__c, Product_Type__c, Shop__c
        ];
    }
    
    /**
     * Get Plant_Program__c records by IDs
     */
    public static List<Plant_Program__c> getPlantProgramsByIds(List<Id> plantProgramIds) {
        return [
            SELECT Id,
                   Name,
                   Plant_Shop__c,
                   Plant_Shop__r.Auth_Plant_Name__c,
                   Auth_Plant_Name__c,
                   Program_Product_Index__c,
                   Plant_Program_Name__c,
                   Program_Code__c,
                   Auth_Sector1__c,
                   Product_Type__c,
                   Shop__c,
                   Include__c,
                   Shifts_Def__c
            FROM Plant_Program__c
            WHERE Id IN :plantProgramIds
        ];
    }
    
    /**
     * Get all active Function__c records
     */
    public static List<Function__c> getAllFunctions() {
        return [
            SELECT Id,
                   Name,
                   Benchmark_Rule__c,
                   Auth_Sector__c,
                   Product_Type__c,
                   Shop_Master_View__c,
                   Program_Product_Index__c
            FROM Function__c WHERE Included_in_Auth_Plan_of_Record__c = true
        ];
    }
    
}