/**
 * @description       : Controller for Manage Plant Shops LWC Component
 * @group             : 
 * @last modified on  : 01-15-2025
 * @last modified by  : 
**/
public with sharing class ManagePlantShopsController {

    private static Map<String, Plant_Program__c> plantProgramsMapping = new Map<String, Plant_Program__c>();
    
    // Static Map to store workbook shift values for trigger handler access
    // Key: Plant Program ID, Value: Map of Workbook ID -> shift values
    public static Map<Id, Map<Id, WorkbookShiftValues>> workbookShiftValuesByProgramId = new Map<Id, Map<Id, WorkbookShiftValues>>();
    
    // Inner class to store workbook shift values
    public class WorkbookShiftValues {
        public Decimal shift2ndValue { get; set; }
        public Decimal shift3rdValue { get; set; }
        
        public WorkbookShiftValues(Decimal shift2nd, Decimal shift3rd) {
            this.shift2ndValue = shift2nd;
            this.shift3rdValue = shift3rd;
        }
    }

    @AuraEnabled(cacheable=false)
    public static InitialDataWrapper getInitialData(String plantId) {
        InitialDataWrapper result = new InitialDataWrapper();
        result.plantName = ''; // Initialize to empty string
        result.plantAuthSector = '';
        
        // Query Plant Name from Name field of Plant__c object
        if (String.isNotBlank(plantId)) {
            try {
                List<Plant__c> plants = [
                    SELECT Id, Name, Auth_Sector__c
                    FROM Plant__c
                    WHERE Id = :plantId
                    LIMIT 1
                ];
                
                if (!plants.isEmpty()) {
                    Plant__c plant = plants[0];
                    if (String.isNotBlank(plant.Name)) {
                        result.plantName = plant.Name;
                    }
                    if (String.isNotBlank(plant.Auth_Sector__c)) {
                        result.plantAuthSector = plant.Auth_Sector__c;
                    }
                }
            } catch (Exception e) {
                System.debug('ERROR querying Plant Name: ' + e.getMessage());
            }
        } else {
            System.debug('WARNING: plantId parameter is blank');
        }
        
        
        // Query Program_Master__c records for this plant that are ready for assignment.
        if (String.isNotBlank(plantId)) {
            try {
                result.programMasters = [
                    SELECT Id, 
                           Plant_Name__c,
                           Sector__c,
                           Product__c,
                           Program_Code__c,
                           Ready_for_Plant_Assignment__c
                    FROM Program_Master__c
                    WHERE Plant_Name__c = :plantId
                    AND Ready_for_Plant_Assignment__c = true
                    ORDER BY Sector__c, Product__c, Program_Code__c
                ];
            } catch (Exception e) {
                System.debug('ERROR querying Program_Master__c: ' + e.getMessage());
                result.programMasters = new List<Program_Master__c>();
            }
        } else {
            result.programMasters = new List<Program_Master__c>();
        }
        
        // Query all active Shop_Master__c records
        result.shopMasters = QuerySelector.getActiveShopMasters();

        // Query existing Plant_Shop__c records for this plant
        result.plantShops = QuerySelector.getPlantShopsByPlantId(plantId);
        
        // Collect Plant Shop IDs
        Set<Id> plantShopIds = new Set<Id>();
        for (Plant_Shop__c ps : result.plantShops) {
            plantShopIds.add(ps.Id);
        }
        
        // Query Plant Programs directly for all matching plant shops
        List<Plant_Program__c> plantPrograms = [
            SELECT Id,
                   Name,
                   Plant_Shop__c,
                   Program_Product_Index__c,
                   Program_Code__c,
                   Plant_Program_Name__c,
                   Include__c,
                   Shifts_Def__c
            FROM Plant_Program__c
            WHERE Plant_Shop__c IN :plantShopIds
        ];
        
        // Build a set of original Plant Program IDs for filtering in LWC
        Set<Id> originalProgramIds = new Set<Id>();
        for (Plant_Program__c pp : plantPrograms) {
            originalProgramIds.add(pp.Id);
        }
        
        // Build shopPrograms map from filtered Plant Programs (only original, not cloned)
        Map<Id, List<Plant_Program__c>> shopPrograms = new Map<Id, List<Plant_Program__c>>();
        for (Plant_Program__c plantProgram : plantPrograms) {
            if (!shopPrograms.containsKey(plantProgram.Plant_Shop__c)) {
                shopPrograms.put(plantProgram.Plant_Shop__c, new List<Plant_Program__c>());
            }
            shopPrograms.get(plantProgram.Plant_Shop__c).add(plantProgram);
        }
        result.shopPrograms = shopPrograms;
        
        // Store original program IDs in a wrapper property for LWC to use for filtering
        result.originalPlantProgramIds = new List<Id>(originalProgramIds);
        
        return result;
    }

   

    /**
     * @description Get Shop_Master__c records based on sector, product type, and shop exclusion criteria
     * @param sector Sector value (e.g., 'Assembly', 'GPS', 'Polymers', 'Press')
     * @param productType Product Type value (e.g., 'Vehicle', 'Battery', 'Engine', 'Drive Unit', 'Transmission', 'Polymers')
     * @param excludeShops List of shop values to exclude (e.g., ['All', 'Body', 'Paint'])
     * @return List of Shop_Master__c records matching the criteria
     */
    @AuraEnabled(cacheable=false)
    public static List<Shop_Master__c> getShopMastersByCriteria(String sector, String productType, List<String> excludeShops) {
        List<Shop_Master__c> shopMasters = new List<Shop_Master__c>();
        
        if (String.isBlank(sector) || String.isBlank(productType)) {
            return shopMasters;
        }
        
        if (excludeShops != null && !excludeShops.isEmpty()) {
            shopMasters = [
                SELECT Id, Name, Auth_Sector__c, Product_Type__c, Shop__c, Program_Product__c, Default_Program__c
                FROM Shop_Master__c
                WHERE Auth_Sector__c = :sector
                AND Product_Type__c = :productType
                AND Shop__c NOT IN :excludeShops
                ORDER BY Shop__c
            ];
        } else {
            shopMasters = [
                SELECT Id, Name, Auth_Sector__c, Product_Type__c, Shop__c, Program_Product__c, Default_Program__c
                FROM Shop_Master__c
                WHERE Auth_Sector__c = :sector
                AND Product_Type__c = :productType
                ORDER BY Shop__c
            ];
        }
        
        
        return shopMasters;
    }
    
    /**
     * Optimized method to update a single Plant Program's Shifts_Def__c
     * Used when Op Plan Default is changed and "Manage Shifts" is clicked
     * Queries Plant_Program__c by matching fields: Auth_Sector1__c, Product_Type__c, Program_Code__c, Shop__c, Program_Product_Index__c
     */
    @AuraEnabled(cacheable=false)
    public static SaveResult updateSinglePlantProgram(
        String plantId,
        String authSector,
        String productType,
        String programCode,
        String shop,
        String programIndex,
        String operationPlanId
    ) {
        SaveResult result = new SaveResult();
        result.success = false;
        
        try {
            if (String.isBlank(plantId) || String.isBlank(authSector) || String.isBlank(productType) || 
                String.isBlank(programIndex)) {
                result.message = 'Plant ID, Auth Sector, Product Type, and Program Index are required';
                return result;
            }
            
            // Query Plant_Program__c by matching fields
            // Match by: Plant, Auth_Sector1__c, Product_Type__c, Program_Code__c, Shop__c (from Plant_Shop__r), Program_Product_Index__c
            List<Plant_Program__c> programsToUpdate;
            
            Id plantIdValue = Id.valueOf(plantId);
            
            if (String.isNotBlank(programCode) && String.isNotBlank(shop)) {
                // Both Program Code and Shop are provided
                programsToUpdate = [
                    SELECT Id, Shifts_Def__c, Plant_Shop__r.Shop__c, Plant_Shop__r.Auth_Plant_Name__c, 
                           Auth_Sector1__c, Product_Type__c, Program_Code__c, Program_Product_Index__c
                    FROM Plant_Program__c
                    WHERE Plant_Shop__r.Auth_Plant_Name__c = :plantIdValue
                    AND Auth_Sector1__c = :authSector
                    AND Product_Type__c = :productType
                    AND Program_Code__c = :programCode
                    AND Plant_Shop__r.Shop__c = :shop
                    AND Program_Product_Index__c = :programIndex
                    LIMIT 1
                ];
            } else if (String.isNotBlank(programCode)) {
                // Only Program Code is provided (Shop is null/empty)
                programsToUpdate = [
                    SELECT Id, Shifts_Def__c, Plant_Shop__r.Shop__c, Plant_Shop__r.Auth_Plant_Name__c, 
                           Auth_Sector1__c, Product_Type__c, Program_Code__c, Program_Product_Index__c
                    FROM Plant_Program__c
                    WHERE Plant_Shop__r.Auth_Plant_Name__c = :plantIdValue
                    AND Auth_Sector1__c = :authSector
                    AND Product_Type__c = :productType
                    AND Program_Code__c = :programCode
                    AND Program_Product_Index__c = :programIndex
                    LIMIT 1
                ];
            } else if (String.isNotBlank(shop)) {
                // Only Shop is provided (Program Code is null/empty)
                programsToUpdate = [
                    SELECT Id, Shifts_Def__c, Plant_Shop__r.Shop__c, Plant_Shop__r.Auth_Plant_Name__c, 
                           Auth_Sector1__c, Product_Type__c, Program_Code__c, Program_Product_Index__c
                    FROM Plant_Program__c
                    WHERE Plant_Shop__r.Auth_Plant_Name__c = :plantIdValue
                    AND Auth_Sector1__c = :authSector
                    AND Product_Type__c = :productType
                    AND (Program_Code__c = null OR Program_Code__c = '')
                    AND Plant_Shop__r.Shop__c = :shop
                    AND Program_Product_Index__c = :programIndex
                    LIMIT 1
                ];
            } else {
                // Neither Program Code nor Shop is provided
                programsToUpdate = [
                    SELECT Id, Shifts_Def__c, Plant_Shop__r.Shop__c, Plant_Shop__r.Auth_Plant_Name__c, 
                           Auth_Sector1__c, Product_Type__c, Program_Code__c, Program_Product_Index__c
                    FROM Plant_Program__c
                    WHERE Plant_Shop__r.Auth_Plant_Name__c = :plantIdValue
                    AND Auth_Sector1__c = :authSector
                    AND Product_Type__c = :productType
                    AND (Program_Code__c = null OR Program_Code__c = '')
                    AND Program_Product_Index__c = :programIndex
                    LIMIT 1
                ];
            }
            
            if (programsToUpdate.isEmpty()) {
                result.message = 'No matching Plant Program found with the specified criteria';
                System.debug('No Plant Program found matching: Plant=' + plantId + ', Sector=' + authSector + 
                           ', ProductType=' + productType + ', ProgramCode=' + programCode + 
                           ', Shop=' + shop + ', ProgramIndex=' + programIndex);
                return result;
            }
            
            if (programsToUpdate.size() > 1) {
                result.message = 'Multiple Plant Programs found matching the criteria. Expected exactly 1.';
                System.debug('WARNING: Found ' + programsToUpdate.size() + ' matching Plant Programs');
                return result;
            }
            
            // Update Shifts_Def__c
            Id opPlanId = String.isNotBlank(operationPlanId) ? Id.valueOf(operationPlanId) : null;
            programsToUpdate[0].Shifts_Def__c = opPlanId;
            
            update programsToUpdate;
            
            result.success = true;
            result.message = 'Plant Program updated successfully';
            result.programIds = new List<Id>{ programsToUpdate[0].Id };
            
            System.debug('=== updateSinglePlantProgram completed ===');
            System.debug('Updated Plant Program: ' + programsToUpdate[0].Id);
            System.debug('Matching criteria: Plant=' + plantId + ', Sector=' + authSector + 
                        ', ProductType=' + productType + ', ProgramCode=' + programCode + 
                        ', Shop=' + shop + ', ProgramIndex=' + programIndex);
            System.debug('New Shifts_Def__c: ' + opPlanId);
            
        } catch (Exception e) {
            result.message = 'Error updating Plant Program: ' + e.getMessage();
            System.debug('ERROR in updateSinglePlantProgram: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
        }
        
        return result;
    }
    
    /**
     * Update a single Plant Program's Shifts_Def__c (Op Plan) by Id.
     * Used for child program Op Plan changes in managePlantShopsV2.
     * @param plantProgramId Plant_Program__c Id to update
     * @param operationPlanId Operation_Plan__c Id (or empty string for null)
     */
    @AuraEnabled(cacheable=false)
    public static SaveResult updatePlantProgramOpPlan(Id plantProgramId, String operationPlanId) {
        SaveResult result = new SaveResult();
        result.success = false;
        try {
            if (plantProgramId == null) {
                result.message = 'Plant Program ID is required';
                return result;
            }
            Plant_Program__c pp = [SELECT Id, Shifts_Def__c FROM Plant_Program__c WHERE Id = :plantProgramId LIMIT 1];
            Id opPlanId = String.isNotBlank(operationPlanId) ? Id.valueOf(operationPlanId) : null;
            pp.Shifts_Def__c = opPlanId;
            update pp;
            result.success = true;
            result.message = 'Op Plan updated successfully';
        } catch (Exception e) {
            result.message = 'Error updating Op Plan: ' + e.getMessage();
        }
        return result;
    }
    
    /**
     * Propagate Operation Plan (Shifts_Def__c) to all matching Plant Programs.
     * Pass excludeShops=[] (empty) to update ALL matching programs including Shop = "All" and "All Except Body, Paint".
     */
    @AuraEnabled(cacheable=false)
    public static SaveResult propagateOperationPlanToMatchingPrograms(
        String plantId, 
        String sector, 
        String productType, 
        List<String> excludeShops, 
        String operationPlanId,
        String programIndex
    ) {
        SaveResult result = new SaveResult();
        result.success = false;
        
        try {
            if (String.isBlank(plantId) || String.isBlank(sector) || String.isBlank(productType)) {
                result.message = 'Plant ID, Sector, and Product Type are required';
                return result;
            }
            
            
            // Build query to find matching Plant_Program__c records
            // Join through Plant_Shop__c to get shop and plant information
            String query = 'SELECT Id, Shifts_Def__c, Plant_Shop__r.Shop__c, Plant_Shop__r.Auth_Plant_Name__c, ' +
                          'Plant_Shop__r.Auth_Sector__c, Plant_Shop__r.Product_Type__c, Program_Product_Index__c ' +
                          'FROM Plant_Program__c ' +
                          'WHERE Plant_Shop__r.Auth_Plant_Name__c = :plantId ' +
                          'AND Plant_Shop__r.Auth_Sector__c = :sector ' +
                          'AND Plant_Shop__r.Product_Type__c = :productType';
            
            // Add program index filter if provided
            if (String.isNotBlank(programIndex)) {
                query += ' AND Program_Product_Index__c = :programIndex';
            }
            
            // Add shop exclusion if provided
            if (excludeShops != null && !excludeShops.isEmpty()) {
                query += ' AND Plant_Shop__r.Shop__c NOT IN :excludeShops';
            }
            
            List<Plant_Program__c> programsToUpdate = Database.query(query);
            
            if (programsToUpdate.isEmpty()) {
                result.success = true;
                result.message = 'No matching Plant Programs found to update';
                return result;
            }
            
            // Update Shifts_Def__c on all matching records
            // Convert empty string to null for lookup field
            Id opPlanId = String.isNotBlank(operationPlanId) ? Id.valueOf(operationPlanId) : null;
            
            for (Plant_Program__c pp : programsToUpdate) {
                pp.Shifts_Def__c = opPlanId;
            }
            
            update programsToUpdate;
            
            result.success = true;
            result.message = 'Successfully updated Shifts_Def__c on ' + programsToUpdate.size() + ' Plant Program(s)';
            
        } catch (Exception e) {
            result.success = false;
            result.message = 'Error propagating Operation Plan: ' + e.getMessage();
            System.debug('Exception in propagateOperationPlanToMatchingPrograms: ' + e.getMessage());
            throw new AuraHandledException(result.message);
        }
        
        return result;
    }

    /**
     * When checkbox is unchecked on a master row (All or All Except Body, Paint),
     * set Include__c = false for all Plant_Program__c records that match sector and product type,
     * except Assembly-Vehicle-Body and Assembly-Vehicle-Paint.
     */
    @AuraEnabled(cacheable=false)
    public static SaveResult setIncludeFalseForMatchingPrograms(
        String plantId,
        String sector,
        String productType,
        String programIndex
    ) {
        SaveResult result = new SaveResult();
        result.success = false;

        try {
            if (String.isBlank(plantId) || String.isBlank(sector) || String.isBlank(productType)) {
                result.message = 'Plant ID, Sector, and Product Type are required';
                return result;
            }

            String query = 'SELECT Id, Include__c FROM Plant_Program__c ' +
                           'WHERE Plant_Shop__r.Auth_Plant_Name__c = :plantId ' +
                           'AND Plant_Shop__r.Auth_Sector__c = :sector ' +
                           'AND Plant_Shop__r.Product_Type__c = :productType ' +
                           'AND Include__c = true';

            if (String.isNotBlank(programIndex)) {
                query += ' AND Program_Product_Index__c = :programIndex';
            }

            // Exclude Assembly-Vehicle-Body and Assembly-Vehicle-Paint (use OR per De Morgan: NOT(A AND B AND C) = (NOT A OR NOT B OR NOT C))
            query += ' AND (Plant_Shop__r.Auth_Sector__c != \'Assembly\' OR Plant_Shop__r.Product_Type__c != \'Vehicle\' OR Plant_Shop__r.Shop__c NOT IN (\'Body\', \'Paint\'))';

            List<Plant_Program__c> programsToUpdate = Database.query(query);

            if (programsToUpdate.isEmpty()) {
                result.success = true;
                result.message = 'No matching Plant Programs found to update';
                return result;
            }

            for (Plant_Program__c pp : programsToUpdate) {
                pp.Include__c = false;
            }

            update programsToUpdate;

            result.success = true;
            result.message = 'Successfully set Include__c = false on ' + programsToUpdate.size() + ' Plant Program(s)';

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error setting Include__c: ' + e.getMessage();
            System.debug('Exception in setIncludeFalseForMatchingPrograms: ' + e.getMessage());
            throw new AuraHandledException(result.message);
        }

        return result;
    }

    /**
     * When checkbox is checked again on a master row (All or All Except Body, Paint),
     * set Include__c = true for all Plant_Program__c records that match sector, product type, and program index,
     * except Assembly-Vehicle-Body and Assembly-Vehicle-Paint (same exclusion as setIncludeFalseForMatchingPrograms).
     */
    @AuraEnabled(cacheable=false)
    public static SaveResult setIncludeTrueForMatchingPrograms(
        String plantId,
        String sector,
        String productType,
        String programIndex
    ) {
        SaveResult result = new SaveResult();
        result.success = false;

        try {
            if (String.isBlank(plantId) || String.isBlank(sector) || String.isBlank(productType)) {
                result.message = 'Plant ID, Sector, and Product Type are required';
                return result;
            }

            String query = 'SELECT Id, Include__c FROM Plant_Program__c ' +
                           'WHERE Plant_Shop__r.Auth_Plant_Name__c = :plantId ' +
                           'AND Plant_Shop__r.Auth_Sector__c = :sector ' +
                           'AND Plant_Shop__r.Product_Type__c = :productType ' +
                           'AND Include__c = false';

            if (String.isNotBlank(programIndex)) {
                query += ' AND Program_Product_Index__c = :programIndex';
            }

            // Exclude Assembly-Vehicle-Body and Assembly-Vehicle-Paint (same as setIncludeFalseForMatchingPrograms)
            query += ' AND (Plant_Shop__r.Auth_Sector__c != \'Assembly\' OR Plant_Shop__r.Product_Type__c != \'Vehicle\' OR Plant_Shop__r.Shop__c NOT IN (\'Body\', \'Paint\'))';

            List<Plant_Program__c> programsToUpdate = Database.query(query);

            if (programsToUpdate.isEmpty()) {
                result.success = true;
                result.message = 'No matching Plant Programs found to update';
                return result;
            }

            for (Plant_Program__c pp : programsToUpdate) {
                pp.Include__c = true;
            }

            update programsToUpdate;

            result.success = true;
            result.message = 'Successfully set Include__c = true on ' + programsToUpdate.size() + ' Plant Program(s)';

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error setting Include__c: ' + e.getMessage();
            System.debug('Exception in setIncludeTrueForMatchingPrograms: ' + e.getMessage());
            throw new AuraHandledException(result.message);
        }

        return result;
    }

    /**
     * Directly update Plant_Program__c records by ID - sets Include__c and Auth_Plant_Name__c.
     * Use when we have specific plantProgramIds (e.g. from unchecked master row programs).
     */
    @AuraEnabled(cacheable=false)
    public static SaveResult updatePlantProgramsIncludeAndAuth(
        String plantId,
        List<String> plantProgramIds,
        Boolean includeValue
    ) {
        SaveResult result = new SaveResult();
        result.success = false;

        try {
            if (plantProgramIds == null || plantProgramIds.isEmpty()) {
                result.success = true;
                result.message = 'No Plant Programs to update';
                return result;
            }

            Set<Id> idSet = new Set<Id>();
            for (String s : plantProgramIds) {
                if (String.isNotBlank(s)) {
                    idSet.add(Id.valueOf(s));
                }
            }
            if (idSet.isEmpty()) {
                result.success = true;
                result.message = 'No valid Plant Program IDs';
                return result;
            }

            List<Plant_Program__c> programsToUpdate = [
                SELECT Id, Include__c, Auth_Plant_Name__c
                FROM Plant_Program__c
                WHERE Id IN :idSet
            ];

            if (programsToUpdate.isEmpty()) {
                result.success = true;
                result.message = 'No matching Plant Programs found';
                return result;
            }

            Id plantIdVal = String.isNotBlank(plantId) ? Id.valueOf(plantId) : null;

            for (Plant_Program__c pp : programsToUpdate) {
                pp.Include__c = includeValue != null ? includeValue : pp.Include__c;
                if (plantIdVal != null) {
                    pp.Auth_Plant_Name__c = plantIdVal;
                }
            }

            update programsToUpdate;

            result.success = true;
            result.message = 'Successfully updated ' + programsToUpdate.size() + ' Plant Program(s)';

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error updating Plant Programs: ' + e.getMessage();
            System.debug('Exception in updatePlantProgramsIncludeAndAuth: ' + e.getMessage());
            throw new AuraHandledException(result.message);
        }

        return result;
    }

    @AuraEnabled(cacheable=false)
    public static SaveResult savePlantShops(String shopDataListString) {
        
        SaveResult result = new SaveResult();
        result.shopMasterIdToPlantShopIdMap = new Map<String, Id>();
        
        try {
            System.debug('=== savePlantShops called ===');
            System.debug('shopDataListString: ' + shopDataListString);
            
            List<ShopData> shopDataList = (List<ShopData>) JSON.deserialize(shopDataListString, List<ShopData>.class);
            
            System.debug('Deserialized shopDataList size: ' + (shopDataList != null ? shopDataList.size() : 0));
            if (shopDataList != null) {
                for (Integer i = 0; i < shopDataList.size(); i++) {
                    ShopData sd = shopDataList[i];
                    System.debug('shopData[' + i + ']: plantId=' + sd.plantId + ', shopMasterId=' + sd.shopMasterId);
                }
            }
            
            if (shopDataList == null || shopDataList.isEmpty()) {
                System.debug('shopDataList is null or empty, returning null');
                return null; 
            }
            
            // Collect Plant IDs and Shop Master IDs to check for existing records
            Set<Id> plantIds = new Set<Id>();
            Set<Id> shopMasterIds = new Set<Id>();
            for (ShopData shopData : shopDataList) {
                try {
                    if (String.isNotBlank(shopData.plantId)) {
                        plantIds.add(Id.valueOf(shopData.plantId));
                    }
                    if (String.isNotBlank(shopData.shopMasterId)) {
                        shopMasterIds.add(Id.valueOf(shopData.shopMasterId));
                    }
                } catch (Exception idEx) {
                    throw new AuraHandledException('Invalid ID format: plantId=' + shopData.plantId + ', shopMasterId=' + shopData.shopMasterId + '. Error: ' + idEx.getMessage());
                }
            }
            
            // Query for existing Plant Shops to avoid duplicates
            Map<String, Plant_Shop__c> existingPlantShopsMap = new Map<String, Plant_Shop__c>();
            if (!plantIds.isEmpty() && !shopMasterIds.isEmpty()) {
                List<Plant_Shop__c> existingPlantShops = [
                    SELECT Id, Auth_Plant_Name__c, Shop_Master__c
                    FROM Plant_Shop__c
                    WHERE Auth_Plant_Name__c IN :plantIds
                    AND Shop_Master__c IN :shopMasterIds
                ];
                
                for (Plant_Shop__c ps : existingPlantShops) {
                    String key = String.valueOf(ps.Auth_Plant_Name__c) + '-' + String.valueOf(ps.Shop_Master__c);
                    existingPlantShopsMap.put(key, ps);
                }
            }
            
            List<Plant_Shop__c> plantShopsToInsert = new List<Plant_Shop__c>();
            for (ShopData shopData : shopDataList) {
                if (String.isBlank(shopData.plantId) || String.isBlank(shopData.shopMasterId)) {
                    throw new AuraHandledException('Plant Shop ID and Shop Master ID are required to save a plant shop. plantId=' + shopData.plantId + ', shopMasterId=' + shopData.shopMasterId);
                }
                
                // Check if this combination already exists
                String key = shopData.plantId + '-' + shopData.shopMasterId;
                if (existingPlantShopsMap.containsKey(key)) {
                    // Use existing record
                    Plant_Shop__c existing = existingPlantShopsMap.get(key);
                    result.shopMasterIdToPlantShopIdMap.put(shopData.shopMasterId, existing.Id);
                    continue;
                }
                
                plantShopsToInsert.add(new Plant_Shop__c(
                    Auth_Plant_Name__c = shopData.plantId,
                    Shop_Master__c = shopData.shopMasterId
                ));
            }
            
            if (!plantShopsToInsert.isEmpty()) {
                System.debug('=== About to insert ' + plantShopsToInsert.size() + ' Plant_Shop__c records ===');
                System.debug('Records to insert: ' + JSON.serializePretty(plantShopsToInsert));
                
                Database.SaveResult[] saveResults = Database.insert(plantShopsToInsert, false);
                
                // Check for errors
                for (Integer i = 0; i < saveResults.size(); i++) {
                    Database.SaveResult sr = saveResults[i];
                    if (sr.isSuccess()) {
                        Plant_Shop__c plantShop = plantShopsToInsert[i];
                        result.shopMasterIdToPlantShopIdMap.put(plantShop.Shop_Master__c, sr.getId());
                    } else {
                        String errorMsg = 'Error inserting Plant Shop record ' + i + ': ';
                        for (Database.Error err : sr.getErrors()) {
                            errorMsg += err.getMessage() + ' (Fields: ' + err.getFields() + '); ';
                        }
                        System.debug('Insert error for record ' + i + ': ' + errorMsg);
                        throw new AuraHandledException(errorMsg);
                    }
                }
                
                System.debug('=== Successfully inserted Plant_Shop__c records ===');
            }
            
            result.success = true;
            result.message = 'Plant shops saved successfully.';
            
        } catch (DmlException e) {
            result.success = false;
            String detailedError = 'DML Error saving Plant Shops: ';
            for (Integer i = 0; i < e.getNumDml(); i++) {
                detailedError += '\nRecord ' + i + ': ' + e.getDmlMessage(i);
                detailedError += '\nFields: ' + e.getDmlFieldNames(i);
                detailedError += '\nType: ' + e.getDmlType(i);
            }
            result.message = detailedError;
            System.debug('DML Exception in savePlantShops: ' + detailedError);
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException(result.message);
        } catch (AuraHandledException e) {
            // Re-throw AuraHandledException as-is to preserve the original message
            System.debug('AuraHandledException in savePlantShops: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw e;
        } catch (Exception e) {
            result.success = false;
            String errorDetails = 'Error saving plant shops: ' + e.getMessage() + ' | Type: ' + e.getTypeName();
            if (e.getCause() != null) {
                errorDetails += ' | Cause: ' + e.getCause().getMessage();
            }
            errorDetails += ' | Stack Trace: ' + e.getStackTraceString();
            result.message = errorDetails;
            System.debug('Exception in savePlantShops: ' + errorDetails);
            System.debug('Full exception: ' + e);
            throw new AuraHandledException(errorDetails);
        }
        
        return result;
    }

    @AuraEnabled(cacheable=false)
    public static SaveResult savePrograms(String programDataListString) {
        System.debug('=== savePrograms called ===');
        System.debug('programDataListString: ' + programDataListString);
        List<ProgramData> programDataList = (List<ProgramData>) JSON.deserialize(programDataListString, List<ProgramData>.class);
        SaveResult result = new SaveResult();
        
        if (programDataList == null || programDataList.isEmpty()) {
            throw new AuraHandledException('No program data provided to save.');
        }

        List<Plant_Program__c> programsToUpsert = new List<Plant_Program__c>();
        
        // Valid Plant_Program_Name picklist values (from Global Value Set)
        Set<String> validPlantProgramNames = new Set<String>{
            'C234', 'Electric', 'Gas', 'CSS', 'GenV', 'Ultium', 
            'Polymers', 'Press', 'All', 'Mid Size SUV', 'ELECTRIC SUBS'
        };
        
        // Store workbook shift values in static Map for trigger handler access
        for (ProgramData programData : programDataList) {
            // Skip if plantProgramId is null or empty (new programs being inserted)
            if (String.isNotBlank(programData.plantProgramId) && 
                (programData.workbookShiftValues != null || programData.workbookShift2ndValues != null)) {
                Map<Id, WorkbookShiftValues> workbookValuesMap = new Map<Id, WorkbookShiftValues>();
                
                // Process workbook shift values
                // Check if workbookShiftValues exists and is not empty
                if (programData.workbookShiftValues != null && !programData.workbookShiftValues.isEmpty()) {
                    for (String workbookId : programData.workbookShiftValues.keySet()) {
                        Object shift3rdObj = programData.workbookShiftValues.get(workbookId);
                        Decimal shift3rd = shift3rdObj != null ? Decimal.valueOf(String.valueOf(shift3rdObj)) : null;
                        
                        Decimal shift2nd = null;
                        if (programData.workbookShift2ndValues != null && programData.workbookShift2ndValues.containsKey(workbookId)) {
                            Object shift2ndObj = programData.workbookShift2ndValues.get(workbookId);
                            shift2nd = shift2ndObj != null ? Decimal.valueOf(String.valueOf(shift2ndObj)) : null;
                        }
                        
                        workbookValuesMap.put(Id.valueOf(workbookId), 
                                            new WorkbookShiftValues(shift2nd, shift3rd));
                    }
                }
                
                // Process workbookShift2ndValues if workbookShiftValues was empty or null
                // This handles the case when going from 1→2 (only 2nd shift values)
                if (programData.workbookShift2ndValues != null && !programData.workbookShift2ndValues.isEmpty()) {
                    for (String workbookId : programData.workbookShift2ndValues.keySet()) {
                        // Only add if not already processed from workbookShiftValues
                        if (!workbookValuesMap.containsKey(Id.valueOf(workbookId))) {
                            Object shift2ndObj = programData.workbookShift2ndValues.get(workbookId);
                            Decimal shift2nd = shift2ndObj != null ? Decimal.valueOf(String.valueOf(shift2ndObj)) : null;
                            workbookValuesMap.put(Id.valueOf(workbookId), 
                                                new WorkbookShiftValues(shift2nd, null));
                        }
                    }
                }
                
                if (!workbookValuesMap.isEmpty()) {
                    workbookShiftValuesByProgramId.put(Id.valueOf(programData.plantProgramId), workbookValuesMap);
                }
            }
        }
        
        // Query existing Plant Programs to check for duplicates before insert
        // Build sets for bulk query and Plant_Shop fallback
        Set<Id> plantShopIds = new Set<Id>();
        
        for (ProgramData programData : programDataList) {
            // Collect plantShopIds from ALL records (for Auth_Plant_Name__c fallback map)
            if (programData.plantShopId != null) {
                plantShopIds.add(Id.valueOf(programData.plantShopId));
            }
        }
        
        // Build Plant_Shop__c maps for fallback values when payload values are blank
        Map<Id, Id> plantShopToAuthPlantMap = new Map<Id, Id>();
        Map<Id, Plant_Shop__c> plantShopDetailsById = new Map<Id, Plant_Shop__c>();
        if (!plantShopIds.isEmpty()) {
            for (Plant_Shop__c ps : [
                SELECT Id, Auth_Plant_Name__c, Auth_Sector__c, Product_Type__c, Shop__c
                FROM Plant_Shop__c
                WHERE Id IN :plantShopIds
            ]) {
                if (ps.Auth_Plant_Name__c != null) {
                    plantShopToAuthPlantMap.put(ps.Id, ps.Auth_Plant_Name__c);
                }
                plantShopDetailsById.put(ps.Id, ps);
            }
        }

        // Duplicate definition:
        // active Plant Program exists with same plant, sector, product type, plant shop, program code, and program name.
        // Use Plant_Shop__c as the scope anchor so we always evaluate all active programs for targeted shops.
        Map<String, Set<Id>> existingActiveDuplicateKeyToIds = new Map<String, Set<Id>>();
        Map<String, Set<Id>> existingActiveShopCodeNameKeyToIds = new Map<String, Set<Id>>();
        if (!plantShopIds.isEmpty()) {
            List<Plant_Program__c> existingPrograms = [
                SELECT Id, Plant_Shop__c, Auth_Plant_Name__c, Auth_Sector1__c, Product_Type__c, Shop__c, Program_Code__c, Plant_Program_Name__c
                FROM Plant_Program__c
                WHERE Include__c = true
                AND Plant_Shop__c IN :plantShopIds
            ];

            for (Plant_Program__c pp : existingPrograms) {
                String existingKey = String.valueOf(pp.Plant_Shop__c) + '|' +
                    String.valueOf(pp.Auth_Plant_Name__c) + '|' +
                    (String.isNotBlank(pp.Auth_Sector1__c) ? pp.Auth_Sector1__c.trim().toLowerCase() : '') + '|' +
                    (String.isNotBlank(pp.Product_Type__c) ? pp.Product_Type__c.trim().toLowerCase() : '') + '|' +
                    (String.isNotBlank(pp.Shop__c) ? pp.Shop__c.trim().toLowerCase() : '') + '|' +
                    (String.isNotBlank(pp.Program_Code__c) ? pp.Program_Code__c.trim().toLowerCase() : '') + '|' +
                    (String.isNotBlank(pp.Plant_Program_Name__c) ? pp.Plant_Program_Name__c.trim().toLowerCase() : '');
                if (!existingActiveDuplicateKeyToIds.containsKey(existingKey)) {
                    existingActiveDuplicateKeyToIds.put(existingKey, new Set<Id>());
                }
                existingActiveDuplicateKeyToIds.get(existingKey).add(pp.Id);

                String existingShopCodeNameKey = String.valueOf(pp.Plant_Shop__c) + '|' +
                    (String.isNotBlank(pp.Program_Code__c) ? pp.Program_Code__c.trim().toLowerCase() : '') + '|' +
                    (String.isNotBlank(pp.Plant_Program_Name__c) ? pp.Plant_Program_Name__c.trim().toLowerCase() : '');
                if (!existingActiveShopCodeNameKeyToIds.containsKey(existingShopCodeNameKey)) {
                    existingActiveShopCodeNameKeyToIds.put(existingShopCodeNameKey, new Set<Id>());
                }
                existingActiveShopCodeNameKeyToIds.get(existingShopCodeNameKey).add(pp.Id);
            }
        }
        
        // Prepare Plant_Shop__c records
        Set<String> seenPendingInsertKeys = new Set<String>();
        for (ProgramData programData : programDataList) {
            Plant_Program__c plantProgram = new Plant_Program__c();
            
            // Check if this is an update (existing record) or insert (new record)
            if (programData.plantProgramId != null && String.isNotBlank(programData.plantProgramId)) {
                // UPDATE existing Plant_Program - check if update would create an active duplicate
                String updateProgramCode = String.isNotBlank(programData.programCode) ? programData.programCode.trim() : '';
                String updateProgramName = String.isNotBlank(programData.programName)
                    ? programData.programName.trim()
                    : updateProgramCode;
                Id updatePlantShopIdVal = String.isNotBlank(programData.plantShopId) ? Id.valueOf(programData.plantShopId) : null;
                Plant_Shop__c updateSourcePlantShop = updatePlantShopIdVal != null ? plantShopDetailsById.get(updatePlantShopIdVal) : null;
                Id updateDuplicatePlantId = String.isNotBlank(programData.plantId)
                    ? Id.valueOf(programData.plantId)
                    : (updateSourcePlantShop != null ? updateSourcePlantShop.Auth_Plant_Name__c : null);
                String updateDuplicateSector = updateSourcePlantShop != null && String.isNotBlank(updateSourcePlantShop.Auth_Sector__c) ? updateSourcePlantShop.Auth_Sector__c.trim().toLowerCase() : '';
                String updateDuplicateProductType = updateSourcePlantShop != null && String.isNotBlank(updateSourcePlantShop.Product_Type__c) ? updateSourcePlantShop.Product_Type__c.trim().toLowerCase() : '';
                String updateDuplicateShop = updateSourcePlantShop != null && String.isNotBlank(updateSourcePlantShop.Shop__c) ? updateSourcePlantShop.Shop__c.trim().toLowerCase() : '';
                String updateDuplicateKey = String.valueOf(updatePlantShopIdVal) + '|' +
                    String.valueOf(updateDuplicatePlantId) + '|' +
                    updateDuplicateSector + '|' +
                    updateDuplicateProductType + '|' +
                    updateDuplicateShop + '|' +
                    updateProgramCode.toLowerCase() + '|' +
                    updateProgramName.toLowerCase();
                String updateShopCodeNameKey = String.valueOf(updatePlantShopIdVal) + '|' +
                    updateProgramCode.toLowerCase() + '|' +
                    updateProgramName.toLowerCase();
                Id updatingProgramId = Id.valueOf(programData.plantProgramId);
                Boolean updateWouldBeActive = programData.isSelected == null ? true : programData.isSelected;
                if (updateWouldBeActive) {
                    Set<Id> exactMatchIds = existingActiveDuplicateKeyToIds.containsKey(updateDuplicateKey)
                        ? new Set<Id>(existingActiveDuplicateKeyToIds.get(updateDuplicateKey))
                        : new Set<Id>();
                    Set<Id> shopCodeNameMatchIds = existingActiveShopCodeNameKeyToIds.containsKey(updateShopCodeNameKey)
                        ? new Set<Id>(existingActiveShopCodeNameKeyToIds.get(updateShopCodeNameKey))
                        : new Set<Id>();
                    exactMatchIds.remove(updatingProgramId);
                    shopCodeNameMatchIds.remove(updatingProgramId);
                    if (!exactMatchIds.isEmpty() || !shopCodeNameMatchIds.isEmpty()) {
                        String displayName = String.isNotBlank(updateProgramName) ? updateProgramName : updateProgramCode;
                        if (String.isBlank(displayName)) {
                            displayName = 'Plant Program';
                        }
                        throw new AuraHandledException(displayName + ' already exists. Please save the plant program with a different name.');
                    }
                }

                // UPDATE existing Plant_Program
                plantProgram.Id = programData.plantProgramId;
                // For updates, we must set all fields that might have changed
                // Convert empty string to null for lookup field
                plantProgram.Shifts_Def__c = String.isNotBlank(programData.operationPlanId) ? programData.operationPlanId : null;
                plantProgram.Include__c = programData.isSelected;
                
                // Set Auth_Plant_Name__c when plantId provided (fixes records created without it)
                if (String.isNotBlank(programData.plantId)) {
                    plantProgram.Auth_Plant_Name__c = Id.valueOf(programData.plantId);
                } else if (programData.plantShopId != null) {
                    Id plantShopIdVal = Id.valueOf(programData.plantShopId);
                    if (plantShopToAuthPlantMap != null && plantShopToAuthPlantMap.containsKey(plantShopIdVal)) {
                        plantProgram.Auth_Plant_Name__c = plantShopToAuthPlantMap.get(plantShopIdVal);
                    }
                }
                
                // Set Program Code if provided (Text field)
                if (String.isNotBlank(programData.programCode)) {
                    plantProgram.Program_Code__c = programData.programCode;
                }
                
                // Set Program Name - Plant_Program_Name__c is a Text field; save user-entered value
                if (String.isNotBlank(programData.programName)) {
                    plantProgram.Plant_Program_Name__c = programData.programName;
                } else if (String.isBlank(programData.programName) && String.isNotBlank(programData.programCode) && validPlantProgramNames.contains(programData.programCode)) {
                    // Fallback: use programCode when programName is empty
                    plantProgram.Plant_Program_Name__c = programData.programCode;
                }
            } else {
                // INSERT new Plant_Program - check for active duplicate
                String programCode = String.isNotBlank(programData.programCode) ? programData.programCode.trim() : '';
                String programName = String.isNotBlank(programData.programName)
                    ? programData.programName.trim()
                    : programCode;
                Id plantShopIdVal = String.isNotBlank(programData.plantShopId) ? Id.valueOf(programData.plantShopId) : null;
                Plant_Shop__c sourcePlantShop = plantShopIdVal != null ? plantShopDetailsById.get(plantShopIdVal) : null;
                Id duplicatePlantId = String.isNotBlank(programData.plantId)
                    ? Id.valueOf(programData.plantId)
                    : (sourcePlantShop != null ? sourcePlantShop.Auth_Plant_Name__c : null);
                String duplicateSector = sourcePlantShop != null && String.isNotBlank(sourcePlantShop.Auth_Sector__c) ? sourcePlantShop.Auth_Sector__c.trim().toLowerCase() : '';
                String duplicateProductType = sourcePlantShop != null && String.isNotBlank(sourcePlantShop.Product_Type__c) ? sourcePlantShop.Product_Type__c.trim().toLowerCase() : '';
                String duplicateShop = sourcePlantShop != null && String.isNotBlank(sourcePlantShop.Shop__c) ? sourcePlantShop.Shop__c.trim().toLowerCase() : '';
                String duplicateKey = String.valueOf(plantShopIdVal) + '|' +
                    String.valueOf(duplicatePlantId) + '|' +
                    duplicateSector + '|' +
                    duplicateProductType + '|' +
                    duplicateShop + '|' +
                    programCode.toLowerCase() + '|' +
                    programName.toLowerCase();
                String duplicateShopCodeNameKey = String.valueOf(plantShopIdVal) + '|' +
                    programCode.toLowerCase() + '|' +
                    programName.toLowerCase();

                if (existingActiveDuplicateKeyToIds.containsKey(duplicateKey) ||
                    existingActiveShopCodeNameKeyToIds.containsKey(duplicateShopCodeNameKey) ||
                    seenPendingInsertKeys.contains(duplicateKey)) {
                    String displayName = String.isNotBlank(programName) ? programName : programCode;
                    if (String.isBlank(displayName)) {
                        displayName = 'Plant Program';
                    }
                    throw new AuraHandledException(displayName + ' already exists. Please save the plant program with a different name.');
                }
                seenPendingInsertKeys.add(duplicateKey);
                
                System.debug('>>> INSERTING NEW Plant_Program__c: shopId=' + programData.plantShopId + 
                            ', index=' + programData.programValue + 
                            ', code=' + programCode + 
                            ', Include__c=' + programData.isSelected);
                
                plantProgram.Plant_Shop__c = programData.plantShopId;
                // Auth_Plant_Name__c: use plantId from request, or fallback to Plant_Shop__c.Auth_Plant_Name__c
                if (String.isNotBlank(programData.plantId)) {
                    plantProgram.Auth_Plant_Name__c = Id.valueOf(programData.plantId);
                } else if (plantShopIdVal != null) {
                    if (plantShopToAuthPlantMap != null && plantShopToAuthPlantMap.containsKey(plantShopIdVal)) {
                        plantProgram.Auth_Plant_Name__c = plantShopToAuthPlantMap.get(plantShopIdVal);
                    }
                }
                plantProgram.Program_Product_Index__c = programData.programValue;
                // Convert empty string to null for lookup field
                plantProgram.Shifts_Def__c = String.isNotBlank(programData.operationPlanId) ? programData.operationPlanId : null;
                plantProgram.Include__c = programData.isSelected;
                
                // Set Program Code if provided (Text field)
                if (String.isNotBlank(programData.programCode)) {
                    plantProgram.Program_Code__c = programData.programCode;
                }
                
                // Set Program Name - Plant_Program_Name__c is a Text field; save user-entered value
                if (String.isNotBlank(programData.programName)) {
                    plantProgram.Plant_Program_Name__c = programData.programName;
                } else if (String.isBlank(programData.programName) && String.isNotBlank(programData.programCode) && validPlantProgramNames.contains(programData.programCode)) {
                    // Fallback: use programCode when programName is empty
                    plantProgram.Plant_Program_Name__c = programData.programCode;
                }
            }
            
            
            programsToUpsert.add(plantProgram);
        }
        
        
        List<Id> insertedPlantProgramIds = new List<Id>();
        List<Id> updatedPlantProgramIds = new List<Id>();
        
        if (!programsToUpsert.isEmpty()) {
            try {
                System.debug('=== About to upsert ' + programsToUpsert.size() + ' Plant_Program__c records ===');
                System.debug('Records to upsert: ' + JSON.serializePretty(programsToUpsert));
                
                //Database.upsert programsToUpsert Id;
                List<Database.UpsertResult> results = Database.upsert(programsToUpsert, Schema.getGlobalDescribe().get('Plant_Program__c').getDescribe().fields.getMap().get('Id'), false);
                System.debug('=== Upsert completed ===');
                
                for (Database.UpsertResult upsertResult : results) {
                    if (upsertResult.isSuccess()) {
                        if (upsertResult.isCreated()) {
                            insertedPlantProgramIds.add(upsertResult.getId());
                        } else {
                            updatedPlantProgramIds.add(upsertResult.getId());
                        }
                    }
                }
                
                // Query back the updated records to verify
                if (!updatedPlantProgramIds.isEmpty()) {
                    List<Plant_Program__c> updatedRecords = [
                        SELECT Id, Shifts_Def__c, Include__c
                        FROM Plant_Program__c
                        WHERE Id IN :updatedPlantProgramIds
                    ];
                }
                
                
            } catch (DmlException e) {
                result.success = false;
                String detailedError = 'DML Error saving Plant Programs: ';
                for (Integer i = 0; i < e.getNumDml(); i++) {
                    detailedError += '\nRecord ' + i + ': ' + e.getDmlMessage(i);
                    detailedError += '\nFields: ' + e.getDmlFieldNames(i);
                    detailedError += '\nType: ' + e.getDmlType(i);
                }
                result.message = detailedError;
                System.debug('DML Exception in savePrograms: ' + detailedError);
                System.debug('Stack trace: ' + e.getStackTraceString());
                throw new AuraHandledException(result.message);
            } catch (Exception e) {
                result.success = false;
                result.message = 'Error saving data: ' + e.getMessage() + ' | Type: ' + e.getTypeName();
                System.debug('Exception in savePrograms: ' + e.getMessage() + '\n' + e.getStackTraceString());
                throw new AuraHandledException(result.message);
            }
        }
        // Include both inserted and updated program IDs in result
        List<Id> allProgramIds = new List<Id>();
        allProgramIds.addAll(insertedPlantProgramIds);
        allProgramIds.addAll(updatedPlantProgramIds);
        result.programIds = allProgramIds;
        result.success = true;
        result.message = 'Programs saved successfully.';
        
        // NOTE: Workbook association is now handled in createPlantFunctions method
        // after Plant Functions are created, so we don't call it here anymore
        // (associateAuthDBRecords requires Plant Functions to exist for proper matching)
        System.debug('Plant Programs saved. Workbook association will happen when Plant Functions are created.');
        
        return result;
    }

    @AuraEnabled(cacheable=false)
    public static SaveResult createPlantFunctions(List<Id> plantProgramIds) {
        SaveResult result = new SaveResult();
        if (plantProgramIds == null || plantProgramIds.isEmpty()) {
            result.success = false;
            result.message = 'No plant programs provided to create functions for.';
            return result;
        }

        // Get all plant programs
        List<Plant_Program__c> programs = QuerySelector.getPlantProgramsByIds(plantProgramIds);

        // Get all functions
        List<Function__c> functions = QuerySelector.getAllFunctions();

        // Plant Functions to Insert
        List<Plant_Function__c> plantFunctionsToInsert = new List<Plant_Function__c>();
        List<Plant_Program__c> newPlantPrograms = new List<Plant_Program__c>();
        
        for(Plant_Program__c program : programs) {
            plantProgramsMapping.put(program.Plant_Shop__c+'-'+program.Program_Product_Index__c, program);
        }

        for(Plant_Program__c program : programs) {
            for(Function__c function : functions) {
                //CHECK IF NEEDS NEW PLANT PROGRAM
                if(checkNeedsNewPlantProgram(function, program)){
                    Plant_Program__c newProgram = generateNewPlantProgram(program);
                    if (newProgram != null) {
                        newPlantPrograms.add(newProgram);
                    }
                }
            }
        }

        plantFunctionsToInsert.addAll(PlantFunctionMatchingHelper.buildPlantFunctions(functions, programs));

        if (!newPlantPrograms.isEmpty()) {
            insert newPlantPrograms;
        }

        if (!newPlantPrograms.isEmpty()) {
            plantFunctionsToInsert.addAll(PlantFunctionMatchingHelper.buildPlantFunctions(functions, newPlantPrograms));
        }

        if (!plantFunctionsToInsert.isEmpty()) {
            Set<Id> targetProgramIds = new Set<Id>();
            Set<Id> functionIds = new Set<Id>();
            for (Plant_Function__c pf : plantFunctionsToInsert) {
                if (pf.Plant_Program__c != null) {
                    targetProgramIds.add(pf.Plant_Program__c);
                }
                if (pf.Function__c != null) {
                    functionIds.add(pf.Function__c);
                }
            }
            
            Set<String> existingCompositeKeys = new Set<String>();
            if (!targetProgramIds.isEmpty() && !functionIds.isEmpty()) {
                for (Plant_Function__c existing : [
                    SELECT Id, Plant_Program__c, Function__c
                    FROM Plant_Function__c
                    WHERE Plant_Program__c IN :targetProgramIds
                    AND Function__c IN :functionIds
                ]) {
                    existingCompositeKeys.add(getPlantFunctionCompositeKey(existing.Plant_Program__c, existing.Function__c));
                }
            }
            
            List<Plant_Function__c> newPlantFunctionsToInsert = new List<Plant_Function__c>();
            for (Plant_Function__c pf : plantFunctionsToInsert) {
                String compositeKey = getPlantFunctionCompositeKey(pf.Plant_Program__c, pf.Function__c);
                if (!existingCompositeKeys.contains(compositeKey)) {
                    newPlantFunctionsToInsert.add(pf);
                    existingCompositeKeys.add(compositeKey);
                }
            }
            
            if (!newPlantFunctionsToInsert.isEmpty()) {
                // SANITIZATION: Ensure Function__c is only assigned when the referenced Function__c
                // record has Included_in_Auth_Plan_of_Record__c = true. Bulkified check.
                Set<Id> referencedFunctionIds = new Set<Id>();
                for (Plant_Function__c pfCand : newPlantFunctionsToInsert) {
                    if (pfCand.Function__c != null) {
                        referencedFunctionIds.add(pfCand.Function__c);
                    }
                }
                Map<Id, Function__c> functionsMap = new Map<Id, Function__c>();
                if (!referencedFunctionIds.isEmpty()) {
                    for (Function__c f : [
                        SELECT Id, Included_in_Auth_Plan_of_Record__c
                        FROM Function__c
                        WHERE Id IN :referencedFunctionIds
                    ]) {
                        functionsMap.put(f.Id, f);
                    }
                }
                List<Plant_Function__c> validPlantFunctionsToInsert = new List<Plant_Function__c>();
                
                for (Plant_Function__c pfCand : newPlantFunctionsToInsert) {
                    if (pfCand.Function__c == null) continue;
                    
                    Function__c related = functionsMap.get(pfCand.Function__c);
                    
                    if (related != null && related.Included_in_Auth_Plan_of_Record__c == true) {
                        validPlantFunctionsToInsert.add(pfCand);
                    }
                }
                
                if (!validPlantFunctionsToInsert.isEmpty()) {
                    insert validPlantFunctionsToInsert;
                }
                
                // Link Workbook records to Plant Programs only when new Plant Functions are created
                // Collect all Plant Program IDs (including newly created ones)
                Set<Id> allPlantProgramIds = new Set<Id>();
                allPlantProgramIds.addAll(plantProgramIds);
                if (!newPlantPrograms.isEmpty()) {
                    for (Plant_Program__c newPP : newPlantPrograms) {
                        allPlantProgramIds.add(newPP.Id);
                    }
                }
                
                // Set result to only include newly inserted Plant Functions
                result.plantFunctions = validPlantFunctionsToInsert;
            } else {
                result.plantFunctions = new List<Plant_Function__c>();
            }
        } else {
            result.plantFunctions = new List<Plant_Function__c>();
        }
        result.success = true;
        result.message = 'Plant functions upserted successfully.';
        return result;
    }
    
    /**
     * Previously auto-created Program B when processing Program A with Equation functions.
     * Disabled: Program B must only be created when the user explicitly checks it in the LWC.
     * Auto-creation caused Program B records to appear for all sectors/shops when unchecked.
     */
    private static Boolean checkNeedsNewPlantProgram(Function__c function, Plant_Program__c program){
        return false; // Do not auto-create Program B - user must explicitly select it in managePlantShopsV2
    }

    private static Boolean checkIsEquation(Function__c function){
        return PlantFunctionMatchingHelper.isEquationFunction(function);
    }


    private static Plant_Program__c generateNewPlantProgram(Plant_Program__c program){
        if (program.Program_Product_Index__c != 'A') {
            return null;
        }
        Plant_Program__c newProgramRecord = program.clone(false, true, false, false);
        newProgramRecord.Program_Product_Index__c = 'B';
        // Ensure Auth_Plant_Name__c is set when source has it null (e.g. cloned from program without it)
        if (newProgramRecord.Auth_Plant_Name__c == null && program.Plant_Shop__r != null && program.Plant_Shop__r.Auth_Plant_Name__c != null) {
            newProgramRecord.Auth_Plant_Name__c = program.Plant_Shop__r.Auth_Plant_Name__c;
        }
        plantProgramsMapping.put(program.Plant_Shop__c+'-B', newProgramRecord);
        return newProgramRecord;
    }

    @AuraEnabled(cacheable=false)
    public static SaveResult reparentEquationFunctionsForDeactivatedPrograms(String requestsJson) {
        SaveResult result = new SaveResult();
        result.success = true;
        result.message = 'No reparent requests supplied.';
        result.programIds = new List<Id>();
        result.createdProgramCount = 0;
        result.reparentedCount = 0;

        if (String.isBlank(requestsJson)) {
            return result;
        }

        List<EquationReparentRequest> requests = (List<EquationReparentRequest>) JSON.deserialize(
            requestsJson,
            List<EquationReparentRequest>.class
        );
        if (requests == null || requests.isEmpty()) {
            return result;
        }

        result.message = 'Plant program was deactivated and functions were reparented successfully.';

        for (EquationReparentRequest request : requests) {
            validateEquationReparentRequest(request);

            Id plantId = Id.valueOf(request.plantId);
            Id sourcePlantProgramId = Id.valueOf(request.sourcePlantProgramId);
            Id shopMasterId = Id.valueOf(request.shopMasterId);
            Id operationPlanId = String.isNotBlank(request.operationPlanId) ? Id.valueOf(request.operationPlanId) : null;

            Id targetPlantShopId = getOrCreatePlantShopForReparent(
                plantId,
                shopMasterId,
                request.sector,
                request.productType
            );
            ReplacementProgramResult replacementProgramResult = getOrCreateReplacementProgram(
                sourcePlantProgramId,
                plantId,
                targetPlantShopId,
                request.programIndex,
                request.programCode,
                request.programName,
                operationPlanId
            );
            Plant_Program__c targetProgram = replacementProgramResult.program;

            result.programIds.add(targetProgram.Id);
            if (replacementProgramResult.wasCreated) {
                result.createdProgramCount++;
            }

            ensurePlantProgramCodeExistsForReparent(request.sector, request.productType, request.programCode);
            // Deactivated source program must be marked as excluded
            update new Plant_Program__c(
                Id = sourcePlantProgramId,
                Include__c = false
            );
            result.reparentedCount += movePlantFunctionsToTarget(sourcePlantProgramId, targetProgram.Id, plantId);
        }

        return result;
    }

    private static void validateEquationReparentRequest(EquationReparentRequest request) {
        if (request == null) {
            throw new AuraHandledException('Replacement Plant Program details are required.');
        }
        if (String.isBlank(request.sourcePlantProgramId) || String.isBlank(request.plantId) ||
            String.isBlank(request.shopMasterId) || String.isBlank(request.programIndex) ||
            String.isBlank(request.programCode) || String.isBlank(request.programName)) {
            throw new AuraHandledException('Complete all replacement Plant Program fields before deactivating the source program.');
        }
    }

    private static Id getOrCreatePlantShopForReparent(Id plantId, Id shopMasterId, String sector, String productType) {
        List<Plant_Shop__c> existingShops = [
            SELECT Id
            FROM Plant_Shop__c
            WHERE Auth_Plant_Name__c = :plantId
            AND Shop_Master__c = :shopMasterId
            LIMIT 1
        ];

        if (!existingShops.isEmpty()) {
            return existingShops[0].Id;
        }

        Shop_Master__c shopMaster = [
            SELECT Id, Shop__c, Auth_Sector__c, Product_Type__c
            FROM Shop_Master__c
            WHERE Id = :shopMasterId
            LIMIT 1
        ];

        Plant_Shop__c newPlantShop = new Plant_Shop__c(
            Auth_Plant_Name__c = plantId,
            Shop_Master__c = shopMasterId,
            Auth_Sector__c = String.isNotBlank(sector) ? sector : shopMaster.Auth_Sector__c,
            Product_Type__c = String.isNotBlank(productType) ? productType : shopMaster.Product_Type__c,
            Shop__c = shopMaster.Shop__c
        );
        insert newPlantShop;
        return newPlantShop.Id;
    }

    private static ReplacementProgramResult getOrCreateReplacementProgram(
        Id sourcePlantProgramId,
        Id plantId,
        Id plantShopId,
        String programIndex,
        String programCode,
        String programName,
        Id operationPlanId
    ) {
        List<Plant_Program__c> matchingPrograms = [
            SELECT Id, CreatedDate, Include__c, Program_Code__c, Plant_Program_Name__c, Shifts_Def__c, Auth_Plant_Name__c
            FROM Plant_Program__c
            WHERE Plant_Shop__c = :plantShopId
            AND Program_Product_Index__c = :programIndex
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        Plant_Program__c targetProgram;
        Boolean wasCreated = matchingPrograms.isEmpty();
        if (wasCreated) {
            targetProgram = new Plant_Program__c(
                Plant_Shop__c = plantShopId,
                Auth_Plant_Name__c = plantId,
                Program_Product_Index__c = programIndex,
                Include__c = true
            );
        } else {
            targetProgram = matchingPrograms[0];
            if (targetProgram.Id == sourcePlantProgramId) {
                throw new AuraHandledException('Choose a different Program Index or Shop for the replacement Plant Program.');
            }
        }

        targetProgram.Auth_Plant_Name__c = plantId;
        targetProgram.Program_Code__c = programCode;
        targetProgram.Plant_Program_Name__c = programName;
        targetProgram.Shifts_Def__c = operationPlanId;
        targetProgram.Include__c = true;
        upsert targetProgram;

        ReplacementProgramResult result = new ReplacementProgramResult();
        result.program = targetProgram;
        result.wasCreated = wasCreated;
        return result;
    }

    private static void ensurePlantProgramCodeExistsForReparent(String sector, String productType, String programCode) {
        if (String.isBlank(sector) || String.isBlank(productType) || String.isBlank(programCode)) {
            return;
        }

        List<Plant_Program_Code__c> existingCodes = [
            SELECT Id
            FROM Plant_Program_Code__c
            WHERE Auth_Sector__c = :sector
            AND Product_Type__c = :productType
            AND Program_Code__c = :programCode
            LIMIT 1
        ];

        if (existingCodes.isEmpty()) {
            insert new Plant_Program_Code__c(
                Auth_Sector__c = sector,
                Product_Type__c = productType,
                Program_Code__c = programCode
            );
        }
    }

    private static Integer movePlantFunctionsToTarget(Id sourcePlantProgramId, Id targetPlantProgramId, Id plantId) {
        List<Plant_Function__c> sourcePlantFunctions = [
            SELECT Id, Function__c, Status__c,
                   Plant_Program__c, Plant__c
            FROM Plant_Function__c
            WHERE Plant_Program__c = :sourcePlantProgramId
        ];

        if (sourcePlantFunctions.isEmpty()) {
            return 0;
        }

        Set<Id> functionIds = new Set<Id>();
        for (Plant_Function__c plantFunction : sourcePlantFunctions) {
            functionIds.add(plantFunction.Function__c);
        }

        Map<Id, Plant_Function__c> existingTargetFunctionsByFunctionId = new Map<Id, Plant_Function__c>();
        for (Plant_Function__c targetFunction : [
            SELECT Id, Function__c
            FROM Plant_Function__c
            WHERE Plant_Program__c = :targetPlantProgramId
            AND Function__c IN :functionIds
        ]) {
            existingTargetFunctionsByFunctionId.put(targetFunction.Function__c, targetFunction);
        }

        List<Plant_Function__c> sourcePlantFunctionsToUpdate = new List<Plant_Function__c>();
        List<Plant_Function__c> targetFunctionsToUpdate = new List<Plant_Function__c>();

        for (Plant_Function__c plantFunction : sourcePlantFunctions) {
            if (existingTargetFunctionsByFunctionId.containsKey(plantFunction.Function__c)) {
                Plant_Function__c existingTargetFunction = existingTargetFunctionsByFunctionId.get(plantFunction.Function__c);
                existingTargetFunction.Status__c = 'Active';
                existingTargetFunction.Plant__c = plantId;
                targetFunctionsToUpdate.add(existingTargetFunction);

                plantFunction.Status__c = 'Decommissioned';
                sourcePlantFunctionsToUpdate.add(plantFunction);
            } else {
                plantFunction.Plant_Program__c = targetPlantProgramId;
                plantFunction.Plant__c = plantId;
                plantFunction.Status__c = 'Active';
                sourcePlantFunctionsToUpdate.add(plantFunction);
            }
        }

        if (!targetFunctionsToUpdate.isEmpty()) {
            update targetFunctionsToUpdate;
        }
        if (!sourcePlantFunctionsToUpdate.isEmpty()) {
            update sourcePlantFunctionsToUpdate;
        }

        return sourcePlantFunctions.size();
    }

    private static String getPlantFunctionCompositeKey(Id plantProgramId, Id functionId) {
        return String.valueOf(plantProgramId) + ':' + String.valueOf(functionId);
    }

    private class ReplacementProgramResult {
        public Plant_Program__c program;
        public Boolean wasCreated;
    }


    // Wrapper classes
    public class InitialDataWrapper {
        @AuraEnabled public String plantName { get; set; }
        @AuraEnabled public String plantAuthSector { get; set; }
        @AuraEnabled public List<Plant_Shop__c> plantShops { get; set; }
        @AuraEnabled public List<Shop_Master__c> shopMasters { get; set; }
        @AuraEnabled public Map<Id, List<Plant_Program__c>> shopPrograms { get; set; }
        @AuraEnabled public List<Id> originalPlantProgramIds { get; set; }
        @AuraEnabled public List<Program_Master__c> programMasters { get; set; }
    }
    
    public class ShopData {
        @AuraEnabled public String plantId { get; set; }
        @AuraEnabled public String shopMasterId { get; set; }
    }

    public class ProgramData {
        @AuraEnabled public String plantProgramId { get; set; }
        @AuraEnabled public String plantId { get; set; }
        @AuraEnabled public String plantShopId { get; set; }
        @AuraEnabled public String programValue { get; set; }
        @AuraEnabled public String programCode { get; set; }
        @AuraEnabled public String programName { get; set; }
        @AuraEnabled public Boolean isSelected { get; set; }
        @AuraEnabled public String operationPlanId { get; set; }
        @AuraEnabled public Decimal auth3rdShiftValue { get; set; }
        @AuraEnabled public Map<String, Decimal> functionShiftValues { get; set; } // Map of Plant_Function__c Id -> shift value (legacy)
        @AuraEnabled public Map<String, Decimal> functionShift2ndValues { get; set; } // Map of Plant_Function__c Id -> 2nd shift value (legacy)
        @AuraEnabled public Map<String, Decimal> workbookShiftValues { get; set; } // Map of Workbook__c Id -> shift value (3rd shift or 2nd shift for 1→2)
        @AuraEnabled public Map<String, Decimal> workbookShift2ndValues { get; set; } // Map of Workbook__c Id -> 2nd shift value
    }

    public class EquationReparentRequest {
        @AuraEnabled public String sourcePlantProgramId { get; set; }
        @AuraEnabled public String plantId { get; set; }
        @AuraEnabled public String sector { get; set; }
        @AuraEnabled public String productType { get; set; }
        @AuraEnabled public String shopMasterId { get; set; }
        @AuraEnabled public String programCode { get; set; }
        @AuraEnabled public String programName { get; set; }
        @AuraEnabled public String operationPlanId { get; set; }
        @AuraEnabled public String programIndex { get; set; }
    }
    
    public class SaveResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Map<String, Id> shopMasterIdToPlantShopIdMap { get; set; }
        @AuraEnabled public List<Id> programIds { get; set; }
        @AuraEnabled public List<Plant_Function__c> plantFunctions { get; set; }
        @AuraEnabled public Integer createdProgramCount { get; set; }
        @AuraEnabled public Integer reparentedCount { get; set; }
    }

    /**
     * Get shift counts from Operation Plans
     * @param oldOpPlanId - Previous Operation Plan ID
     * @param newOpPlanId - New Operation Plan ID
     * @return ShiftDataWrapper with old and new shift counts
     */
    @AuraEnabled(cacheable=false)
    public static ShiftDataWrapper getOperationPlanShifts(Id oldOpPlanId, Id newOpPlanId) {
        ShiftDataWrapper result = new ShiftDataWrapper();
        
        Set<Id> opPlanIds = new Set<Id>();
        if (oldOpPlanId != null) {
            opPlanIds.add(oldOpPlanId);
        }
        if (newOpPlanId != null) {
            opPlanIds.add(newOpPlanId);
        }
        
        if (opPlanIds.isEmpty()) {
            return result;
        }
        
        Map<Id, Operation_Plan__c> opPlanMap = new Map<Id, Operation_Plan__c>([
            SELECT Id, Shifts_Numeric__c
            FROM Operation_Plan__c
            WHERE Id IN :opPlanIds
        ]);
        
        if (oldOpPlanId != null && opPlanMap.containsKey(oldOpPlanId)) {
            Operation_Plan__c oldOP = opPlanMap.get(oldOpPlanId);
            if (oldOP.Shifts_Numeric__c != null) {
                result.oldShifts = Integer.valueOf(oldOP.Shifts_Numeric__c);
            } else {
                System.debug('WARNING: Shifts_Numeric__c is null for Operation Plan: ' + oldOpPlanId);
                result.oldShifts = 0;
            }
        }
        
        if (newOpPlanId != null && opPlanMap.containsKey(newOpPlanId)) {
            Operation_Plan__c newOP = opPlanMap.get(newOpPlanId);
            if (newOP.Shifts_Numeric__c != null) {
                result.newShifts = Integer.valueOf(newOP.Shifts_Numeric__c);
            } else {
                System.debug('WARNING: Shifts_Numeric__c is null for Operation Plan: ' + newOpPlanId);
                result.newShifts = 0;
            }
        }
        
        System.debug('getOperationPlanShifts returning: oldShifts=' + result.oldShifts + ', newShifts=' + result.newShifts);
        return result;
    }

    public class ShiftDataWrapper {
        @AuraEnabled public Integer oldShifts { get; set; }
        @AuraEnabled public Integer newShifts { get; set; }
        
        public ShiftDataWrapper() {
            this.oldShifts = 0;
            this.newShifts = 0;
        }
    }

    /**
     * @description Get child Plant Programs for a master shop row (All, All Except Body, Paint, etc.)
     * Used by the accordion feature to show individual shop Plant Programs under master rows
     * @param plantId Plant ID
     * @param sector Sector value (e.g., 'Assembly', 'GPS', 'Polymers', 'Press')
     * @param productType Product Type value (e.g., 'Vehicle', 'Battery', 'Engine')
     * @param excludeShops List of shop values to exclude (e.g., ['All', 'Body', 'Paint'])
     * @return List of ChildPlantProgramWrapper with plant program details
     */
    @AuraEnabled(cacheable=false)
    public static List<ChildPlantProgramWrapper> getChildPlantPrograms(
        String plantId, 
        String sector, 
        String productType, 
        List<String> excludeShops
    ) {
        List<ChildPlantProgramWrapper> results = new List<ChildPlantProgramWrapper>();
        
        if (String.isBlank(plantId) || String.isBlank(sector) || String.isBlank(productType)) {
            return results;
        }
        
        System.debug('getChildPlantPrograms called:');
        System.debug('  plantId: ' + plantId);
        System.debug('  sector: ' + sector);
        System.debug('  productType: ' + productType);
        System.debug('  excludeShops: ' + excludeShops);
        
        // Query Plant Programs through Plant_Shop__c relationship
        List<Plant_Program__c> childPrograms;
        
        if (excludeShops != null && !excludeShops.isEmpty()) {
            childPrograms = [
                SELECT Id, Name, Program_Product_Index__c, Program_Code__c, Plant_Program_Name__c,
                       Include__c, Shifts_Def__c, Plant_Shop__c,
                       Plant_Shop__r.Shop__c, Plant_Shop__r.Auth_Sector__c, 
                       Plant_Shop__r.Product_Type__c, Plant_Shop__r.Shop_Master__c
                FROM Plant_Program__c
                WHERE Plant_Shop__r.Auth_Plant_Name__c = :plantId
                AND Plant_Shop__r.Auth_Sector__c = :sector
                AND Plant_Shop__r.Product_Type__c = :productType
                AND Plant_Shop__r.Shop__c NOT IN :excludeShops
                ORDER BY Plant_Shop__r.Shop__c, Program_Product_Index__c
            ];
        } else {
            childPrograms = [
                SELECT Id, Name, Program_Product_Index__c, Program_Code__c, Plant_Program_Name__c,
                       Include__c, Shifts_Def__c, Plant_Shop__c,
                       Plant_Shop__r.Shop__c, Plant_Shop__r.Auth_Sector__c, 
                       Plant_Shop__r.Product_Type__c, Plant_Shop__r.Shop_Master__c
                FROM Plant_Program__c
                WHERE Plant_Shop__r.Auth_Plant_Name__c = :plantId
                AND Plant_Shop__r.Auth_Sector__c = :sector
                AND Plant_Shop__r.Product_Type__c = :productType
                ORDER BY Plant_Shop__r.Shop__c, Program_Product_Index__c
            ];
        }
        
        System.debug('Found ' + childPrograms.size() + ' child Plant Programs');
        
        // Build result wrappers
        for (Plant_Program__c pp : childPrograms) {
            ChildPlantProgramWrapper wrapper = new ChildPlantProgramWrapper();
            wrapper.plantProgramId = pp.Id;
            wrapper.plantProgramName = pp.Name;
            wrapper.programIndex = pp.Program_Product_Index__c;
            wrapper.programCode = pp.Program_Code__c;
            wrapper.programName = pp.Plant_Program_Name__c;
            wrapper.isIncluded = pp.Include__c;
            wrapper.operationPlanId = pp.Shifts_Def__c;
            wrapper.plantShopId = pp.Plant_Shop__c;
            wrapper.shop = pp.Plant_Shop__r.Shop__c;
            wrapper.sector = pp.Plant_Shop__r.Auth_Sector__c;
            wrapper.productType = pp.Plant_Shop__r.Product_Type__c;
            wrapper.shopMasterId = pp.Plant_Shop__r.Shop_Master__c;
            
            results.add(wrapper);
        }
        
        return results;
    }
    
    /**
     * @description Wrapper class for child Plant Program data used in accordion
     */
    public class ChildPlantProgramWrapper {
        @AuraEnabled public Id plantProgramId { get; set; }
        @AuraEnabled public String plantProgramName { get; set; }
        @AuraEnabled public String programIndex { get; set; }
        @AuraEnabled public String programCode { get; set; }
        @AuraEnabled public String programName { get; set; }
        @AuraEnabled public Boolean isIncluded { get; set; }
        @AuraEnabled public Id operationPlanId { get; set; }
        @AuraEnabled public Id plantShopId { get; set; }
        @AuraEnabled public String shop { get; set; }
        @AuraEnabled public String sector { get; set; }
        @AuraEnabled public String productType { get; set; }
        @AuraEnabled public Id shopMasterId { get; set; }
    }

    /**
     * @description Wrapper class for Workbook with shift data
     */
    public class WorkbookWithShiftWrapper {
        @AuraEnabled public Id workbookId { get; set; }
        @AuraEnabled public String workbookName { get; set; }
        @AuraEnabled public String functionName { get; set; }
        @AuraEnabled public String functionalArea { get; set; }
        @AuraEnabled public String shop { get; set; }
        @AuraEnabled public String programCode { get; set; }
        @AuraEnabled public Decimal currentPosition1st { get; set; }
        @AuraEnabled public Decimal currentPosition2nd { get; set; }
        @AuraEnabled public Decimal currentPosition3rd { get; set; }
        @AuraEnabled public Decimal newShiftValue { get; set; }
        @AuraEnabled public Decimal newShift2ndValue { get; set; }
    }
    
    /**
     * @description Wrapper class for Workbook data in Allocate modal
     */
    public class WorkbookAllocateWrapper {
        @AuraEnabled public Id workbookId { get; set; }
        @AuraEnabled public String workbookName { get; set; }
        @AuraEnabled public String functionName { get; set; }
        @AuraEnabled public String functionalArea { get; set; }
        @AuraEnabled public String shop { get; set; }
        @AuraEnabled public String programCode { get; set; }
        @AuraEnabled public String programName { get; set; }
        @AuraEnabled public String classification { get; set; }
        @AuraEnabled public Decimal shift1st { get; set; }
        @AuraEnabled public Decimal shift2nd { get; set; }
        @AuraEnabled public Decimal shift3rd { get; set; }
        @AuraEnabled public Decimal newShift2nd { get; set; }
        @AuraEnabled public Decimal newShift3rd { get; set; }
    }
    
    /**
     * @description Save workbook shift values from Allocate modal
     * @param workbookRecordsJson JSON string of workbook records with updated shift values
     * @return String success message
     */
    @AuraEnabled(cacheable=false)
    public static String saveAllocateWorkbookData(String workbookRecordsJson) {
        try {
            List<WorkbookAllocateWrapper> workbookRecords = (List<WorkbookAllocateWrapper>) JSON.deserialize(
                workbookRecordsJson, 
                List<WorkbookAllocateWrapper>.class
            );
            
            List<Workbook__c> workbooksToUpdate = new List<Workbook__c>();
            
            for (WorkbookAllocateWrapper wrapper : workbookRecords) {
                Workbook__c wb = new Workbook__c(Id = wrapper.workbookId);
                Boolean hasChanges = false;
                
                // Update shift values based on what was edited
                if (wrapper.newShift2nd != null) {
                    Decimal current2nd = wrapper.shift2nd != null ? wrapper.shift2nd : 0;
                    if (wrapper.newShift2nd != current2nd) {
                        wb.Dec_2nd__c = wrapper.newShift2nd;
                        hasChanges = true;
                    }
                }
                if (wrapper.newShift3rd != null) {
                    Decimal current3rd = wrapper.shift3rd != null ? wrapper.shift3rd : 0;
                    if (wrapper.newShift3rd != current3rd) {
                        wb.Dec_3rd__c = wrapper.newShift3rd;
                        hasChanges = true;
                    }
                }
                
                if (hasChanges) {
                    workbooksToUpdate.add(wb);
                }
            }
            
            if (!workbooksToUpdate.isEmpty()) {
                update workbooksToUpdate;
                return 'Workbook data saved successfully. ' + workbooksToUpdate.size() + ' record(s) updated.';
            }
            
            return 'No records to update.';
        } catch (Exception e) {
            throw new AuraHandledException('Error saving workbook data: ' + e.getMessage());
        }
    }
    
    /**
     * @description Wrapper class for Plant Function with Workbook data (kept for backward compatibility)
     */
    public class PlantFunctionWithWorkbookWrapper {
        @AuraEnabled public Id plantFunctionId { get; set; }
        @AuraEnabled public String plantFunctionName { get; set; }
        @AuraEnabled public Id functionId { get; set; }
        @AuraEnabled public String functionName { get; set; }
        @AuraEnabled public Integer shiftsNumeric { get; set; }
        @AuraEnabled public Decimal currentPosition1st { get; set; }
        @AuraEnabled public Decimal currentPosition2nd { get; set; }
        @AuraEnabled public Decimal currentPosition3rd { get; set; }
        @AuraEnabled public Decimal newShiftValue { get; set; }
        @AuraEnabled public String programCode { get; set; }
        @AuraEnabled public String functionalArea { get; set; }
        @AuraEnabled public String shop { get; set; }
    }
    
    /**
     * Input wrapper for filterWorkbooksBySelectedFunctions
     */
    public class FilterWorkbookRequest {
        @InvocableVariable(label='Plant Program ID' description='Plant Program ID to filter Workbooks for')
        public Id plantProgramId;
        
        @InvocableVariable(label='Workbooks' description='Optional: List of Workbook records (used to get Plant_Program__c if plantProgramId is not provided)')
        public List<Workbook__c> workbooks;
        
        @InvocableVariable(label='Selected Function IDs' description='List of Plant Function IDs (as strings) that were selected. Not used when cloneAllFunctions is true.')
        public List<String> selectedFunctionIds;
        
        @InvocableVariable(label='Clone All Functions' description='If true, filter by all Plant Functions for the Plant Program')
        public Boolean cloneAllFunctions;
    }
    
    /**
     * Output wrapper for filterWorkbooksBySelectedFunctions
     */
    public class FilterWorkbookResult {
        @InvocableVariable(label='Filtered Workbooks' description='Filtered list of Workbook records')
        public List<Workbook__c> filteredWorkbooks;
    }
    
    /**
     * @description Get all Operation Plans for dropdown selection
     * @return List of OperationPlanOption wrapper containing Id and Name
     */
    @AuraEnabled(cacheable=true)
    public static List<OperationPlanOption> getOperationPlansForDropdown() {
        List<OperationPlanOption> options = new List<OperationPlanOption>();
        
        List<Operation_Plan__c> operationPlans = [
            SELECT Id, Name, Shifts_Numeric__c, Crews_Numeric__c, Days__c
            FROM Operation_Plan__c
            ORDER BY Name ASC
        ];
        
        for (Operation_Plan__c op : operationPlans) {
            OperationPlanOption option = new OperationPlanOption();
            option.id = op.Id;
            option.name = op.Name;
            option.shiftsNumeric = op.Shifts_Numeric__c != null ? Integer.valueOf(op.Shifts_Numeric__c) : 0;
            option.crewsNumeric = op.Crews_Numeric__c != null ? Integer.valueOf(op.Crews_Numeric__c) : 0;
            option.days = op.Days__c != null ? Integer.valueOf(op.Days__c) : 0;
            options.add(option);
        }
        
        return options;
    }
    
    /**
     * Wrapper class for Operation Plan dropdown options
     */
    public class OperationPlanOption {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public Integer shiftsNumeric { get; set; }
        @AuraEnabled public Integer crewsNumeric { get; set; }
        @AuraEnabled public Integer days { get; set; }
    }
    
    /**
     * @description Check if Plant_Program_Code__c record exists for the given combination,
     *              and insert if it doesn't exist
     * @param authSector The Auth Sector value
     * @param productType The Product Type value
     * @param programCode The Program Code value
     * @return SaveResult indicating success or failure
     */
    @AuraEnabled(cacheable=false)
    public static SaveResult ensurePlantProgramCodeExists(String authSector, String productType, String programCode) {
        SaveResult result = new SaveResult();
        
        // Validate inputs
        if (String.isBlank(authSector) || String.isBlank(productType) || String.isBlank(programCode)) {
            result.success = false;
            result.message = 'Auth Sector, Product Type, and Program Code are required';
            return result;
        }
        
        try {
            // Check if record already exists
            List<Plant_Program_Code__c> existingRecords = [
                SELECT Id
                FROM Plant_Program_Code__c
                WHERE Auth_Sector__c = :authSector
                AND Product_Type__c = :productType
                AND Program_Code__c = :programCode
                LIMIT 1
            ];
            
            // If record doesn't exist, insert it
            if (existingRecords.isEmpty()) {
                Plant_Program_Code__c newRecord = new Plant_Program_Code__c(
                    Auth_Sector__c = authSector,
                    Product_Type__c = productType,
                    Program_Code__c = programCode
                );
                
                insert newRecord;
                
                result.success = true;
                result.message = 'Plant Program Code record created successfully';
            } else {
                result.success = true;
                result.message = 'Plant Program Code record already exists';
            }
        } catch (Exception e) {
            result.success = false;
            result.message = 'Error ensuring Plant Program Code exists: ' + e.getMessage();
            System.debug('ERROR in ensurePlantProgramCodeExists: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
        }
        
        return result;
    }
    
    /**
     * @description Get Program Code options from Plant_Program_Code__c for the given Auth Sector and Product Type
     * Queries Plant_Program_Code__c where Auth_Sector__c and Product_Type__c match, returns distinct Program_Code__c values
     * @param authSector Auth Sector value (e.g., 'Assembly', 'GPS', 'Polymers', 'Press')
     * @param productType Product Type value (e.g., 'Vehicle', 'Battery', 'Engine', 'Press', 'Polymers')
     * @return List of Program Code options (label and value pairs) from Plant_Program_Code__c records
     */
    @AuraEnabled(cacheable=true)
    public static List<ProgramCodeOption> getProgramCodeOptionsBySectorProductType(String authSector, String productType) {
        List<ProgramCodeOption> options = new List<ProgramCodeOption>();
        
        try {
            if (String.isBlank(authSector) || String.isBlank(productType)) {
                return options;
            }
            
            List<Plant_Program_Code__c> records = [
                SELECT Program_Code__c
                FROM Plant_Program_Code__c
                WHERE Auth_Sector__c = :authSector
                AND Product_Type__c = :productType
                AND Program_Code__c != null
                ORDER BY Program_Code__c
            ];
            
            Set<String> seenValues = new Set<String>();
            for (Plant_Program_Code__c ppc : records) {
                String code = ppc.Program_Code__c;
                if (String.isNotBlank(code) && !seenValues.contains(code)) {
                    seenValues.add(code);
                    ProgramCodeOption option = new ProgramCodeOption();
                    option.label = code;
                    option.value = code;
                    options.add(option);
                }
            }
        } catch (Exception e) {
            System.debug('ERROR in getProgramCodeOptionsBySectorProductType: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
        }
        
        return options;
    }
    
    /**
     * @description Propagate Program Code and Program Name changes from master row to all matching Plant Programs
     * Used when updating Program Code/Name on "All Except Body, Paint" or "All" rows - cascades to all child shop records
     * @param plantId Plant ID
     * @param sector Sector value (e.g., 'Assembly', 'GPS', 'Polymers', 'Press')
     * @param productType Product Type value (e.g., 'Vehicle', 'Battery', 'Engine', 'Press', 'Polymers')
     * @param excludeShops List of shop values to exclude (e.g., ['All', 'Body', 'Paint', 'All Except Body, Paint'])
     * @param programCode New Program Code value
     * @param programName New Program Name value
     * @param programIndex Program Product Index (e.g., 'A', 'B', 'C')
     * @return SaveResult with count of updated records
     */
    @AuraEnabled(cacheable=false)
    public static SaveResult propagateProgramCodeAndNameToMatchingPrograms(
        String plantId,
        String sector,
        String productType,
        List<String> excludeShops,
        String programCode,
        String programName,
        String programIndex
    ) {
        SaveResult result = new SaveResult();
        result.success = false;
        
        try {
            if (String.isBlank(plantId) || String.isBlank(sector) || String.isBlank(productType)) {
                result.message = 'Plant ID, Sector, and Product Type are required';
                return result;
            }
            
            String query = 'SELECT Id, Program_Code__c, Plant_Program_Name__c, Plant_Shop__r.Shop__c ' +
                          'FROM Plant_Program__c ' +
                          'WHERE Plant_Shop__r.Auth_Plant_Name__c = :plantId ' +
                          'AND Plant_Shop__r.Auth_Sector__c = :sector ' +
                          'AND Plant_Shop__r.Product_Type__c = :productType';
            
            if (String.isNotBlank(programIndex)) {
                query += ' AND Program_Product_Index__c = :programIndex';
            }
            
            if (excludeShops != null && !excludeShops.isEmpty()) {
                query += ' AND Plant_Shop__r.Shop__c NOT IN :excludeShops';
            }
            
            List<Plant_Program__c> programsToUpdate = Database.query(query);
            
            if (programsToUpdate.isEmpty()) {
                result.success = true;
                result.message = 'No matching Plant Programs found to update';
                return result;
            }
            
            for (Plant_Program__c pp : programsToUpdate) {
                if (String.isNotBlank(programCode)) {
                    pp.Program_Code__c = programCode;
                }
                if (String.isNotBlank(programName)) {
                    pp.Plant_Program_Name__c = programName;
                }
            }
            
            update programsToUpdate;
            
            result.success = true;
            result.message = 'Successfully updated Program Code/Name on ' + programsToUpdate.size() + ' Plant Program(s)';
            
        } catch (Exception e) {
            result.success = false;
            result.message = 'Error propagating Program Code/Name: ' + e.getMessage();
            System.debug('Exception in propagateProgramCodeAndNameToMatchingPrograms: ' + e.getMessage());
            throw new AuraHandledException(result.message);
        }
        
        return result;
    }
    
    /**
     * Wrapper class for Program Code dropdown options
     */
    public class ProgramCodeOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
    }
}