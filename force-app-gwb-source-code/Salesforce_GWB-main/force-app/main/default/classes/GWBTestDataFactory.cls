/**
 * GWB Test Data Factory
 */
@isTest
public class GWBTestDataFactory {

     /**
     * Create a Plant__c record
     * @param plantName - Name for the Plant
     * @param doInsert - Whether to insert the record
     * @return Plant__c record
     
    public static Plant__c createPlant(String plantName, Boolean doInsert) {
        Plant__c plant = new Plant__c(Name = plantName);
        if (doInsert) {
            insert plant;
        }
        return plant;
    } */
    
    /**
     * Create a Function record with default or custom values
     * @param productType - Product Type value (default: 'Equation')
     * @param authSector - Auth Sector value (default: 'Equation')
     * @param doInsert - Whether to insert the record (default: true)
     * @return Function__c record
     */
    public static Function__c createFunction(String productType, String authSector, Boolean doInsert) {
        return createFunction(productType, authSector, null, doInsert);
    }
    
    /**
     * Create a Function record with default or custom values
     * @param productType - Product Type value (default: 'Equation')
     * @param authSector - Auth Sector value (default: 'Equation')
     * @param includedInAuthPlan - Optional. When false, avoids FunctionTrigger creating Workbooks
     * @param doInsert - Whether to insert the record (default: true)
     * @return Function__c record
     */
    public static Function__c createFunction(String productType, String authSector, Boolean includedInAuthPlan, Boolean doInsert) {
        Function__c func = new Function__c(
            Product_Type__c = productType != null ? productType : 'Equation',
            Auth_Sector__c = authSector != null ? authSector : 'Equation',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base'
        );
        if (includedInAuthPlan != null) {
            func.Included_in_Auth_Plan_of_Record__c = includedInAuthPlan;
        }
        
        if (doInsert) {
            insert func;
        }
        
        return func;
    }
    
    /**
     * Create a Function record with default values and insert
     */
    public static Function__c createFunction() {
        return createFunction('Equation', 'Equation', true);
    }
    
    /**
     * Create a Function record for ManagePlantShops (matches Plant_Program criteria)
     * @param productType - Product Type (e.g. 'Vehicle')
     * @param authSector - Auth Sector (e.g. 'Assembly')
     * @param shopMasterView - Shop_Master_View__c (e.g. 'All')
     * @param programProductIndex - Program_Product_Index__c (e.g. 'A')
     * @param doInsert - Whether to insert
     */
    public static Function__c createFunctionForPlantShops(String productType, String authSector, String shopMasterView, String programProductIndex, Boolean doInsert) {
        Function__c func = new Function__c(
            Product_Type__c = productType != null ? productType : 'Vehicle',
            Auth_Sector__c = authSector != null ? authSector : 'Assembly',
            Shop_Master_View__c = shopMasterView,
            Program_Product_Index__c = programProductIndex,
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base',
            Included_in_Auth_Plan_of_Record__c = true
        );
        if (doInsert) {
            insert func;
        }
        return func;
    }
    
    /**
     * Create a Plant Program record
     * @param doInsert - Whether to insert the record (default: true)
     * @return Plant_Program__c record
     */
    public static Plant_Program__c createPlantProgram(Boolean doInsert) {
        Plant__c plant = createPlant(null, true);
        Plant_Program__c plantProgram = new Plant_Program__c(
            Auth_Plant_Name__c = plant.Id
        );
        
        if (doInsert) {
            insert plantProgram;
        }
        
        return plantProgram;
    }
    
    /**
     * Create a Plant Program record and insert
     */
    public static Plant_Program__c createPlantProgram() {
        return createPlantProgram(true);
    }
    
    /**
     * Create a Plant Program record for ManagePlantShops (linked to Plant_Shop__c)
     * Auth_Sector1__c and Product_Type__c are formula fields from Plant_Shop__r
     * @param plantShopId - Related Plant_Shop__c Id
     * @param programIndex - Program_Product_Index__c value
     * @param includeVal - Include__c value
     * @param programCode - Program_Code__c value (optional, use valid picklist e.g. 'CSS', 'Ultium')
     * @param doInsert - Whether to insert the record
     * @return Plant_Program__c record
     */
    public static Plant_Program__c createPlantProgramForShop(
        Id plantShopId,
        String programIndex,
        Boolean includeVal,
        String programCode,
        Boolean doInsert
    ) {
        Plant_Program__c pp = new Plant_Program__c(
            Plant_Shop__c = plantShopId,
            Program_Product_Index__c = programIndex != null ? programIndex : 'A',
            Include__c = includeVal != null ? includeVal : true
        );
        if (String.isNotBlank(programCode)) {
            pp.Program_Code__c = programCode;
        }
        // Populate Auth_Plant_Name__c (required lookup) from the parent Plant_Shop__c
        if (plantShopId != null) {
            List<Plant_Shop__c> shops = [SELECT Auth_Plant_Name__c FROM Plant_Shop__c WHERE Id = :plantShopId LIMIT 1];
            if (!shops.isEmpty() && shops[0].Auth_Plant_Name__c != null) {
                pp.Auth_Plant_Name__c = shops[0].Auth_Plant_Name__c;
            }
        }
        if (doInsert) {
            insert pp;
        }
        return pp;
    }
    
