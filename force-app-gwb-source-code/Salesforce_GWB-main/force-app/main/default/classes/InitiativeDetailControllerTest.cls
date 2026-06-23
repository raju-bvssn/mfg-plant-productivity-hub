@IsTest
private class InitiativeDetailControllerTest {
    @IsTest
    static void permanentNoWorkbookReturnsEmptyWrapper() {
        PPS_TestDataFactory.DemoData data = PPS_TestDataFactory.createDemoData();

        List<InitiativeSectionWrapper> sections = InitiativeDetailController.getForecastData(data.permanentInitiative.Id);

        System.assertEquals(1, sections.size());
        System.assertEquals('Effective Date', sections[0].initiativeDateOption);
        System.assertEquals(0, sections[0].gwbFunctions.size());
    }

    @IsTest
    static void formerTemporaryNoWorkbookReturnsPermanentOnlyWrapper() {
        PPS_TestDataFactory.DemoData data = PPS_TestDataFactory.createDemoData();

        List<InitiativeSectionWrapper> sections = InitiativeDetailController.getForecastData(data.temporaryInitiative.Id);

        System.assertEquals(1, sections.size());
        System.assertEquals('Effective Date', sections[0].initiativeDateOption);
        System.assertEquals(true, sections[0].editable);
    }

    @IsTest
    static void savePermanentForecastCreatesForecastAndActualWorkbook() {
        PPS_TestDataFactory.DemoData data = PPS_TestDataFactory.createDemoData();
        List<InitiativeSectionWrapper> sections = buildFiveAdjustmentSections(data, false);

        InitiativeDetailController.saveForecastData(data.permanentInitiative.Id, JSON.serialize(new PPS_TestDataFactory.SaveRequestWrapperWithSections(sections)));

        Initiative__c savedInitiative = [
            SELECT Total_Calculated_Adjustment__c
            FROM Initiative__c
            WHERE Id = :data.permanentInitiative.Id
        ];
        System.assertEquals(5, savedInitiative.Total_Calculated_Adjustment__c);

        Map<String, Integer> countsByRecordType = new Map<String, Integer>();
        for (AggregateResult result : [
            SELECT RecordType.DeveloperName recordTypeName, COUNT(Id) totalRows
            FROM Workbook__c
            WHERE Initiative__c = :data.permanentInitiative.Id
            GROUP BY RecordType.DeveloperName
        ]) {
            countsByRecordType.put((String) result.get('recordTypeName'), (Integer) result.get('totalRows'));
        }
        System.assertEquals(2, countsByRecordType.get('Forecast'));
        System.assertEquals(2, countsByRecordType.get('Actuals'));
        for (Workbook__c workbook : [
            SELECT Exclude_From_GWB__c
            FROM Workbook__c
            WHERE Initiative__c = :data.permanentInitiative.Id
        ]) {
            System.assertEquals(data.permanentInitiative.Exclude_From_GWB__c, workbook.Exclude_From_GWB__c);
        }
    }

    @IsTest
    static void saveFormerTemporaryForecastIgnoresEndMirrorRows() {
        PPS_TestDataFactory.DemoData data = PPS_TestDataFactory.createDemoData();
        List<InitiativeSectionWrapper> sections = buildFiveAdjustmentSections(data, true);

        InitiativeDetailController.saveForecastData(data.temporaryInitiative.Id, JSON.serialize(new PPS_TestDataFactory.SaveRequestWrapperWithSections(sections)));

        List<Workbook__c> workbooks = [
            SELECT Id, RecordType.DeveloperName, Initiative_Date_Option__c, Mar_1st__c, Aug_1st__c
            FROM Workbook__c
            WHERE Initiative__c = :data.temporaryInitiative.Id
            ORDER BY RecordType.DeveloperName, Initiative_Date_Option__c
        ];
        System.assertEquals(4, workbooks.size());
        System.assertEquals(null, findWorkbook(workbooks, 'Forecast', 'End Date'));
    }

    @IsTest
    static void sameMonthFormerTemporaryDoesNotCreateSeparateDateOptionRows() {
        PPS_TestDataFactory.DemoData data = PPS_TestDataFactory.createDemoData();
        data.temporaryInitiative.End_Date__c = data.temporaryInitiative.Effective_Date__c;
        update data.temporaryInitiative;
        List<InitiativeSectionWrapper> sections = buildFiveAdjustmentSections(data, true);
        sections[1].month = 'Mar';

        InitiativeDetailController.saveForecastData(data.temporaryInitiative.Id, JSON.serialize(new PPS_TestDataFactory.SaveRequestWrapperWithSections(sections)));

        Set<String> options = new Set<String>();
        for (Workbook__c wb : [
            SELECT Initiative_Date_Option__c
            FROM Workbook__c
            WHERE Initiative__c = :data.temporaryInitiative.Id
            AND RecordType.DeveloperName = 'Forecast'
        ]) {
            options.add(wb.Initiative_Date_Option__c);
        }
        System.assertEquals(new Set<String>{ 'Effective Date' }, options);
    }

