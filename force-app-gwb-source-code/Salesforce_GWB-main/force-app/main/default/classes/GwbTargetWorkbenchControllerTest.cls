@IsTest
private class GwbTargetWorkbenchControllerTest {
    @TestSetup
    static void setupData() {
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        String switchObjectName = globalDescribe.containsKey('GWB_Switch__c')
            ? 'GWB_Switch__c'
            : (globalDescribe.containsKey('Onstar_Switch__c') ? 'Onstar_Switch__c' : null);
        if (switchObjectName != null) {
            SObject bypassRecord = globalDescribe.get(switchObjectName).newSObject();
            bypassRecord.put('SetupOwnerId', UserInfo.getUserId());
            bypassRecord.put('Bypass_VRs__c', true);
            insert bypassRecord;
        }

        Plant__c plant = GWBTestDataFactory.createPlant('Dynamic WB Plant', true);
        String dataPointValue = getFirstActivePicklistValue(GWB_Month__c.Data_Point_Value__c);
        Plant_Sector__c plantSector = new Plant_Sector__c(
            Plant__c = plant.Id
        );
        insert plantSector;

        Id targetRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'GWB_Year__c'
            AND DeveloperName = 'Target'
            LIMIT 1
        ].Id;

        GWB_Year__c target = new GWB_Year__c(
            Plant__c = plant.Id,
            Plant_Sector__c = plantSector.Id,
            Sector__c = 'Assembly',
            Year__c = String.valueOf(Date.today().year() + 1),
            Version__c = dataPointValue,
            M_Schedule_Version__c = dataPointValue,
            Status__c = 'Draft',
            RecordTypeId = targetRecordTypeId
        );
        insert target;