    /**
     * Create a Plant Function record
     * @param functionId - Related Function__c Id
     * @param plantProgramId - Related Plant_Program__c Id
     * @param externalId - External Id value
     * @param doInsert - Whether to insert the record
     * @return Plant_Function__c record
     */
    public static Plant_Function__c createPlantFunction(Id functionId, Id plantProgramId, String externalId, Boolean doInsert) {
        
        if (functionId != null) {
            Function__c f = [SELECT Id, Included_in_Auth_Plan_of_Record__c FROM Function__c
                             WHERE Id = :functionId LIMIT 1];
            
            if (f != null || f.Included_in_Auth_Plan_of_Record__c != true) {
                f.Included_in_Auth_Plan_of_Record__c = true;
                update f;
            }
        }
        
        List<Plant_Function__c> existingPf = [
            SELECT Id,
            Function__c,
            Plant_Program__c
            FROM Plant_Function__c
            WHERE Function__c = :functionId
            AND Plant_Program__c = :plantProgramId
            LIMIT 1
        ];
        
        if (!existingPf.isEmpty()) {
            return existingPf[0];
        }

        
        Plant_Function__c plantFunction = new Plant_Function__c(
            Function__c = functionId,
            Plant_Program__c = plantProgramId
        );
        
        if (doInsert) {
            insert plantFunction;
        }
        
        return plantFunction;
    }
    
    /**
     * Create Plant Program Code records with default values
     * @param doInsert - Whether to insert the records
     * @return List of Plant_Program_Code__c records
     */
    public static List<Plant_Program_Code__c> createPlantProgramCodes(Boolean doInsert) {
        List<Plant_Program_Code__c> plantProgramCodes = new List<Plant_Program_Code__c>();
        
        plantProgramCodes.add(new Plant_Program_Code__c(
            Program_Code__c = 'CSS',
            Product_Type__c = 'Battery',
            Auth_Sector__c = 'Assembly'
        ));
        
        plantProgramCodes.add(new Plant_Program_Code__c(
            Program_Code__c = 'GenV',
            Product_Type__c = 'Battery',
            Auth_Sector__c = 'GPS'
        ));
        
        if (doInsert) {
            insert plantProgramCodes;
        }
        
        return plantProgramCodes;
    }
    
    /**
     * Create Plant Program Code records and insert
     */
    public static List<Plant_Program_Code__c> createPlantProgramCodes() {
        return createPlantProgramCodes(true);
    }
    
    /**
     * Create a single Plant Program Code record
     * @param programCode - Program Code value
     * @param productType - Product Type value
     * @param authSector - Auth Sector value
     * @param functionalArea - Functional Area value
     * @param doInsert - Whether to insert the record
     * @return Plant_Program_Code__c record
     */
    public static Plant_Program_Code__c createPlantProgramCode(
        String programCode, 
        String productType, 
        String authSector, 
        String functionalArea, 
        Boolean doInsert
    ) {
        Plant_Program_Code__c ppc = new Plant_Program_Code__c(
            Program_Code__c = programCode,
            Product_Type__c = productType,
            Auth_Sector__c = authSector
        );
        
        if (doInsert) {
            insert ppc;
        }
        
        return ppc;
    }
    
    /**
     * Create a Plant__c record
     * @param name - Plant Name (optional, default: generated)
     * @param doInsert - Whether to insert the record
     * @return Plant__c record
     */
    public static Plant__c createPlant(String name, Boolean doInsert) {
        Plant__c plant = new Plant__c();
        plant.Auth_Region__c = 'GMNA';
        plant.MVP__c = 'GWB';
        if (String.isNotBlank(name)) {
            plant.Name = name;
        } else {
            plant.Name = 'TEST_PLANT_' + String.valueOf(System.now().getTime());
        }
        if (doInsert) {
            insert plant;
        }
        return plant;
    }
    
    /**
     * Create a Plant__c record and insert
     */
    public static Plant__c createPlant() {
        return createPlant(null, true);
    }
    