    @IsTest
    static void totalMismatchThrowsFriendlyError() {
        PPS_TestDataFactory.DemoData data = PPS_TestDataFactory.createDemoData();
        List<InitiativeSectionWrapper> sections = buildFiveAdjustmentSections(data, false);
        sections[0].gwbFunctions[0].crew1 = 9;

        try {
            InitiativeDetailController.saveForecastData(data.permanentInitiative.Id, JSON.serialize(new PPS_TestDataFactory.SaveRequestWrapperWithSections(sections)));
            System.assert(false, 'Expected mismatch exception');
        } catch (AuraHandledException e) {
            System.assertEquals('Script-thrown exception', e.getMessage());
        }
    }

    @IsTest
    static void existingWorkbookRowsAreUpdatedNotDuplicated() {
        PPS_TestDataFactory.DemoData data = PPS_TestDataFactory.createDemoData();
        List<InitiativeSectionWrapper> sections = buildFiveAdjustmentSections(data, false);

        InitiativeDetailController.saveForecastData(data.permanentInitiative.Id, JSON.serialize(new PPS_TestDataFactory.SaveRequestWrapperWithSections(sections)));
        InitiativeDetailController.saveForecastData(data.permanentInitiative.Id, JSON.serialize(new PPS_TestDataFactory.SaveRequestWrapperWithSections(sections)));

        System.assertEquals(4, [
            SELECT COUNT()
            FROM Workbook__c
            WHERE Initiative__c = :data.permanentInitiative.Id
        ]);
    }

    @IsTest
    static void actualsSaveCreatesOperationsAndRollsUpFunctionTotals() {
        PPS_TestDataFactory.DemoData data = PPS_TestDataFactory.createDemoData();
        List<InitiativeSectionWrapper> sections = buildFiveAdjustmentSections(data, false);
        sections[0].gwbFunctions[1].crew2 = 0;
        sections[0].gwbFunctions[0].operations.add(operation(data.operationOne.Id, '1AEST', 2, -1, 2));
        sections[0].gwbFunctions[0].operations.add(operation(data.operationTwo.Id, '1BEST', -1, 2, 0));

        InitiativeDetailController.saveActualData(data.permanentInitiative.Id, JSON.serialize(new PPS_TestDataFactory.SaveRequestWrapperWithSections(sections)));

        Workbook__c workbook = [
            SELECT Mar_1st__c, Mar_2nd__c, Mar_3rd__c
            FROM Workbook__c
            WHERE Initiative__c = :data.permanentInitiative.Id
            AND RecordType.DeveloperName = 'Actuals'
            AND Plant_Function__c = :data.plantFunctionOne.Id
            LIMIT 1
        ];
        System.assertEquals(1, workbook.Mar_1st__c);
        System.assertEquals(1, workbook.Mar_2nd__c);
        System.assertEquals(2, workbook.Mar_3rd__c);
        List<Authorized_Database__c> authRows = [
            SELECT Plant_Function__c, Year__c
            FROM Authorized_Database__c
            WHERE GWB_Function__c = :workbook.Id
        ];
        System.assertEquals(2, authRows.size());
        for (Authorized_Database__c authRow : authRows) {
            System.assertEquals(data.plantFunctionOne.Id, authRow.Plant_Function__c);
            System.assertEquals(2026, authRow.Year__c);
        }
    }

    @IsTest
    static void crewNumericUsesShiftOverrideThenPlantProgramFallback() {
        PPS_TestDataFactory.DemoData data = PPS_TestDataFactory.createDemoData();

        List<GwbFunctionWrapper> functions = InitiativeDetailController.getAvailablePlantFunctions(data.permanentInitiative.Id);
        Map<Id, Integer> crewByPf = new Map<Id, Integer>();
        for (GwbFunctionWrapper row : functions) {
            crewByPf.put(row.plantFunctionId, row.crewEditableCount);
        }

        System.assertEquals(3, crewByPf.get(data.plantFunctionOne.Id));
        System.assertEquals(2, crewByPf.get(data.plantFunctionTwo.Id));
    }