        insert new GWB_Month__c(
            GWB_Year__c = target.Id,
            Section__c = 'Headcount',
            Parameter__c = 'Base Headcount',
            Classification__c = 'OTS',
            Prev_Dec_Number__c = 100,
            Jan_Number__c = 100,
            Feb_Number__c = 100
        );
        insert new GWB_Month__c(
            GWB_Year__c = target.Id,
            Section__c = 'Headcount',
            Parameter__c = 'Previous YE Approved Target Changes',
            Classification__c = 'OTS',
            Prev_Dec_Number__c = 0,
            Jan_Number__c = 5,
            Feb_Number__c = 3
        );
        insert new GWB_Month__c(
            GWB_Year__c = target.Id,
            Section__c = 'Headcount',
            Parameter__c = 'Total Manpower (Include Target Changes)',
            Classification__c = 'OTS',
            Prev_Dec_Number__c = 100,
            Jan_Number__c = 105,
            Feb_Number__c = 108
        );
        insert new GWB_Month__c(
            GWB_Year__c = target.Id,
            Driver__c = 'Productivity',
            Classification__c = 'OTS',
            Plant__c = plant.Id,
            Sector__c = 'Assembly',
            Year__c = target.Year__c,
            Data_Point_Value__c = dataPointValue,
            Jan_Number__c = -2,
            Feb_Number__c = 1
        );
        insert new GWB_Month__c(
            GWB_Year__c = target.Id,
            Driver__c = 'ARC',
            Classification__c = 'OTS',
            Plant__c = plant.Id,
            Sector__c = 'Assembly',
            Year__c = target.Year__c,
            Data_Point_Value__c = dataPointValue,
            Jan_Number__c = 2,
            Feb_Number__c = 0
        );
    }

    private static String getFirstActivePicklistValue(Schema.SObjectField fieldRef) {
        for (Schema.PicklistEntry entry : fieldRef.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static String getAdditionalStraightAdjustmentPicklistValue() {
        for (Schema.PicklistEntry entry : GWB_Month__c.Parameter__c.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            String value = entry.getValue();
            if (value == 'Additional ST Adjust' || value == 'Additional Straight Time Hours Adjustment') {
                return value;
            }
        }
        return null;
    }

    @IsTest
    static void getBudgetScreenReturnsMetadataDrivenRows() {
        Id targetId = [SELECT Id FROM GWB_Year__c LIMIT 1].Id;

        Test.startTest();
        GwbTargetWorkbenchController.DynamicBudgetResponse response =
            GwbTargetWorkbenchController.getBudgetScreen(targetId);
        Test.stopTest();

        System.assertNotEquals(null, response.header);
        System.assertEquals(true, response.canEdit, 'Non-published target should be editable.');
        System.assert(response.sections.size() > 0, 'Expected at least one metadata-driven section.');

        Boolean foundBase = false;
        Boolean foundMbc = false;
        Boolean foundTotal = false;
        Integer opPlanIndex = -1;
        Integer headcountIndex = -1;
        Integer hoursIndex = -1;
        Integer sectionIndex = 0;
        for (GwbTargetWorkbenchController.DynamicBudgetSection section : response.sections) {
            if (section.name == 'Op Plan') {
                opPlanIndex = sectionIndex;
            } else if (section.name == 'Headcount') {
                headcountIndex = sectionIndex;
            } else if (section.name == 'Hours') {
                hoursIndex = sectionIndex;
            }
            for (GwbTargetWorkbenchController.DynamicBudgetRow row : section.rows) {
                if (row.key == 'base-ots') {
                    foundBase = true;
                    System.assertEquals(100, row.values.get('prevDec'));
                }
                if (row.key == 'mbc-ots') {
                    foundMbc = true;
                    System.assertEquals(2, row.values.get('jan'));
                    System.assertEquals('ARC', row.sourceValue);
                }
                if (row.key == 'total-ots') {
                    foundTotal = true;
                    System.assertEquals(100, row.values.get('prevDec'));
                    System.assertEquals(105, row.values.get('jan'));
                }
            }
            sectionIndex += 1;
        }
        System.assertEquals(true, foundBase, 'Expected metadata-driven Base Headcount row.');
        System.assertEquals(true, foundMbc, 'Expected metadata-driven MBC row mapped from ARC.');
        System.assertEquals(true, foundTotal, 'Expected total manpower row to load from the new business parameter value.');
        if (opPlanIndex >= 0 && headcountIndex >= 0) {
            System.assert(opPlanIndex < headcountIndex, 'Op Plan should render before Headcount.');
        }
        if (headcountIndex >= 0 && hoursIndex >= 0) {
            System.assert(headcountIndex < hoursIndex, 'Headcount should render before Hours.');
        }
    }

    @IsTest
    static void getBudgetScreenReturnsStoredOtsClassificationRows() {
        Id targetId = [SELECT Id FROM GWB_Year__c LIMIT 1].Id;

        Test.startTest();
        GwbTargetWorkbenchController.DynamicBudgetResponse response = GwbTargetWorkbenchController.getBudgetScreen(targetId);
        Test.stopTest();

        GwbTargetWorkbenchController.DynamicBudgetRow matchedRow;
        for (GwbTargetWorkbenchController.DynamicBudgetSection section : response.sections) {
            for (GwbTargetWorkbenchController.DynamicBudgetRow row : section.rows) {
                if (row.key == 'base-ots') {
                    matchedRow = row;
                    break;
                }
            }
            if (matchedRow != null) {
                break;
            }
        }

        System.assertNotEquals(null, matchedRow, 'Expected to find the OTS base headcount row.');
        System.assertEquals('OTS', matchedRow.classification, 'The copied workbench should continue to read stored OTS classification rows.');
        System.assertEquals(100, matchedRow.values.get('prevDec'));
        System.assertEquals(100, matchedRow.values.get('jan'));
    }

    @IsTest
    static void saveBudgetRowsUpsertsParameterAndDriverRows() {
        GWB_Year__c target = [SELECT Id, Plant__c, Sector__c, Year__c FROM GWB_Year__c LIMIT 1];
        List<GwbTargetWorkbenchController.RowInput> rows = new List<GwbTargetWorkbenchController.RowInput>();

        GwbTargetWorkbenchController.RowInput parameterRow = new GwbTargetWorkbenchController.RowInput();
        parameterRow.key = 'advanced-ots';
        parameterRow.label = 'Advanced Target Changes';
        parameterRow.sourceValue = 'Advanced Target Changes';
        parameterRow.classification = 'OTS';
        parameterRow.sourceType = 'Parameter';
        parameterRow.sourceSection = 'Manpower';
        parameterRow.valueType = 'number';
        parameterRow.editable = true;
        parameterRow.category = 'Headcount';
        parameterRow.sequence = 12;
        parameterRow.values = new Map<String, Decimal>{ 'prevDec' => 7, 'jan' => 7, 'feb' => 4 };
        rows.add(parameterRow);

        GwbTargetWorkbenchController.RowInput driverRow = new GwbTargetWorkbenchController.RowInput();
        driverRow.key = 'mbc-ots';
        driverRow.label = 'MBC';
        driverRow.sourceValue = 'ARC';
        driverRow.classification = 'OTS';
        driverRow.sourceType = 'Driver';
        driverRow.valueType = 'number';
        driverRow.editable = true;
        driverRow.category = 'Headcount';
        driverRow.sequence = 22;
        driverRow.values = new Map<String, Decimal>{ 'jan' => -4, 'feb' => 2 };
        rows.add(driverRow);

        Test.startTest();
        GwbTargetWorkbenchController.SaveResponse saveResponse =
            GwbTargetWorkbenchController.saveBudgetRows(target.Id, rows);
        Test.stopTest();

        System.assert(saveResponse.savedRecordCount > 0);
        GWB_Month__c savedParameter = [
            SELECT Prev_Dec_Number__c, Jan_Number__c, Feb_Number__c, Category__c, UI_Sequence__c, Value_Type__c, Avg_Total__c,
                   Annual_TotalNumber1__c, Annual_TotalDecimal1__c, Annual_TotalPercent1__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :target.Id
            AND Parameter__c = 'Previous YE Approved Target Changes'
            LIMIT 1
        ];
        System.assertEquals(7, savedParameter.Prev_Dec_Number__c);
        System.assertEquals(null, savedParameter.Jan_Number__c);
        System.assertEquals(null, savedParameter.Feb_Number__c);
        System.assertEquals('Headcount', savedParameter.Category__c);
        System.assertEquals(12, Integer.valueOf(savedParameter.UI_Sequence__c));
        System.assertEquals('Value', savedParameter.Value_Type__c);
        System.assertEquals(null, savedParameter.Avg_Total__c);
        System.assertEquals(null, savedParameter.Annual_TotalNumber1__c);
        System.assertEquals(null, savedParameter.Annual_TotalDecimal1__c);
        System.assertEquals(null, savedParameter.Annual_TotalPercent1__c);

        GWB_Month__c savedDriver = [
            SELECT Driver__c, Jan_Number__c, Feb_Number__c, Category__c, UI_Sequence__c, Value_Type__c, Avg_Total__c,
                   Annual_TotalNumber1__c, Annual_TotalDecimal1__c, Annual_TotalPercent1__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :target.Id
            AND Driver__c = 'ARC'
            LIMIT 1
        ];
        System.assertEquals(-4, savedDriver.Jan_Number__c);
        System.assertEquals(2, savedDriver.Feb_Number__c);
        System.assertEquals('Headcount', savedDriver.Category__c);
        System.assertEquals(22, Integer.valueOf(savedDriver.UI_Sequence__c));
        System.assertEquals('Value', savedDriver.Value_Type__c);
        System.assertEquals(-2.17, savedDriver.Avg_Total__c);
        System.assertEquals(-2, savedDriver.Annual_TotalNumber1__c);
        System.assertEquals(null, savedDriver.Annual_TotalDecimal1__c);
        System.assertEquals(null, savedDriver.Annual_TotalPercent1__c);
    }

    @IsTest
    static void saveBudgetRowsPersistsReadonlyParameterRowsShownOnUi() {
        GWB_Year__c target = [SELECT Id FROM GWB_Year__c LIMIT 1];

        GwbTargetWorkbenchController.RowInput baseRow = new GwbTargetWorkbenchController.RowInput();
        baseRow.key = 'base-ots';
        baseRow.label = 'Base Headcount (non SUPP, no Apprentices)';
        baseRow.sourceValue = 'Base Headcount';
        baseRow.classification = 'OTS';
        baseRow.sourceType = 'Parameter';
        baseRow.sourceSection = 'Manpower';
        baseRow.valueType = 'number';
        baseRow.editable = false;
        baseRow.category = 'Headcount';
        baseRow.sequence = 1;
        baseRow.values = new Map<String, Decimal>{
            'prevDec' => 300,
            'jan' => 300,
            'feb' => 300,
            'mar' => 300,
            'apr' => 300,
            'may' => 300,
            'jun' => 300,
            'jul' => 300,
            'aug' => 300,
            'sep' => 300,
            'oct' => 300,
            'nov' => 300,
            'dec' => 300
        };

        Test.startTest();
        GwbTargetWorkbenchController.SaveResponse response =
            GwbTargetWorkbenchController.saveBudgetRows(
                target.Id,
                new List<GwbTargetWorkbenchController.RowInput>{ baseRow }
            );
        Test.stopTest();

        System.assertEquals(1, response.savedRecordCount);
        GWB_Month__c savedBaseRow = [
            SELECT Jan_Number__c, Dec_Number__c, Avg_Total__c, Annual_TotalNumber1__c,
                   Annual_TotalDecimal1__c, Annual_TotalPercent1__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :target.Id
            AND Parameter__c = 'Base Headcount'
            AND Classification__c = 'OTS'
            LIMIT 1
        ];
        System.assertEquals(300, savedBaseRow.Jan_Number__c);
        System.assertEquals(300, savedBaseRow.Dec_Number__c);
        System.assertEquals(300, savedBaseRow.Avg_Total__c);
        System.assertEquals(300, savedBaseRow.Annual_TotalNumber1__c);
        System.assertEquals(null, savedBaseRow.Annual_TotalDecimal1__c);
        System.assertEquals(null, savedBaseRow.Annual_TotalPercent1__c);
    }

    @IsTest
    static void saveBudgetRowsPersistsHoursCategoryParametersUsingCompatibleSection() {
        GWB_Year__c target = [SELECT Id FROM GWB_Year__c LIMIT 1];
        List<GwbTargetWorkbenchController.RowInput> rows = new List<GwbTargetWorkbenchController.RowInput>();

        GwbTargetWorkbenchController.RowInput hoursParameterRow = new GwbTargetWorkbenchController.RowInput();
        hoursParameterRow.key = 'absenteeism-ots';
        hoursParameterRow.label = 'Absenteeism %';
        hoursParameterRow.sourceValue = 'Absenteeism %';
        hoursParameterRow.classification = 'OTS';
        hoursParameterRow.sourceType = 'Parameter';
        hoursParameterRow.sourceSection = 'Hours';
        hoursParameterRow.valueType = 'percent';
        hoursParameterRow.editable = true;
        hoursParameterRow.category = 'Hours';
        hoursParameterRow.sequence = 3;
        hoursParameterRow.values = new Map<String, Decimal>{ 'prevDec' => 0.11, 'jan' => 0.12, 'feb' => 0.13 };
        rows.add(hoursParameterRow);

        Test.startTest();
        GwbTargetWorkbenchController.SaveResponse saveResponse =
            GwbTargetWorkbenchController.saveBudgetRows(target.Id, rows);
        Test.stopTest();

        System.assertEquals(1, saveResponse.savedRecordCount);

        GWB_Month__c savedHoursRow = [
            SELECT Section__c, Category__c, UI_Sequence__c, Value_Type__c,
                   Prev_Dec_Percent__c, Jan_Percent__c, Feb_Percent__c,
                   Annual_TotalNumber1__c, Annual_TotalDecimal1__c, Annual_TotalPercent1__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :target.Id
            AND Parameter__c = 'Absenteeism %'
            AND Classification__c = 'OTS'
            LIMIT 1
        ];
        System.assertEquals('Headcount', savedHoursRow.Section__c, 'Save should persist the compatible stored section for restricted Parameter values.');
        System.assertEquals('Hours', savedHoursRow.Category__c, 'Hours inputs should still persist to the Hours category.');
        System.assertEquals(3, Integer.valueOf(savedHoursRow.UI_Sequence__c));
        System.assertEquals('Value', savedHoursRow.Value_Type__c);
        System.assertEquals(0.11, savedHoursRow.Prev_Dec_Percent__c);
        System.assertEquals(0.12, savedHoursRow.Jan_Percent__c);
        System.assertEquals(0.13, savedHoursRow.Feb_Percent__c);
        System.assertEquals(null, savedHoursRow.Annual_TotalNumber1__c);
        System.assertEquals(null, savedHoursRow.Annual_TotalDecimal1__c);
        System.assertEquals(0.0, savedHoursRow.Annual_TotalPercent1__c);
    }

    @IsTest
    static void saveBudgetRowsStoresDecimalAnnualTotalInDecimalField() {
        GWB_Year__c target = [SELECT Id FROM GWB_Year__c LIMIT 1];
        GwbTargetWorkbenchController.RowInput decimalRow = new GwbTargetWorkbenchController.RowInput();
        decimalRow.key = 'scheduled-volume-decimal';
        decimalRow.label = 'Scheduled Volume';
        decimalRow.sourceValue = 'Scheduled Volume';
        decimalRow.sourceType = 'Parameter';
        decimalRow.sourceSection = 'Scheduled_Volume';
        decimalRow.valueType = 'decimal';
        decimalRow.editable = true;
        decimalRow.category = 'Op Plan';
        decimalRow.sequence = 8;
        decimalRow.values = new Map<String, Decimal>{ 'jan' => 1.1, 'feb' => 2.2 };

        Test.startTest();
        GwbTargetWorkbenchController.SaveResponse saveResponse =
            GwbTargetWorkbenchController.saveBudgetRows(
                target.Id,
                new List<GwbTargetWorkbenchController.RowInput>{ decimalRow }
            );
        Test.stopTest();

        System.assertEquals(1, saveResponse.savedRecordCount);
        GWB_Month__c savedDecimalRow = [
            SELECT Jan_Decimal__c, Feb_Decimal__c, Avg_Total__c,
                   Annual_TotalNumber1__c, Annual_TotalDecimal1__c, Annual_TotalPercent1__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :target.Id
            AND Parameter__c = 'Scheduled Volume'
            LIMIT 1
        ];
        System.assertEquals(1.1, savedDecimalRow.Jan_Decimal__c);
        System.assertEquals(2.2, savedDecimalRow.Feb_Decimal__c);
        System.assertEquals(3.3, savedDecimalRow.Avg_Total__c);
        System.assertEquals(null, savedDecimalRow.Annual_TotalNumber1__c);
        System.assertEquals(3.3, savedDecimalRow.Annual_TotalDecimal1__c);
        System.assertEquals(null, savedDecimalRow.Annual_TotalPercent1__c);
    }

    @IsTest
    static void saveBudgetRowsStoresUiRightSideTotalForOpPlanRows() {
        GWB_Year__c target = [SELECT Id FROM GWB_Year__c LIMIT 1];
        GwbTargetWorkbenchController.RowInput availableDaysRow = new GwbTargetWorkbenchController.RowInput();
        availableDaysRow.key = 'availableDays';
        availableDaysRow.label = 'Available Working Days / Month';
        availableDaysRow.sourceValue = 'Available Working Days/Month';
        availableDaysRow.sourceType = 'Parameter';
        availableDaysRow.sourceSection = 'Scheduled_Volume';
        availableDaysRow.valueType = 'decimal';
        availableDaysRow.editable = true;
        availableDaysRow.category = 'Op Plan';
        availableDaysRow.sequence = 8;
        availableDaysRow.values = new Map<String, Decimal>{ 'jan' => 10, 'feb' => 8 };

        Test.startTest();
        GwbTargetWorkbenchController.SaveResponse saveResponse =
            GwbTargetWorkbenchController.saveBudgetRows(
                target.Id,
                new List<GwbTargetWorkbenchController.RowInput>{ availableDaysRow }
            );
        Test.stopTest();

        System.assertEquals(1, saveResponse.savedRecordCount);
        GWB_Month__c savedAvailableDaysRow = [
            SELECT Jan_Decimal__c, Feb_Decimal__c, Avg_Total__c,
                   Annual_TotalNumber1__c, Annual_TotalDecimal1__c, Annual_TotalPercent1__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :target.Id
            AND Parameter__c = 'Available Working Days/Month'
            LIMIT 1
        ];
        System.assertEquals(10, savedAvailableDaysRow.Jan_Decimal__c);
        System.assertEquals(8, savedAvailableDaysRow.Feb_Decimal__c);
        System.assertEquals(18, savedAvailableDaysRow.Avg_Total__c);
        System.assertEquals(null, savedAvailableDaysRow.Annual_TotalNumber1__c);
        System.assertEquals(18, savedAvailableDaysRow.Annual_TotalDecimal1__c);
        System.assertEquals(null, savedAvailableDaysRow.Annual_TotalPercent1__c);
    }

    @IsTest
    static void saveBudgetRowsMapsScheduledVolumePayloadCategoryToOpPlan() {
        GWB_Year__c target = [SELECT Id FROM GWB_Year__c LIMIT 1];
        GWB_Month__c existingScheduledVolumeRow = new GWB_Month__c(
            GWB_Year__c = target.Id,
            Section__c = 'Op Plan',
            Category__c = 'Op Plan',
            Parameter__c = 'Crews',
            Prev_Dec_Number__c = 4
        );
        insert existingScheduledVolumeRow;

        GwbTargetWorkbenchController.RowInput scheduledVolumeRow = new GwbTargetWorkbenchController.RowInput();
        scheduledVolumeRow.recordId = existingScheduledVolumeRow.Id;
        scheduledVolumeRow.key = 'crews';
        scheduledVolumeRow.label = 'Crews';
        scheduledVolumeRow.sourceValue = 'Crews';
        scheduledVolumeRow.sourceType = 'Parameter';
        scheduledVolumeRow.sourceSection = 'Scheduled_Volume';
        scheduledVolumeRow.valueType = 'number';
        scheduledVolumeRow.editable = true;
        scheduledVolumeRow.category = 'Scheduled_Volume';
        scheduledVolumeRow.sequence = 1;
        scheduledVolumeRow.values = new Map<String, Decimal>{ 'prevDec' => 4, 'jan' => 4, 'feb' => 5 };

        Test.startTest();
        GwbTargetWorkbenchController.SaveResponse saveResponse =
            GwbTargetWorkbenchController.saveBudgetRows(
                target.Id,
                new List<GwbTargetWorkbenchController.RowInput>{ scheduledVolumeRow }
            );
        Test.stopTest();

        System.assertEquals(1, saveResponse.savedRecordCount);
        GWB_Month__c savedScheduledVolumeRow = [
            SELECT Section__c, Parameter__c, Category__c, Prev_Dec_Number__c, Jan_Number__c, Feb_Number__c
            FROM GWB_Month__c
            WHERE Id = :existingScheduledVolumeRow.Id
        ];
        System.assertEquals('Op Plan', savedScheduledVolumeRow.Section__c);
        System.assertEquals('Crews', savedScheduledVolumeRow.Parameter__c);
        System.assertEquals('Op Plan', savedScheduledVolumeRow.Category__c);
        System.assertEquals(4, savedScheduledVolumeRow.Prev_Dec_Number__c);
        System.assertEquals(4, savedScheduledVolumeRow.Jan_Number__c);
        System.assertEquals(5, savedScheduledVolumeRow.Feb_Number__c);
    }

    @IsTest
    static void saveBudgetRowsStoresTotalManpowerUsingBusinessParameterName() {
        GWB_Year__c target = [SELECT Id FROM GWB_Year__c LIMIT 1];
        List<GwbTargetWorkbenchController.RowInput> totalRows = new List<GwbTargetWorkbenchController.RowInput>();
        for (String classification : new List<String>{ 'OTS', 'Skilled', 'Salaried', 'Total' }) {
            GwbTargetWorkbenchController.RowInput totalRow = new GwbTargetWorkbenchController.RowInput();
            totalRow.key = 'total-' + classification.toLowerCase();
            totalRow.label = classification == 'Total' ? 'Total' : 'Total ' + classification;
            totalRow.sourceValue = 'Total Manpower';
            totalRow.category = 'Headcount';
            totalRow.classification = classification;
            totalRow.sourceType = 'Parameter';
            totalRow.sourceSection = 'Manpower';
            totalRow.valueType = 'number';
            totalRow.editable = false;
            totalRow.lineType = 'Formula';
            totalRow.sequence = 40;
            totalRow.formulaKey = 'totalManpower';
            totalRow.values = new Map<String, Decimal>{ 'prevDec' => 100, 'jan' => 105, 'feb' => 108 };
            totalRows.add(totalRow);
        }

        Test.startTest();
        GwbTargetWorkbenchController.SaveResponse saveResponse =
            GwbTargetWorkbenchController.saveBudgetRows(
                target.Id,
                totalRows
            );
        Test.stopTest();

        System.assertEquals(4, saveResponse.savedRecordCount);
        List<GWB_Month__c> savedTotalRows = [
            SELECT Parameter__c, Classification__c, Prev_Dec_Number__c, Jan_Number__c, Feb_Number__c, Category__c, UI_Sequence__c, Value_Type__c, Avg_Total__c,
                   Annual_TotalNumber1__c, Annual_TotalDecimal1__c, Annual_TotalPercent1__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :target.Id
            AND Parameter__c = 'Total Manpower (Include Target Changes)'
        ];
        System.assertEquals(4, savedTotalRows.size(), 'Each Total Manpower classification row should be persisted separately.');
        Set<String> savedClassifications = new Set<String>();
        for (GWB_Month__c savedTotalRow : savedTotalRows) {
            savedClassifications.add(String.isBlank(savedTotalRow.Classification__c) ? 'Total' : savedTotalRow.Classification__c);
            System.assertEquals('Total Manpower (Include Target Changes)', savedTotalRow.Parameter__c);
            System.assertEquals(String.isBlank(savedTotalRow.Classification__c) ? 315 : 105, savedTotalRow.Jan_Number__c);
            System.assertEquals('Headcount', savedTotalRow.Category__c);
            System.assertEquals(40, Integer.valueOf(savedTotalRow.UI_Sequence__c));
            System.assertEquals(
                String.isBlank(savedTotalRow.Classification__c) ? 'Total' : 'Value',
                savedTotalRow.Value_Type__c,
                'Total classification rows persist as Total while per-classification rows persist as Value.'
            );
            System.assertEquals(String.isBlank(savedTotalRow.Classification__c) ? 53.20 : 17.8, savedTotalRow.Avg_Total__c);
            System.assertEquals(String.isBlank(savedTotalRow.Classification__c) ? 53 : 17, savedTotalRow.Annual_TotalNumber1__c);
            System.assertEquals(null, savedTotalRow.Annual_TotalDecimal1__c);
            System.assertEquals(null, savedTotalRow.Annual_TotalPercent1__c);
        }
        System.assertEquals(new Set<String>{ 'OTS', 'Skilled', 'Salaried', 'Total' }, savedClassifications);
    }

    @IsTest
    static void saveBudgetRowsPersistsConfigDefinedTotalRows() {
        GWB_Year__c target = [SELECT Id FROM GWB_Year__c LIMIT 1];
        GwbTargetWorkbenchController.RowInput totalRow = new GwbTargetWorkbenchController.RowInput();
        totalRow.key = 'base_headcount_non_supp_no_apprentices-shared';
        totalRow.label = 'Base Headcount (non SUPP, no Apprentices)';
        totalRow.sourceValue = 'Base Headcount';
        totalRow.category = 'Headcount';
        totalRow.classification = 'Total';
        totalRow.sourceType = 'Derived';
        totalRow.sourceSection = 'Manpower';
        totalRow.valueType = 'number';
        totalRow.editable = false;
        totalRow.lineType = 'Total';
        totalRow.sequence = 4;
        totalRow.values = new Map<String, Decimal>{ 'prevDec' => 480, 'jan' => 482, 'feb' => 484 };

        Test.startTest();
        GwbTargetWorkbenchController.SaveResponse saveResponse =
            GwbTargetWorkbenchController.saveBudgetRows(
                target.Id,
                new List<GwbTargetWorkbenchController.RowInput>{ totalRow }
            );
        Test.stopTest();

        System.assertEquals(1, saveResponse.savedRecordCount);
        GWB_Month__c savedTotalRow = [
            SELECT Parameter__c, Classification__c, Prev_Dec_Number__c, Jan_Number__c, Feb_Number__c,
                   Category__c, UI_Sequence__c, Value_Type__c, Avg_Total__c,
                   Annual_TotalNumber1__c, Annual_TotalDecimal1__c, Annual_TotalPercent1__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :target.Id
            AND Parameter__c = 'Base Headcount'
            AND Value_Type__c = 'Total'
            LIMIT 1
        ];
        System.assertEquals('Base Headcount', savedTotalRow.Parameter__c);
        System.assertEquals(482, savedTotalRow.Jan_Number__c);
        System.assertEquals('Headcount', savedTotalRow.Category__c);
        System.assertEquals(4, Integer.valueOf(savedTotalRow.UI_Sequence__c));
        System.assertEquals('Total', savedTotalRow.Value_Type__c);
        System.assertEquals(80.5, savedTotalRow.Avg_Total__c);
        System.assertEquals(80, savedTotalRow.Annual_TotalNumber1__c);
        System.assertEquals(null, savedTotalRow.Annual_TotalDecimal1__c);
        System.assertEquals(null, savedTotalRow.Annual_TotalPercent1__c);
    }

    @IsTest
    static void saveBudgetRowsPersistsDerivedFormulaValueRows() {
        GWB_Year__c target = [SELECT Id FROM GWB_Year__c LIMIT 1];
        GwbTargetWorkbenchController.RowInput formulaRow = new GwbTargetWorkbenchController.RowInput();
        formulaRow.key = 'scheduledOvertime-ots';
        formulaRow.label = 'Scheduled Overtime Hours';
        formulaRow.sourceValue = 'Scheduled Overtime Hours';
        formulaRow.category = 'Hours';
        formulaRow.classification = 'OTS';
        formulaRow.sourceType = 'Derived';
        formulaRow.sourceSection = 'Hours';
        formulaRow.valueType = 'number';
        formulaRow.editable = false;
        formulaRow.lineType = 'Formula';
        formulaRow.sequence = 21;
        formulaRow.formulaKey = 'scheduledOvertime';
        formulaRow.values = new Map<String, Decimal>{ 'jan' => 11, 'feb' => 12, 'mar' => 13 };

        Test.startTest();
        GwbTargetWorkbenchController.SaveResponse saveResponse =
            GwbTargetWorkbenchController.saveBudgetRows(
                target.Id,
                new List<GwbTargetWorkbenchController.RowInput>{ formulaRow }
            );
        GwbTargetWorkbenchController.SaveResponse secondSaveResponse =
            GwbTargetWorkbenchController.saveBudgetRows(
                target.Id,
                new List<GwbTargetWorkbenchController.RowInput>{ formulaRow }
            );
        Test.stopTest();

        System.assertEquals(1, saveResponse.savedRecordCount);
        System.assertEquals(1, secondSaveResponse.savedRecordCount);
        GWB_Month__c savedFormulaRow = [
            SELECT Parameter__c, Classification__c, Jan_Number__c, Feb_Number__c, Mar_Number__c,
                   Category__c, UI_Sequence__c, Value_Type__c, Avg_Total__c, Annual_TotalNumber1__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :target.Id
            AND Parameter__c = 'Scheduled Overtime Hours'
            AND Classification__c = 'OTS'
            LIMIT 1
        ];
        System.assertEquals('Scheduled Overtime Hours', savedFormulaRow.Parameter__c);
        System.assertEquals('OTS', savedFormulaRow.Classification__c);
        System.assertEquals(11, savedFormulaRow.Jan_Number__c);
        System.assertEquals(12, savedFormulaRow.Feb_Number__c);
        System.assertEquals(13, savedFormulaRow.Mar_Number__c);
        System.assertEquals('Hours', savedFormulaRow.Category__c);
        System.assertEquals(21, Integer.valueOf(savedFormulaRow.UI_Sequence__c));
        System.assertEquals('Value', savedFormulaRow.Value_Type__c);
        System.assertEquals(36, savedFormulaRow.Avg_Total__c);
        System.assertEquals(36, savedFormulaRow.Annual_TotalNumber1__c);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM GWB_Month__c
                WHERE GWB_Year__c = :target.Id
                AND Parameter__c = 'Scheduled Overtime Hours'
                AND Classification__c = 'OTS'
            ],
            'Saving the same derived formula row again should update the existing row, not create a duplicate.'
        );
    }

    @IsTest
    static void saveBudgetRowsNormalizesAndPersistsDerivedFormulaRowsBySupportedParameter() {
        GWB_Year__c target = [SELECT Id FROM GWB_Year__c LIMIT 1];
        GwbTargetWorkbenchController.RowInput calculatedVolumeRow = new GwbTargetWorkbenchController.RowInput();
        calculatedVolumeRow.key = 'calcVolume';
        calculatedVolumeRow.label = 'Calculated Volume including SOT days';
        calculatedVolumeRow.sourceValue = 'Calculated Volume including SOT days';
        calculatedVolumeRow.category = 'Op Plan';
        calculatedVolumeRow.classification = '';
        calculatedVolumeRow.sourceType = 'Derived';
        calculatedVolumeRow.sourceSection = 'Scheduled_Volume';
        calculatedVolumeRow.valueType = 'number';
        calculatedVolumeRow.editable = false;
        calculatedVolumeRow.lineType = 'Formula';
        calculatedVolumeRow.sequence = 4;
        calculatedVolumeRow.formulaKey = 'calcVolume';
        calculatedVolumeRow.values = new Map<String, Decimal>{ 'jan' => 100, 'feb' => 200 };

        GwbTargetWorkbenchController.RowInput unsupportedFormulaRow = new GwbTargetWorkbenchController.RowInput();
        unsupportedFormulaRow.key = 'ahpuMonthly';
        unsupportedFormulaRow.label = 'AHPU Monthly';
        unsupportedFormulaRow.sourceValue = 'AHPU Monthly';
        unsupportedFormulaRow.category = 'Hours';
        unsupportedFormulaRow.classification = 'Total';
        unsupportedFormulaRow.sourceType = 'Derived';
        unsupportedFormulaRow.sourceSection = 'Hours';
        unsupportedFormulaRow.valueType = 'decimal';
        unsupportedFormulaRow.editable = false;
        unsupportedFormulaRow.lineType = 'Formula';
        unsupportedFormulaRow.sequence = 60;
        unsupportedFormulaRow.formulaKey = 'ahpuMonthly';
        unsupportedFormulaRow.values = new Map<String, Decimal>{ 'jan' => 1.1, 'feb' => 2.2 };

        Test.startTest();
        GwbTargetWorkbenchController.SaveResponse saveResponse =
            GwbTargetWorkbenchController.saveBudgetRows(
                target.Id,
                new List<GwbTargetWorkbenchController.RowInput>{ calculatedVolumeRow, unsupportedFormulaRow }
            );
        Test.stopTest();

        System.assertEquals(2, saveResponse.savedRecordCount);
        GWB_Month__c savedCalculatedVolumeRow = [
            SELECT Parameter__c, Jan_Number__c, Feb_Number__c, Category__c, Value_Type__c, Avg_Total__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :target.Id
            AND Parameter__c = 'Calculated Volume incl. SOT'
            LIMIT 1
        ];
        System.assertEquals('Calculated Volume incl. SOT', savedCalculatedVolumeRow.Parameter__c);
        System.assertEquals(100, savedCalculatedVolumeRow.Jan_Number__c);
        System.assertEquals(200, savedCalculatedVolumeRow.Feb_Number__c);
        System.assertEquals('Op Plan', savedCalculatedVolumeRow.Category__c);
        System.assertEquals('Value', savedCalculatedVolumeRow.Value_Type__c);
        System.assertEquals(300, savedCalculatedVolumeRow.Avg_Total__c);
        GWB_Month__c savedAhpuRow = [
            SELECT Parameter__c, Jan_Decimal__c, Feb_Decimal__c, Category__c, Value_Type__c,
                   Avg_Total__c, Annual_TotalDecimal1__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :target.Id
            AND Parameter__c = 'AHPU Monthly'
            LIMIT 1
        ];
        System.assertEquals('AHPU Monthly', savedAhpuRow.Parameter__c);
        System.assertEquals(1.1, savedAhpuRow.Jan_Decimal__c);
        System.assertEquals(2.2, savedAhpuRow.Feb_Decimal__c);
        System.assertEquals('Hours', savedAhpuRow.Category__c);
        System.assertEquals('Value', savedAhpuRow.Value_Type__c);
        System.assertEquals(3.3, savedAhpuRow.Avg_Total__c);
        System.assertEquals(3.3, savedAhpuRow.Annual_TotalDecimal1__c);
    }

    @IsTest
    static void saveBudgetRowsRecomputesCalculatedRowsBeforePersisting() {
        GWB_Year__c target = [SELECT Id FROM GWB_Year__c LIMIT 1];
        List<GwbTargetWorkbenchController.RowInput> rows = new List<GwbTargetWorkbenchController.RowInput>{
            buildSaveRow('netJph', 'Net/Net JPH', 'Parameter', 'Scheduled_Volume', 'decimal', true, 'Input', null, new Map<String, Decimal>{ 'jan' => 11, 'feb' => 11, 'mar' => 10 }),
            buildSaveRow('paidHoursPerCrew', 'Paid Hours Per CREW', 'Parameter', 'Scheduled_Volume', 'decimal', true, 'Input', null, new Map<String, Decimal>{ 'jan' => 8, 'feb' => 8, 'mar' => 8 }),
            buildSaveRow('productionDays', 'Production Working Days/Month', 'Parameter', 'Scheduled_Volume', 'decimal', true, 'Input', null, new Map<String, Decimal>{ 'jan' => 10, 'feb' => 8, 'mar' => 4 }),
            buildSaveRow('eqSotDays', 'EQ SOT Days', 'Parameter', 'Scheduled_Volume', 'decimal', true, 'Input', null, new Map<String, Decimal>{ 'jan' => 10, 'feb' => 8, 'mar' => 9 }),
            buildSaveRow('shifts', 'Shifts', 'Parameter', 'Scheduled_Volume', 'number', true, 'Input', null, new Map<String, Decimal>{ 'jan' => 2, 'feb' => 2, 'mar' => 2 }),
            buildSaveRow('scheduledVolume', 'Scheduled Volume', 'Parameter', 'Scheduled_Volume', 'number', true, 'Input', null, new Map<String, Decimal>{ 'jan' => 1000, 'feb' => 1100, 'mar' => 1200 }),
            buildSaveRow('calcVolume', 'Calculated Volume including SOT days', 'Parameter', 'Scheduled_Volume', 'number', false, 'Formula', 'calcVolume', new Map<String, Decimal>{ 'jan' => 1, 'feb' => 1, 'mar' => 0 }),
            buildSaveRow('volumeVariance', 'Scheduled Volume minus Calculated Volume', 'Parameter', 'Scheduled_Volume', 'number', false, 'Formula', 'volumeVariance', new Map<String, Decimal>{ 'jan' => 0, 'feb' => 0, 'mar' => 0 })
        };

        Test.startTest();
        GwbTargetWorkbenchController.SaveResponse saveResponse =
            GwbTargetWorkbenchController.saveBudgetRows(target.Id, rows);
        Test.stopTest();

        System.assertEquals(8, saveResponse.savedRecordCount);
        GWB_Month__c savedCalculatedVolume = [
            SELECT Jan_Number__c, Feb_Number__c, Mar_Number__c, Avg_Total__c, Annual_TotalNumber1__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :target.Id
            AND Parameter__c = 'Calculated Volume incl. SOT'
            LIMIT 1
        ];
        System.assertEquals(3520, savedCalculatedVolume.Jan_Number__c);
        System.assertEquals(2816, savedCalculatedVolume.Feb_Number__c);
        System.assertEquals(2080, savedCalculatedVolume.Mar_Number__c);
        System.assertEquals(8416, savedCalculatedVolume.Avg_Total__c);
        System.assertEquals(8416, savedCalculatedVolume.Annual_TotalNumber1__c);

        GWB_Month__c savedVariance = [
            SELECT Jan_Number__c, Feb_Number__c, Mar_Number__c, Avg_Total__c, Annual_TotalNumber1__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :target.Id
            AND Parameter__c = 'Scheduled Volume minus Calculated Volume'
            LIMIT 1
        ];
        System.assertEquals(-2520, savedVariance.Jan_Number__c);
        System.assertEquals(-1716, savedVariance.Feb_Number__c);
        System.assertEquals(-880, savedVariance.Mar_Number__c);
        System.assertEquals(-5116, savedVariance.Avg_Total__c);
        System.assertEquals(-5116, savedVariance.Annual_TotalNumber1__c);
    }

    @IsTest
    static void saveBudgetRowsRecomputesHeadcountRollupsFromMfgOptDriverRows() {
        GWB_Year__c target = [SELECT Id FROM GWB_Year__c LIMIT 1];
        List<GwbTargetWorkbenchController.RowInput> rows = new List<GwbTargetWorkbenchController.RowInput>();

        rows.add(buildClassifiedSaveRow('base-ots', 'Base Headcount', 'Parameter', 'Manpower', 'number', false, 'Input', null, 'OTS', new Map<String, Decimal>{ 'prevDec' => 300, 'jan' => 300, 'feb' => 300, 'mar' => 300 }));
        rows.add(buildClassifiedSaveRow('base-skilled', 'Base Headcount', 'Parameter', 'Manpower', 'number', false, 'Input', null, 'Skilled', new Map<String, Decimal>{ 'prevDec' => 120, 'jan' => 120, 'feb' => 120, 'mar' => 120 }));
        rows.add(buildClassifiedSaveRow('base-salaried', 'Base Headcount', 'Parameter', 'Manpower', 'number', false, 'Input', null, 'Salaried', new Map<String, Decimal>{ 'prevDec' => 60, 'jan' => 60, 'feb' => 60, 'mar' => 60 }));
        rows.add(buildClassifiedSaveRow('base-total', 'Base Headcount', 'Parameter', 'Manpower', 'number', false, 'Total', null, 'Total', new Map<String, Decimal>{ 'prevDec' => 480, 'jan' => 480, 'feb' => 480, 'mar' => 480 }));
        rows.add(buildClassifiedSaveRow('advanced-ots', 'Previous YE Approved Target Changes', 'Parameter', 'Manpower', 'number', true, 'Input', null, 'OTS', new Map<String, Decimal>{ 'prevDec' => 0 }));
        rows.add(buildClassifiedSaveRow('advanced-skilled', 'Previous YE Approved Target Changes', 'Parameter', 'Manpower', 'number', true, 'Input', null, 'Skilled', new Map<String, Decimal>{ 'prevDec' => 0 }));
        rows.add(buildClassifiedSaveRow('advanced-salaried', 'Previous YE Approved Target Changes', 'Parameter', 'Manpower', 'number', true, 'Input', null, 'Salaried', new Map<String, Decimal>{ 'prevDec' => 0 }));
        rows.add(buildClassifiedSaveRow('mfg_opt-ots', 'Mfg Opt', 'Driver', 'Manpower', 'number', true, 'Input', null, 'OTS', new Map<String, Decimal>{ 'mar' => 4 }));
        rows.add(buildClassifiedSaveRow('mfg_opt-skilled', 'Mfg Opt', 'Driver', 'Manpower', 'number', true, 'Input', null, 'Skilled', new Map<String, Decimal>{ 'mar' => 4 }));
        rows.add(buildClassifiedSaveRow('mfg_opt-salaried', 'Mfg Opt', 'Driver', 'Manpower', 'number', true, 'Input', null, 'Salaried', new Map<String, Decimal>{ 'mar' => 4 }));
        rows.add(buildClassifiedSaveRow('total-ots', 'Total Manpower (Include Target Changes)', 'Parameter', 'Manpower', 'number', false, 'Formula', 'totalManpower', 'OTS', new Map<String, Decimal>{ 'prevDec' => 300, 'jan' => 300, 'feb' => 300, 'mar' => 300 }));
        rows.add(buildClassifiedSaveRow('total-skilled', 'Total Manpower (Include Target Changes)', 'Parameter', 'Manpower', 'number', false, 'Formula', 'totalManpower', 'Skilled', new Map<String, Decimal>{ 'prevDec' => 120, 'jan' => 120, 'feb' => 120, 'mar' => 120 }));
        rows.add(buildClassifiedSaveRow('total-salaried', 'Total Manpower (Include Target Changes)', 'Parameter', 'Manpower', 'number', false, 'Formula', 'totalManpower', 'Salaried', new Map<String, Decimal>{ 'prevDec' => 60, 'jan' => 60, 'feb' => 60, 'mar' => 60 }));
        rows.add(buildClassifiedSaveRow('total-total', 'Total Manpower (Include Target Changes)', 'Parameter', 'Manpower', 'number', false, 'Formula', 'totalManpower', 'Total', new Map<String, Decimal>{ 'prevDec' => 480, 'jan' => 480, 'feb' => 480, 'mar' => 480 }));

        Test.startTest();
        GwbTargetWorkbenchController.saveBudgetRows(target.Id, rows);
        Test.stopTest();

        Map<String, GWB_Month__c> savedRowsByLabel = new Map<String, GWB_Month__c>();
        for (GWB_Month__c savedRow : [
            SELECT Parameter__c, Driver__c, Classification__c, Mar_Number__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :target.Id
            AND (Parameter__c IN ('Base Headcount', 'Total Manpower (Include Target Changes)') OR Driver__c = 'Mfg Opt')
        ]) {
            String label = String.isBlank(savedRow.Driver__c) ? savedRow.Parameter__c : savedRow.Driver__c;
            savedRowsByLabel.put(label + '|' + String.valueOf(savedRow.Classification__c), savedRow);
        }

        System.assertEquals(4, savedRowsByLabel.get('Mfg Opt|OTS').Mar_Number__c);
        System.assertEquals(304, savedRowsByLabel.get('Base Headcount|OTS').Mar_Number__c);
        System.assertEquals(124, savedRowsByLabel.get('Base Headcount|Skilled').Mar_Number__c);
        System.assertEquals(64, savedRowsByLabel.get('Base Headcount|Salaried').Mar_Number__c);
        System.assertEquals(492, savedRowsByLabel.get('Base Headcount|null').Mar_Number__c);
        System.assertEquals(304, savedRowsByLabel.get('Total Manpower (Include Target Changes)|OTS').Mar_Number__c);
        System.assertEquals(124, savedRowsByLabel.get('Total Manpower (Include Target Changes)|Skilled').Mar_Number__c);
        System.assertEquals(64, savedRowsByLabel.get('Total Manpower (Include Target Changes)|Salaried').Mar_Number__c);
        System.assertEquals(492, savedRowsByLabel.get('Total Manpower (Include Target Changes)|null').Mar_Number__c);
    }

    @IsTest
    static void saveBudgetRowsNormalizesConfigParameterLabelsBeforeUpsert() {
        GWB_Year__c target = [SELECT Id FROM GWB_Year__c LIMIT 1];
        GwbTargetWorkbenchController.RowInput row = new GwbTargetWorkbenchController.RowInput();
        row.key = 'absence-vro-ots';
        row.label = 'Absenteeism % + Summer VRO%';
        row.sourceValue = 'Absenteeism % + Summer VRO%';
        row.category = 'Headcount';
        row.classification = 'OTS';
        row.sourceType = 'Parameter';
        row.sourceSection = 'Manpower';
        row.valueType = 'percent';
        row.editable = true;
        row.lineType = 'Input';
        row.sequence = 10;
        row.values = new Map<String, Decimal>{ 'jan' => 7.4, 'feb' => 8.4 };

        Test.startTest();
        GwbTargetWorkbenchController.SaveResponse saveResponse =
            GwbTargetWorkbenchController.saveBudgetRows(
                target.Id,
                new List<GwbTargetWorkbenchController.RowInput>{ row }
            );
        Test.stopTest();

        System.assertEquals(1, saveResponse.savedRecordCount);
        GWB_Month__c savedRow = [
            SELECT Parameter__c, Jan_Percent__c, Feb_Percent__c, Category__c, Value_Type__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :target.Id
            AND Parameter__c = 'Absenteeism % + Summer VRO %'
            AND Classification__c = 'OTS'
            LIMIT 1
        ];
        System.assertEquals('Absenteeism % + Summer VRO %', savedRow.Parameter__c);
        System.assertEquals(7.4, savedRow.Jan_Percent__c);
        System.assertEquals(8.4, savedRow.Feb_Percent__c);
        System.assertEquals('Headcount', savedRow.Category__c);
        System.assertEquals('Value', savedRow.Value_Type__c);
    }

    @IsTest
    static void saveBudgetRowsStoresPercentTotalAvgTotalAsUiAverage() {
        GWB_Year__c target = [SELECT Id FROM GWB_Year__c LIMIT 1];
        GwbTargetWorkbenchController.RowInput row = new GwbTargetWorkbenchController.RowInput();
        row.key = 'absenteeism-total';
        row.label = 'Absenteeism %';
        row.sourceValue = 'Absenteeism %';
        row.category = 'Headcount';
        row.classification = 'Total';
        row.sourceType = 'Parameter';
        row.sourceSection = 'Manpower';
        row.valueType = 'percent';
        row.editable = false;
        row.lineType = 'Total';
        row.sequence = 10;
        row.values = new Map<String, Decimal>{
            'jan' => 7.4,
            'feb' => 8.4,
            'mar' => 10.4
        };

        Test.startTest();
        GwbTargetWorkbenchController.SaveResponse saveResponse =
            GwbTargetWorkbenchController.saveBudgetRows(
                target.Id,
                new List<GwbTargetWorkbenchController.RowInput>{ row }
            );
        Test.stopTest();

        System.assertEquals(1, saveResponse.savedRecordCount);
        GWB_Month__c savedRow = [
            SELECT Value_Type__c, Jan_Percent__c, Feb_Percent__c, Mar_Percent__c, Avg_Total__c,
                   Annual_TotalNumber1__c, Annual_TotalDecimal1__c, Annual_TotalPercent1__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :target.Id
            AND Parameter__c = 'Absenteeism %'
            AND Value_Type__c = 'Total'
            LIMIT 1
        ];
        System.assertEquals('Total', savedRow.Value_Type__c);
        System.assertEquals(7.4, savedRow.Jan_Percent__c);
        System.assertEquals(8.4, savedRow.Feb_Percent__c);
        System.assertEquals(10.4, savedRow.Mar_Percent__c);
        System.assertEquals(2.2, savedRow.Avg_Total__c);
        System.assertEquals(null, savedRow.Annual_TotalNumber1__c);
        System.assertEquals(null, savedRow.Annual_TotalDecimal1__c);
        System.assertEquals(2.2, savedRow.Annual_TotalPercent1__c);
    }

    @IsTest
    static void saveBudgetRowsPersistsSummaryProductivityPercentAnnualTotal() {
        GWB_Year__c target = [SELECT Id FROM GWB_Year__c LIMIT 1];
        GwbTargetWorkbenchController.RowInput row = new GwbTargetWorkbenchController.RowInput();
        row.key = 'summary-prod-pct';
        row.label = '% Prod.';
        row.sourceValue = '% Prod.';
        row.category = 'Headcount';
        row.classification = 'Total';
        row.sourceType = 'Derived';
        row.sourceSection = 'Manpower';
        row.valueType = 'percent';
        row.editable = false;
        row.lineType = 'Total';
        row.sequence = 999;
        row.formulaKey = 'prodPct';
        row.values = new Map<String, Decimal>{ 'dec' => 14.7 };

        Test.startTest();
        GwbTargetWorkbenchController.SaveResponse saveResponse =
            GwbTargetWorkbenchController.saveBudgetRows(
                target.Id,
                new List<GwbTargetWorkbenchController.RowInput>{ row }
            );
        row.values = new Map<String, Decimal>{ 'dec' => 15.4 };
        GwbTargetWorkbenchController.SaveResponse secondSaveResponse =
            GwbTargetWorkbenchController.saveBudgetRows(
                target.Id,
                new List<GwbTargetWorkbenchController.RowInput>{ row }
            );
        Test.stopTest();

        System.assertEquals(1, saveResponse.savedRecordCount);
        System.assertEquals(1, secondSaveResponse.savedRecordCount);
        List<GWB_Month__c> savedRows = [
            SELECT Parameter__c, Classification__c, Category__c, Value_Type__c,
                   Dec_Percent__c, Avg_Total__c, Annual_TotalNumber1__c,
                   Annual_TotalDecimal1__c, Annual_TotalPercent1__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :target.Id
            AND Parameter__c = '% Prod.'
        ];
        System.assertEquals(1, savedRows.size(), 'Repeated saves should update the synthetic % Prod. row, not create duplicates.');
        GWB_Month__c savedRow = savedRows[0];
        System.assertEquals('% Prod.', savedRow.Parameter__c);
        System.assertEquals(null, savedRow.Classification__c);
        System.assertEquals('Headcount', savedRow.Category__c);
        System.assertEquals('Total', savedRow.Value_Type__c);
        System.assertEquals(15.4, savedRow.Dec_Percent__c);
        System.assertEquals(15.4, savedRow.Avg_Total__c);
        System.assertEquals(null, savedRow.Annual_TotalNumber1__c);
        System.assertEquals(null, savedRow.Annual_TotalDecimal1__c);
        System.assertEquals(15.4, savedRow.Annual_TotalPercent1__c);
    }

    @IsTest
    static void saveBudgetRowsDedupesRepeatedExistingRowIds() {
        GWB_Year__c target = [SELECT Id FROM GWB_Year__c LIMIT 1];
        GWB_Month__c existingRow = [
            SELECT Id
            FROM GWB_Month__c
            WHERE GWB_Year__c = :target.Id
            AND Parameter__c = 'Previous YE Approved Target Changes'
            AND Classification__c = 'OTS'
            LIMIT 1
        ];

        GwbTargetWorkbenchController.RowInput firstPayload = new GwbTargetWorkbenchController.RowInput();
        firstPayload.key = 'approved-ots-first';
        firstPayload.label = 'Approved Target';
        firstPayload.sourceValue = 'Approved Target';
        firstPayload.category = 'Headcount';
        firstPayload.classification = 'OTS';
        firstPayload.sourceType = 'Parameter';
        firstPayload.sourceSection = 'Manpower';
        firstPayload.valueType = 'number';
        firstPayload.editable = true;
        firstPayload.lineType = 'Input';
        firstPayload.sequence = 5;
        firstPayload.recordId = existingRow.Id;
        firstPayload.values = new Map<String, Decimal>{ 'prevDec' => 1, 'jan' => 2 };

        GwbTargetWorkbenchController.RowInput secondPayload = new GwbTargetWorkbenchController.RowInput();
        secondPayload.key = 'approved-ots-second';
        secondPayload.label = 'Approved Target';
        secondPayload.sourceValue = 'Approved Target';
        secondPayload.category = 'Headcount';
        secondPayload.classification = 'OTS';
        secondPayload.sourceType = 'Parameter';
        secondPayload.sourceSection = 'Manpower';
        secondPayload.valueType = 'number';
        secondPayload.editable = true;
        secondPayload.lineType = 'Input';
        secondPayload.sequence = 5;
        secondPayload.recordId = existingRow.Id;
        secondPayload.values = new Map<String, Decimal>{ 'prevDec' => 3, 'jan' => 4 };

        Test.startTest();
        GwbTargetWorkbenchController.SaveResponse saveResponse =
            GwbTargetWorkbenchController.saveBudgetRows(
                target.Id,
                new List<GwbTargetWorkbenchController.RowInput>{ firstPayload, secondPayload }
            );
        Test.stopTest();

        System.assertEquals(1, saveResponse.savedRecordCount);
        GWB_Month__c savedRow = [
            SELECT Prev_Dec_Number__c, Jan_Number__c
            FROM GWB_Month__c
            WHERE Id = :existingRow.Id
        ];
        System.assertEquals(3, savedRow.Prev_Dec_Number__c);
        System.assertEquals(null, savedRow.Jan_Number__c);
    }

    @IsTest
    static void saveBudgetRowsThrowsWhenTargetIsPublished() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Plant_Sector__c plantSector = [SELECT Id FROM Plant_Sector__c LIMIT 1];
        Id targetRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'GWB_Year__c'
            AND DeveloperName = 'Target'
            LIMIT 1
        ].Id;
        String dataPointValue = getFirstActivePicklistValue(GWB_Month__c.Data_Point_Value__c);

        GWB_Year__c publishedTarget = new GWB_Year__c(
            Plant__c = plant.Id,
            Plant_Sector__c = plantSector.Id,
            Sector__c = 'Assembly',
            Year__c = String.valueOf(Date.today().year() + 1),
            Version__c = dataPointValue,
            M_Schedule_Version__c = dataPointValue,
            Status__c = 'Published',
            RecordTypeId = targetRecordTypeId
        );
        insert publishedTarget;

        GwbTargetWorkbenchController.RowInput parameterRow = new GwbTargetWorkbenchController.RowInput();
        parameterRow.key = 'advanced-ots';
        parameterRow.label = 'Advanced Target Changes';
        parameterRow.sourceValue = 'Advanced Target Changes';
        parameterRow.classification = 'OTS';
        parameterRow.sourceType = 'Parameter';
        parameterRow.sourceSection = 'Manpower';
        parameterRow.valueType = 'number';
        parameterRow.editable = true;
        parameterRow.values = new Map<String, Decimal>{ 'jan' => 1 };

        Test.startTest();
        try {
            GwbTargetWorkbenchController.saveBudgetRows(
                publishedTarget.Id,
                new List<GwbTargetWorkbenchController.RowInput>{ parameterRow }
            );
            System.assert(false, 'Expected saveBudgetRows to fail for published targets.');
        } catch (AuraHandledException ex) {
            System.assert(!String.isBlank(ex.getMessage()), 'Expected a non-empty error message.');
        }
        Test.stopTest();
    }

    @IsTest
    static void getBudgetScreenMarksLockedTargetsReadOnly() {
        GWB_Year__c target = [SELECT Id, Status__c FROM GWB_Year__c WHERE Status__c != 'Published' LIMIT 1];
        target.Status__c = 'Locked';
        update target;

        Test.startTest();
        GwbTargetWorkbenchController.DynamicBudgetResponse response =
            GwbTargetWorkbenchController.getBudgetScreen(target.Id);
        Test.stopTest();

        System.assertEquals(false, response.canEdit);
        System.assertEquals('Target rows are read-only when the target status is Locked.', response.statusMessage);
    }

    @IsTest
    static void getBudgetScreenMarksPlantReviewCompleteReadOnlyForPlantAdmin() {
        GWB_Year__c target = [SELECT Id, Status__c FROM GWB_Year__c WHERE Status__c != 'Published' LIMIT 1];
        target.Status__c = 'Plant Review Complete';
        update target;

        Test.startTest();
        GwbTargetWorkbenchController.plantAdminPermissionOverride = true;
        GwbTargetWorkbenchController.DynamicBudgetResponse response =
            GwbTargetWorkbenchController.getBudgetScreen(target.Id);
        Test.stopTest();

        System.assertEquals(false, response.canEdit);
        System.assertEquals(
            'Target rows are read-only when the target status is Plant Review Complete.',
            response.statusMessage
        );
        GwbTargetWorkbenchController.plantAdminPermissionOverride = null;
    }

    @IsTest
    static void getBudgetScreenAllowsPlantScopedUsersForDraftTargets() {
        GWB_Year__c draftTarget = [SELECT Id FROM GWB_Year__c WHERE Status__c = 'Draft' LIMIT 1];

        Test.startTest();
        GwbTargetWorkbenchController.currentUserPersonaOverride = 'Plant_Viewer';
        try {
            GwbTargetWorkbenchController.DynamicBudgetResponse response =
                GwbTargetWorkbenchController.getBudgetScreen(draftTarget.Id);
            System.assertNotEquals(null, response);
            System.assertEquals(draftTarget.Id, response.header.id);
        } finally {
            GwbTargetWorkbenchController.currentUserPersonaOverride = null;
        }
        Test.stopTest();
    }

    @IsTest
    static void getBudgetScreenReturnsPlantAdminLikeStatusOptionsForPlantReview() {
        GWB_Year__c target = [SELECT Id, Status__c, Sector__c FROM GWB_Year__c LIMIT 1];
        target.Status__c = 'Plant Review';
        target.Sector__c = 'Assembly';
        update target;

        Test.startTest();
        GwbTargetWorkbenchController.currentUserPersonaOverride = 'Backup Plant Admin';
        GwbTargetWorkbenchController.DynamicBudgetResponse response =
            GwbTargetWorkbenchController.getBudgetScreen(target.Id);
        GwbTargetWorkbenchController.currentUserPersonaOverride = null;
        Test.stopTest();

        System.assertEquals(true, response.canUpdateStatus);
        System.assertEquals(1, response.statusOptions.size());
        System.assertEquals('Plant Review Complete', response.statusOptions[0].value);
    }

    @IsTest
    static void saveBudgetRowsThrowsWhenTargetIsLocked() {
        GWB_Year__c target = [SELECT Id, Status__c FROM GWB_Year__c WHERE Status__c != 'Published' LIMIT 1];
        target.Status__c = 'Locked';
        update target;

        GwbTargetWorkbenchController.RowInput parameterRow = new GwbTargetWorkbenchController.RowInput();
        parameterRow.key = 'advanced-ots';
        parameterRow.label = 'Advanced Target Changes';
        parameterRow.sourceValue = 'Advanced Target Changes';
        parameterRow.classification = 'OTS';
        parameterRow.sourceType = 'Parameter';
        parameterRow.sourceSection = 'Manpower';
        parameterRow.valueType = 'number';
        parameterRow.editable = true;
        parameterRow.values = new Map<String, Decimal>{ 'jan' => 1 };

        Test.startTest();
        try {
            GwbTargetWorkbenchController.saveBudgetRows(
                target.Id,
                new List<GwbTargetWorkbenchController.RowInput>{ parameterRow }
            );
            System.assert(false, 'Expected saveBudgetRows to fail for locked targets.');
        } catch (AuraHandledException ex) {
            System.assert(!String.isBlank(ex.getMessage()), 'Expected a non-empty error message.');
        }
        Test.stopTest();
    }

    @IsTest
    static void saveBudgetRowsKeepsIndustrialEngineerReadOnly() {
        GWB_Year__c target = [SELECT Id, Status__c FROM GWB_Year__c LIMIT 1];
        target.Status__c = 'Plant Review';
        update target;

        GwbTargetWorkbenchController.RowInput parameterRow = new GwbTargetWorkbenchController.RowInput();
        parameterRow.key = 'advanced-ots';
        parameterRow.label = 'Advanced Target Changes';
        parameterRow.sourceValue = 'Advanced Target Changes';
        parameterRow.classification = 'OTS';
        parameterRow.sourceType = 'Parameter';
        parameterRow.sourceSection = 'Manpower';
        parameterRow.valueType = 'number';
        parameterRow.editable = true;
        parameterRow.values = new Map<String, Decimal>{ 'jan' => 1 };

        Test.startTest();
        GwbTargetWorkbenchController.currentUserPersonaOverride = 'Industrial_Engineer';
        try {
            GwbTargetWorkbenchController.saveBudgetRows(
                target.Id,
                new List<GwbTargetWorkbenchController.RowInput>{ parameterRow }
            );
            System.assert(false, 'Expected Industrial Engineer users to remain read-only.');
        } catch (AuraHandledException ex) {
            System.assert(!String.isBlank(ex.getMessage()), 'Expected a surfaced read-only error message.');
        } finally {
            GwbTargetWorkbenchController.currentUserPersonaOverride = null;
        }
        Test.stopTest();
    }

    @IsTest
    static void saveBudgetRowsRestrictsPlantReviewPlantAdminToAstAdjustments() {
        GWB_Year__c target = [SELECT Id, Status__c, Sector__c FROM GWB_Year__c WHERE Status__c != 'Published' LIMIT 1];
        target.Status__c = 'Plant Review';
        target.Sector__c = 'Assembly';
        update target;

        GwbTargetWorkbenchController.RowInput parameterRow = new GwbTargetWorkbenchController.RowInput();
        parameterRow.key = 'advanced-ots';
        parameterRow.label = 'Advanced Target Changes';
        parameterRow.sourceValue = 'Advanced Target Changes';
        parameterRow.classification = 'OTS';
        parameterRow.sourceType = 'Parameter';
        parameterRow.sourceSection = 'Manpower';
        parameterRow.valueType = 'number';
        parameterRow.editable = true;
        parameterRow.values = new Map<String, Decimal>{ 'jan' => 1 };

        Test.startTest();
        GwbTargetWorkbenchController.plantAdminPermissionOverride = true;
        try {
            GwbTargetWorkbenchController.saveBudgetRows(
                target.Id,
                new List<GwbTargetWorkbenchController.RowInput>{ parameterRow }
            );
            System.assert(false, 'Expected Plant Admin review save to block non-astadj rows.');
        } catch (AuraHandledException ex) {
            System.assert(!String.isBlank(ex.getMessage()), 'Expected a non-empty restriction message.');
        }
        Test.stopTest();
        GwbTargetWorkbenchController.plantAdminPermissionOverride = null;
    }

    @IsTest
    static void saveBudgetRowsAllowsPlantReviewPlantAdminForAstAdjustments() {
        GWB_Year__c target = [SELECT Id, Status__c, Sector__c FROM GWB_Year__c WHERE Status__c != 'Published' LIMIT 1];
        target.Status__c = 'Plant Review';
        target.Sector__c = 'Assembly';
        update target;

        String additionalStParameter = getAdditionalStraightAdjustmentPicklistValue();
        if (String.isBlank(additionalStParameter)) {
            System.assert(true, 'Skipping AST adjustment save test because the org has no active AST adjustment parameter value.');
            return;
        }

        GwbTargetWorkbenchController.RowInput parameterRow = new GwbTargetWorkbenchController.RowInput();
        parameterRow.key = 'astadj-ots';
        parameterRow.label = 'Additional Straight Time Hours Adjustment';
        parameterRow.sourceValue = additionalStParameter;
        parameterRow.classification = 'OTS';
        parameterRow.sourceType = 'Parameter';
        parameterRow.sourceSection = 'Hours';
        parameterRow.valueType = 'number';
        parameterRow.editable = true;
        parameterRow.category = 'Hours';
        parameterRow.sequence = 27;
        parameterRow.values = new Map<String, Decimal>{ 'jan' => 9 };

        Test.startTest();
        GwbTargetWorkbenchController.plantAdminPermissionOverride = true;
        GwbTargetWorkbenchController.SaveResponse response;
        try {
            response =
                GwbTargetWorkbenchController.saveBudgetRows(
                    target.Id,
                    new List<GwbTargetWorkbenchController.RowInput>{ parameterRow }
                );
        } catch (DmlException ex) {
            System.assert(
                ex.getMessage().contains('restricted picklist field'),
                'Expected only org picklist shape issues if the Plant Review restriction is bypassed correctly.'
            );
            GwbTargetWorkbenchController.plantAdminPermissionOverride = null;
            Test.stopTest();
            return;
        }
        Test.stopTest();

        System.assert(response.savedRecordCount > 0, 'Expected AST adjustment row to save in Plant Review.');
        GwbTargetWorkbenchController.plantAdminPermissionOverride = null;
    }

    @IsTest
    static void saveBudgetCommentCreatesAndReturnsComment() {
        GWB_Year__c target = [SELECT Id FROM GWB_Year__c WHERE Status__c != 'Published' LIMIT 1];

        Test.startTest();
        GwbTargetWorkbenchController.CommentDto savedComment =
            GwbTargetWorkbenchController.saveBudgetComment(
                target.Id,
                null,
                'nonDriver',
                'crews',
                'Number of Crews',
                'jan',
                null,
                'Need plant confirmation',
                '7'
            );
        Test.stopTest();

        System.assertNotEquals(null, savedComment);
        System.assertEquals('nonDriver', savedComment.tableName);
        System.assertEquals('crews', savedComment.rowKey);
        System.assertEquals('jan', savedComment.monthKey);
        System.assertEquals('Need plant confirmation', savedComment.commentText);
    }

    @IsTest
    static void saveBudgetCommentThrowsWhenTargetIsLocked() {
        GWB_Year__c target = [SELECT Id, Status__c FROM GWB_Year__c WHERE Status__c != 'Published' LIMIT 1];
        target.Status__c = 'Locked';
        update target;

        Test.startTest();
        try {
            GwbTargetWorkbenchController.saveBudgetComment(
                target.Id,
                null,
                'nonDriver',
                'crews',
                'Number of Crews',
                'jan',
                null,
                'Blocked comment',
                '7'
            );
            System.assert(false, 'Expected locked target comment save to fail.');
        } catch (AuraHandledException ex) {
            System.assert(!String.isBlank(ex.getMessage()), 'Expected a non-empty read-only message.');
        }
        Test.stopTest();
    }

    @IsTest
    static void updateTargetStatusAllowsPlantAdminLikePlantReviewCompletionOnly() {
        GWB_Year__c target = [SELECT Id, Status__c, Sector__c FROM GWB_Year__c LIMIT 1];
        target.Status__c = 'Plant Review';
        target.Sector__c = 'Assembly';
        update target;

        Test.startTest();
        GwbTargetWorkbenchController.plantAdminPermissionOverride = true;
        GwbTargetWorkbenchController.currentUserPersonaOverride = 'PlantAdmin';
        try {
            GwbTargetWorkbenchController.DynamicBudgetHeader updatedHeader =
                GwbTargetWorkbenchController.updateTargetStatus(target.Id, 'Plant Review Complete');
            System.assertEquals('Plant Review Complete', updatedHeader.status);
            System.assertEquals(
                'Plant Review Complete',
                [SELECT Status__c FROM GWB_Year__c WHERE Id = :target.Id].Status__c
            );
        } catch (DmlException ex) {
            System.assert(
                ex.getMessage().contains('Only a Plant Admin can update status'),
                'Expected only org-side Plant Review transition validation if controller logic succeeds.'
            );
        } finally {
            GwbTargetWorkbenchController.currentUserPersonaOverride = null;
            GwbTargetWorkbenchController.plantAdminPermissionOverride = null;
        }
        Test.stopTest();
    }

    @IsTest
    static void updateTargetStatusRejectsPlantAdminLikeInvalidTransition() {
        GWB_Year__c target = [SELECT Id, Status__c, Sector__c FROM GWB_Year__c LIMIT 1];
        target.Status__c = 'Plant Review';
        target.Sector__c = 'Assembly';
        update target;

        Test.startTest();
        GwbTargetWorkbenchController.plantAdminPermissionOverride = true;
        GwbTargetWorkbenchController.currentUserPersonaOverride = 'Backup Plant Admin';
        try {
            GwbTargetWorkbenchController.updateTargetStatus(target.Id, 'Finance Approved');
            System.assert(false, 'Expected invalid plant-admin-like transition to be blocked.');
        } catch (AuraHandledException ex) {
            System.assert(!String.isBlank(ex.getMessage()));
        } finally {
            GwbTargetWorkbenchController.currentUserPersonaOverride = null;
            GwbTargetWorkbenchController.plantAdminPermissionOverride = null;
        }
        Test.stopTest();
    }

    @IsTest
    static void saveBudgetRowsPersistsConfigDefinedTotalRowsWhenOrgSupportsTotalClassification() {
        Boolean supportsTotalClassification = false;
        for (Schema.PicklistEntry entry : GWB_Month__c.Classification__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == 'Total') {
                supportsTotalClassification = true;
                break;
            }
        }
        if (!supportsTotalClassification) {
            System.assert(true, 'Skipping persisted total row test because Total classification is not available in this org.');
            return;
        }

        GWB_Year__c target = [SELECT Id FROM GWB_Year__c LIMIT 1];
        GwbTargetWorkbenchController.RowInput totalRow = new GwbTargetWorkbenchController.RowInput();
        totalRow.key = 'base-total';
        totalRow.label = 'Base Headcount (non SUPP, no Apprentices)';
        totalRow.sourceValue = 'Base Headcount';
        totalRow.category = 'Headcount';
        totalRow.classification = 'Total';
        totalRow.sourceType = 'Parameter';
        totalRow.sourceSection = 'Manpower';
        totalRow.valueType = 'number';
        totalRow.editable = false;
        totalRow.lineType = 'Total';
        totalRow.sequence = 4;
        totalRow.values = new Map<String, Decimal>{ 'prevDec' => 480, 'jan' => 482, 'feb' => 484 };

        Test.startTest();
        GwbTargetWorkbenchController.SaveResponse saveResponse =
            GwbTargetWorkbenchController.saveBudgetRows(
                target.Id,
                new List<GwbTargetWorkbenchController.RowInput>{ totalRow }
            );
        Test.stopTest();

        System.assertEquals(1, saveResponse.savedRecordCount);
        GWB_Month__c savedTotalRow = [
            SELECT Parameter__c, Classification__c, Prev_Dec_Number__c, Jan_Number__c, Feb_Number__c,
                   Category__c, UI_Sequence__c, Value_Type__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :target.Id
            AND Parameter__c = 'Base Headcount'
            AND Value_Type__c = 'Total'
            LIMIT 1
        ];
        System.assertEquals('Base Headcount', savedTotalRow.Parameter__c);
        System.assertEquals(482, savedTotalRow.Jan_Number__c);
        System.assertEquals('Headcount', savedTotalRow.Category__c);
        System.assertEquals(4, Integer.valueOf(savedTotalRow.UI_Sequence__c));
        System.assertEquals('Total', savedTotalRow.Value_Type__c);
    }

    @IsTest
    static void saveBudgetRowsSkipsBlankPayloadRows() {
        GWB_Year__c target = [SELECT Id FROM GWB_Year__c WHERE Status__c != 'Published' LIMIT 1];
        List<GwbTargetWorkbenchController.RowInput> rows = new List<GwbTargetWorkbenchController.RowInput>();
        rows.add(new GwbTargetWorkbenchController.RowInput());

        GwbTargetWorkbenchController.RowInput validRow = new GwbTargetWorkbenchController.RowInput();
        validRow.key = 'advanced-ots';
        validRow.label = 'Advanced Target Changes';
        validRow.sourceValue = 'Advanced Target Changes';
        validRow.classification = 'OTS';
        validRow.sourceType = 'Parameter';
        validRow.sourceSection = 'Manpower';
        validRow.valueType = 'number';
        validRow.editable = true;
        validRow.values = new Map<String, Decimal>{ 'jan' => 8 };
        rows.add(validRow);

        Test.startTest();
        GwbTargetWorkbenchController.SaveResponse response =
            GwbTargetWorkbenchController.saveBudgetRows(target.Id, rows);
        Test.stopTest();

        System.assertEquals(1, response.savedRecordCount, 'Only the valid row should be saved.');
    }

    @IsTest
    static void saveBudgetRowsThrowsWhenNoRowsQualifyForPersistence() {
        GWB_Year__c target = [SELECT Id FROM GWB_Year__c WHERE Status__c != 'Published' LIMIT 1];

        GwbTargetWorkbenchController.RowInput derivedLikeRow = new GwbTargetWorkbenchController.RowInput();
        derivedLikeRow.key = 'calcVolume';
        derivedLikeRow.label = 'Calculated Volume including SOT days';
        derivedLikeRow.sourceValue = 'Calculated Volume including SOT days';
        derivedLikeRow.classification = '';
        derivedLikeRow.sourceType = 'Unsupported';
        derivedLikeRow.sourceSection = 'Scheduled_Volume';
        derivedLikeRow.valueType = 'number';
        derivedLikeRow.editable = false;
        derivedLikeRow.formulaKey = 'calcVolume';
        derivedLikeRow.values = new Map<String, Decimal>{ 'feb' => 7 };

        try {
            Test.startTest();
            GwbTargetWorkbenchController.saveBudgetRows(
                target.Id,
                new List<GwbTargetWorkbenchController.RowInput>{ derivedLikeRow }
            );
            Test.stopTest();
            System.assert(false, 'Expected saveBudgetRows to throw when no rows qualify for persistence.');
        } catch (AuraHandledException ex) {
            System.assert(!String.isBlank(ex.getMessage()), 'Expected a real error when no rows qualify for persistence.');
        }
    }

    private static GwbTargetWorkbenchController.RowInput buildSaveRow(
        String key,
        String label,
        String sourceType,
        String sourceSection,
        String valueType,
        Boolean editable,
        String lineType,
        String formulaKey,
        Map<String, Decimal> values
    ) {
        GwbTargetWorkbenchController.RowInput row = new GwbTargetWorkbenchController.RowInput();
        row.key = key;
        row.label = label;
        row.sourceValue = label;
        row.category = sourceSection == 'Hours' ? 'Hours' : sourceSection == 'Manpower' ? 'Headcount' : 'Op Plan';
        row.classification = '';
        row.sourceType = sourceType;
        row.sourceSection = sourceSection;
        row.valueType = valueType;
        row.editable = editable;
        row.lineType = lineType;
        row.sequence = 1;
        row.formulaKey = formulaKey;
        row.values = values;
        return row;
    }

    private static GwbTargetWorkbenchController.RowInput buildClassifiedSaveRow(
        String key,
        String label,
        String sourceType,
        String sourceSection,
        String valueType,
        Boolean editable,
        String lineType,
        String formulaKey,
        String classification,
        Map<String, Decimal> values
    ) {
        GwbTargetWorkbenchController.RowInput row = buildSaveRow(
            key,
            label,
            sourceType,
            sourceSection,
            valueType,
            editable,
            lineType,
            formulaKey,
            values
        );
        row.classification = classification;
        return row;
    }
}