    /**
     * Create a Shop_Master__c record for ManagePlantShops tests
     * @param authSector - Auth Sector value (e.g., 'Assembly', 'GPS')
     * @param productType - Product Type value (e.g., 'Vehicle', 'Battery')
     * @param shop - Shop value (e.g., 'All', 'Body')
     * @param active - Active__c checkbox value (default: true)
     * @param doInsert - Whether to insert the record
     * @return Shop_Master__c record
     */
    public static Shop_Master__c createShopMaster(String authSector, String productType, String shop, Boolean active, Boolean doInsert) {
        Shop_Master__c sm = new Shop_Master__c(
            Auth_Sector__c = authSector != null ? authSector : 'Assembly',
            Product_Type__c = productType != null ? productType : 'Vehicle',
            Shop__c = shop != null ? shop : 'All',
            Active__c = active != null ? active : true
        );
        if (doInsert) {
            insert sm;
        }
        return sm;
    }
    
    /**
     * Create a Shop_Master__c record and insert
     */
    public static Shop_Master__c createShopMaster() {
        return createShopMaster('Assembly', 'Vehicle', 'All', true, true);
    }
    
    /**
     * Create a Plant_Shop__c record linking Plant to Shop_Master
     * @param plantId - Related Plant__c Id
     * @param shopMasterId - Related Shop_Master__c Id
     * @param authSector - Auth Sector value
     * @param productType - Product Type value
     * @param shop - Shop value
     * @param doInsert - Whether to insert the record
     * @return Plant_Shop__c record
     */
    public static Plant_Shop__c createPlantShop(Id plantId, Id shopMasterId, String authSector, String productType, String shop, Boolean doInsert) {
        Plant_Shop__c ps = new Plant_Shop__c(
            Auth_Plant_Name__c = plantId,
            Shop_Master__c = shopMasterId,
            Auth_Sector__c = authSector != null ? authSector : 'Assembly',
            Product_Type__c = productType != null ? productType : 'Vehicle',
            Shop__c = shop != null ? shop : 'All'
        );
        if (doInsert) {
            insert ps;
        }
        return ps;
    }
    
    /**
     * Create an Operation_Plan__c record for shift definitions
     * @param shiftsNumeric - Number of shifts
     * @param doInsert - Whether to insert the record
     * @return Operation_Plan__c record
     */
    public static Operation_Plan__c createOperationPlan(Integer shiftsNumeric, Boolean doInsert) {
        Operation_Plan__c op = new Operation_Plan__c(
            Name = 'TEST_OP_' + String.valueOf(System.now().getTime()),
            Shifts_Numeric__c = shiftsNumeric != null ? shiftsNumeric : 1,
            Crews_Numeric__c = 1,
            Days__c = 5
        );
        if (doInsert) {
            insert op;
        }
        return op;
    }

    /**
     * Create a Workbook__c record with optional values
     * @param year - Year value (default: current year)
     * @param month - Month value (optional)
     * @param doInsert - Whether to insert the record
     * @return Workbook__c record
     */
    public static Workbook__c createWorkbook(Decimal year, String month, Boolean doInsert) {
        Decimal currentYear = Date.today().year();
        
        Workbook__c workbook = new Workbook__c(
            Year__c = year != null ? year : currentYear
        );
        
        if (doInsert) {
            insert workbook;
        }
        
        return workbook;
    }
    
    /**
     * Create a Workbook__c record with default values and insert
     */
    public static Workbook__c createWorkbook() {
        return createWorkbook(null, null, true);
    }
    
    /**
     * Create multiple Workbook__c records
     * @param count - Number of records to create
     * @param doInsert - Whether to insert the records
     * @return List of Workbook__c records
     */
    public static List<Workbook__c> createWorkbooks(Integer count, Boolean doInsert) {
        List<Workbook__c> workbooks = new List<Workbook__c>();
        Decimal currentYear = Date.today().year();
        
        for (Integer i = 0; i < count; i++) {
            workbooks.add(new Workbook__c(
                Year__c = currentYear
            ));
        }
        
        if (doInsert) {
            insert workbooks;
        }
        
        return workbooks;
    }
    
    /**
     * Create multiple Workbook__c records and insert
     */
    public static List<Workbook__c> createWorkbooks(Integer count) {
        return createWorkbooks(count, true);
    }
    
    /**
     * Create a Workbook__c record linked to Function__c (for CopyTempWorkbookMonthsToWorkbook flows)
     * @param functionId - Related Function__c Id
     * @param doInsert - Whether to insert the record
     * @return Workbook__c record
     */
    public static Workbook__c createWorkbookWithFunction(Id functionId, Boolean doInsert) {
        Workbook__c workbook = new Workbook__c(
            Year__c = Date.today().year()
        );
        if (doInsert) {
            insert workbook;
        }
        return workbook;
    }
    
    
    /**
     * Create a complete Workbook test setup with history and insert
     */
    public static Map<String, Object> createCompleteWorkbookSetup() {
        return createCompleteWorkbookSetup(true);
    }