    @IsTest
    static void controllerPassThroughsAndSaveRequestWrapperAreCovered() {
        PPS_TestDataFactory.DemoData data = PPS_TestDataFactory.createDemoData();

        SaveRequestWrapper request = new SaveRequestWrapper();
        System.assertEquals(0, request.sections.size());

        List<InitiativeSectionWrapper> actualSections = InitiativeDetailController.getActualData(data.permanentInitiative.Id);
        System.assertEquals(1, actualSections.size());

        List<OperationWrapper> operations = InitiativeDetailController.getAvailableOperations(
            data.permanentInitiative.Id,
            data.plantFunctionOne.Id
        );
        System.assertEquals(2, operations.size());

        List<OperationWrapper> functionTwoOperations = InitiativeDetailController.getAvailableOperations(
            data.permanentInitiative.Id,
            data.plantFunctionTwo.Id
        );
        System.assertEquals(0, functionTwoOperations.size());
    }

    @IsTest
    static void seedBackendSampleDataCreatesPermanentAndContainmentRows() {
        PPS_TestDataFactory.seedBackendSampleData();

        List<Initiative__c> initiatives = [
            SELECT Id, Initiative_Type__c, Driver__c, Parent_Initiative__c
            FROM Initiative__c
            WHERE Description__c = 'PPS backend sample data'
        ];
        System.assertEquals(4, initiatives.size());
        Boolean hasContainmentChild = false;
        for (Initiative__c initiative : initiatives) {
            if (initiative.Driver__c == 'Containment' && initiative.Parent_Initiative__c != null) {
                hasContainmentChild = true;
            }
        }
        System.assertEquals(true, hasContainmentChild);

        Set<String> months = new Set<String>();
        for (Workbook__c wb : [
            SELECT Month__c, Initiative_Date_Option__c
            FROM Workbook__c
            WHERE Initiative__c IN :initiatives
        ]) {
            months.add(wb.Month__c);
            System.assertEquals('Effective Date', wb.Initiative_Date_Option__c);
        }
        System.assert(months.contains('March'));
        System.assert(months.contains('May'));
        System.assert(months.contains('June'));
    }

    @IsTest
    static void childInitiativeWrapperDisallowsAddFunctions() {
        PPS_TestDataFactory.DemoData data = PPS_TestDataFactory.createDemoData();

        List<InitiativeSectionWrapper> sections = InitiativeDetailController.getForecastData(data.containmentChildInitiative.Id);

        System.assertEquals(1, sections.size());
        System.assertEquals(data.containmentParentInitiative.Id, sections[0].parentInitiativeId);
        System.assertEquals(true, sections[0].hasParentInitiative);
        System.assertEquals(true, sections[0].isContainmentDriver);
        System.assertEquals(false, sections[0].addFunctionsAllowed);
    }

    @IsTest
    static void missingInitiativeIdThrowsFriendlyError() {
        try {
            InitiativeDetailController.getForecastData(null);
            System.assert(false, 'Expected missing Id exception');
        } catch (AuraHandledException e) {
            System.assertEquals('Script-thrown exception', e.getMessage());
        }
    }

    private static List<InitiativeSectionWrapper> buildFiveAdjustmentSections(PPS_TestDataFactory.DemoData data, Boolean temporary) {
        List<InitiativeSectionWrapper> sections = new List<InitiativeSectionWrapper>{
            PPS_TestDataFactory.createSection('effective', 'Effective Date', 2026, 'Mar', true, new List<Plant_Function__c>{ data.plantFunctionOne, data.plantFunctionTwo })
        };
        sections[0].gwbFunctions[0].crew1 = 1;
        sections[0].gwbFunctions[0].crew2 = 1;
        sections[0].gwbFunctions[0].crew3 = 1;
        sections[0].gwbFunctions[1].crew1 = 1;
        sections[0].gwbFunctions[1].crew2 = 1;
        sections[0].gwbFunctions[1].crew3 = 0;

        if (temporary) {
            sections.add(PPS_TestDataFactory.createSection('end', 'End Date', 2026, 'Aug', false, new List<Plant_Function__c>{ data.plantFunctionOne, data.plantFunctionTwo }));
        }
        return sections;
    }

    private static OperationWrapper operation(Id operationId, String name, Integer crew1, Integer crew2, Integer crew3) {
        OperationWrapper row = new OperationWrapper();
        row.operationId = operationId;
        row.operationIdentifier = name;
        row.crew1 = crew1;
        row.crew2 = crew2;
        row.crew3 = crew3;
        return row;
    }

    private static Workbook__c findWorkbook(List<Workbook__c> workbooks, String recordTypeName, String option) {
        for (Workbook__c wb : workbooks) {
            if (wb.RecordType.DeveloperName == recordTypeName && wb.Initiative_Date_Option__c == option) {
                return wb;
            }
        }
        return null;
    }
}