    /**
     * Create a complete Workbook test setup without Change_Log__c dependencies.
     * @param createHistory - Whether to create field history by making updates
     * @return Map containing created records with key: 'workbook'
     */
    public static Map<String, Object> createCompleteWorkbookSetup(Boolean createHistory) {
        Map<String, Object> testData = new Map<String, Object>();

        Decimal currentYear = Date.today().year();
        Workbook__c workbook = createWorkbook(currentYear, 'January', true);
        testData.put('workbook', workbook);

        if (createHistory) {
            // Multiple updates create field history records needed by tests.
            workbook.Year__c = currentYear + 1;
            update workbook;
        }

        return testData;
    }

    /**
     * Create a GWB Year target record for tests.
     */
    public static GWB_Year__c createGwbYearTarget(Id plantId, String year, String status, Boolean doInsert) {
        Id targetRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'GWB_Year__c'
            AND DeveloperName = 'Target'
            LIMIT 1
        ].Id;
        Plant_Sector__c plantSector = doInsert ? createPlantSector(plantId, 'Assembly', true) : null;

        GWB_Year__c gwbYear = new GWB_Year__c(
            Plant__c = plantId,
            Plant_Sector__c = plantSector == null ? null : plantSector.Id,
            Sector__c = 'Assembly',
            Year__c = String.isBlank(year) ? String.valueOf(Date.today().year()) : year,
            Status__c = String.isBlank(status) ? 'Draft' : status,
            Version__c = 'TestVersion',
            M_Schedule_Version__c = '01+11',
            RecordTypeId = targetRecordTypeId
        );
        if (doInsert) {
            insert gwbYear;
        }
        return gwbYear;
    }

    /**
     * Create a Plant Sector record with valid defaults.
     */
    public static Plant_Sector__c createPlantSector(Id plantId, String authSector, Boolean doInsert) {
        Plant_Sector__c plantSector = new Plant_Sector__c(
            Plant__c = plantId
        );
        if (doInsert) {
            insert plantSector;
        }
        return plantSector;
    }

    /**
     * Create a Plant Shop Target record with valid defaults.
     */
    public static Plant_Shop_Target__c createPlantShopTarget(
        Id gwbYearId,
        Id plantId,
        Decimal year,
        String month,
        String driver,
        String classification,
        Decimal totalChangesNeeded,
        String status,
        Boolean doInsert
    ) {
        Plant_Shop_Target__c target = new Plant_Shop_Target__c(
            Target__c = gwbYearId,
            Plant__c = plantId,
            Year__c = year == null ? Date.today().year() : year,
            Month__c = String.isBlank(month) ? 'January' : month,
            Driver__c = String.isBlank(driver) ? 'Productivity' : driver,
            Classification__c = String.isBlank(classification) ? 'OTS' : classification,
            Total_Changes_Needed__c = totalChangesNeeded,
            Status__c = String.isBlank(status) ? 'Draft' : status
        );
        if (doInsert) {
            insert target;
        }
        return target;
    }

    /**
     * Create a Plant Shop Target Item record with valid defaults.
     */
    public static Plant_Shop_Target_Item__c createPlantShopTargetItem(
        Id plantShopTargetId,
        String shopManagerView,
        Decimal adjustment,
        Boolean doInsert
    ) {
        Plant_Shop_Target_Item__c item = new Plant_Shop_Target_Item__c(
            Plant_Shop_Target__c = plantShopTargetId,
            Shop_Manager_View__c = String.isBlank(shopManagerView) ? 'Body' : shopManagerView,
            Adjustment__c = adjustment == null ? 0 : adjustment
        );
        if (doInsert) {
            insert item;
        }
        return item;
    }

    /**
     * Create a Function record that can be matched by PlantProgramTriggerHandler.
     */
    public static Function__c createFunctionForPlantProgram(
        String productType,
        String authSector,
        String shopMasterView,
        Boolean includedInAuthPlan,
        Boolean doInsert
    ) {
        Function__c func = new Function__c(
            Product_Type__c = String.isBlank(productType) ? 'Vehicle' : productType,
            Auth_Sector__c = String.isBlank(authSector) ? 'Assembly' : authSector,
            Shop_Master_View__c = String.isBlank(shopMasterView) ? 'Body' : shopMasterView,
            Benchmark_Rule__c = 'Test benchmark rule',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base',
            Included_in_Auth_Plan_of_Record__c = includedInAuthPlan == null ? true : includedInAuthPlan
        );
        if (doInsert) {
            insert func;
        }
        return func;
    }

}