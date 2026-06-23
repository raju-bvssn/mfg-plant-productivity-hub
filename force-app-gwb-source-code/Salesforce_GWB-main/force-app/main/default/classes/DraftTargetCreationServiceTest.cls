@IsTest
private class DraftTargetCreationServiceTest {
    @TestSetup
    static void setupData() {
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        String switchObjectName = globalDescribe.containsKey('GWB_Switch__c')
            ? 'GWB_Switch__c'
            : (globalDescribe.containsKey('Onstar_Switch__c') ? 'Onstar_Switch__c' : null);
        if (switchObjectName == null) {
            return;
        }

        SObject bypassRecord = globalDescribe.get(switchObjectName).newSObject();
        bypassRecord.put('SetupOwnerId', UserInfo.getUserId());
        Map<String, Schema.SObjectField> switchFields = bypassRecord.getSObjectType().getDescribe().fields.getMap();
        if (switchFields.containsKey('Bypass_VRs__c')) {
            bypassRecord.put('Bypass_VRs__c', true);
        }
        if (switchFields.containsKey('Bypass_Flows__c')) {
            bypassRecord.put('Bypass_Flows__c', true);
        }
        if (switchFields.containsKey('Bypass_Triggers__c')) {
            bypassRecord.put('Bypass_Triggers__c', true);
        }
        insert bypassRecord;
    }

    private static String getActivePicklistValue(Schema.SObjectField fieldReference, Integer activeIndex) {
        Integer currentIndex = 0;
        for (Schema.PicklistEntry entry : fieldReference.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            if (currentIndex == activeIndex) {
                return entry.getValue();
            }
            currentIndex++;
        }
        return null;
    }

    @IsTest
    static void processPlantSectors_handlesEmptyAndIncompleteRows() {
        DraftTargetCreationService.ProcessingResult emptyResult =
            DraftTargetCreationService.processPlantSectors(null, GwbBudgetTestSupport.VERSION, null, null);
        System.assertEquals(0, emptyResult.successCount);
        System.assertEquals(0, emptyResult.failureCount);

        DraftTargetCreationService.ProcessingResult failureResult =
            DraftTargetCreationService.processPlantSectors(
                new List<Plant_Sector__c>{ new Plant_Sector__c() },
                GwbBudgetTestSupport.VERSION,
                null,
                null
            );

        System.assertEquals(0, failureResult.successCount);
        System.assertEquals(1, failureResult.failureCount);
        System.assertEquals(1, failureResult.failureMessages.size());
        System.assert(failureResult.failureMessages[0].contains('Plant Sector data is incomplete.'));
    }

    @IsTest
    static void processPlantSectors_createsAssemblyTargetAndCopiesJustifications() {
        String targetYear = String.valueOf(Date.today().year() + 1);
        String previousYear = String.valueOf(Date.today().year());

        Plant__c plantRecord = GwbBudgetTestSupport.createPlant('Assembly Plant', 'Assembly', null);
        Plant_Sector__c plantSector = GwbBudgetTestSupport.createPlantSector(
            plantRecord.Id,
            'Assembly',
            null,
            null
        );

        GWB_Year__c previousLockedTarget = GwbBudgetTestSupport.createTarget(
            plantRecord.Id,
            plantSector.Id,
            'Assembly',
            previousYear,
            'Locked',
            GwbBudgetTestSupport.VERSION
        );

        GwbBudgetTestSupport.createSharedMonth(
            previousLockedTarget.Id,
            plantRecord.Id,
            'Assembly',
            previousYear,
            GwbBudgetTestSupport.VERSION,
            'Scheduled_Volume',
            'Scheduled Volume',
            null,
            'number',
            7,
            null,
            null,
            null
        );
        GwbBudgetTestSupport.createSharedMonth(
            previousLockedTarget.Id,
            plantRecord.Id,
            'Assembly',
            previousYear,
            GwbBudgetTestSupport.VERSION,
            'Manpower',
            'Base Headcount',
            'OTS',
            'number',
            null,
            null,
            null,
            5
        );
        GwbBudgetTestSupport.createSharedMonth(
            previousLockedTarget.Id,
            plantRecord.Id,
            'Assembly',
            previousYear,
            GwbBudgetTestSupport.VERSION,
            'Manpower',
            'Previous YE Approved Target Changes',
            'OTS',
            'number',
            null,
            null,
            null,
            1
        );
        GwbBudgetTestSupport.createSharedMonth(
            previousLockedTarget.Id,
            plantRecord.Id,
            'Assembly',
            previousYear,
            GwbBudgetTestSupport.VERSION,
            'Manpower',
            'Absenteeism %',
            'OTS',
            'percent',
            null,
            null,
            null,
            0.12
        );
        GwbBudgetTestSupport.createSharedMonth(
            previousLockedTarget.Id,
            plantRecord.Id,
            'Assembly',
            previousYear,
            GwbBudgetTestSupport.VERSION,
            'Scheduled_Volume',
            'Net/Net JPH',
            null,
            'decimal',
            null,
            null,
            null,
            3.5
        );
        GwbBudgetTestSupport.createSharedMonth(
            previousLockedTarget.Id,
            plantRecord.Id,
            'Assembly',
            previousYear,
            GwbBudgetTestSupport.VERSION,
            'Manpower',
            'Additional Straight Time Hours Adjustment',
            'OTS',
            'number',
            null,
            null,
            null,
            4
        );
        insert new GWB_Month__c(
            GWB_Year__c = previousLockedTarget.Id,
            Plant__c = plantRecord.Id,
            Sector__c = 'Assembly',
            Year__c = previousYear,
            Data_Point_Value__c = GwbBudgetTestSupport.VERSION,
            Section__c = 'Headcount',
            Category__c = 'Headcount',
            Driver__c = 'Productivity',
            Classification__c = 'OTS',
            Value_Type__c = 'Value',
            Dec_Number__c = 12
        );
        GwbBudgetTestSupport.createComment(
            previousLockedTarget.Id,
            'hoursJustification',
            'astjust-monthly',
            'Additional ST Adjustment',
            'dec',
            'OTS',
            'Carry this comment forward',
            '4'
        );

        GwbBudgetTestSupport.createPlantVolume(
            plantRecord.Id,
            'Assembly',
            targetYear,
            GwbBudgetTestSupport.VERSION,
            'January',
            100,
            null,
            null,
            null
        );
        GwbBudgetTestSupport.createPlantVolume(
            plantRecord.Id,
            'Assembly',
            targetYear,
            GwbBudgetTestSupport.VERSION,
            'February',
            200,
            null,
            null,
            null
        );

        Test.startTest();
        DraftTargetCreationService.ProcessingResult result =
            DraftTargetCreationService.processPlantSectors(
                new List<Plant_Sector__c>{ plantSector },
                GwbBudgetTestSupport.VERSION,
                null,
                null
            );
        Test.stopTest();

        System.assertEquals(0, result.failureCount, 'Generation failures: ' + String.join(result.failureMessages, ' || '));
        System.assertEquals(1, result.successCount, 'Generation failures: ' + String.join(result.failureMessages, ' || '));

        GWB_Year__c createdTarget = [
            SELECT Id, Previous_Year_GWB__c, Status__c, Year__c, Version__c, M_Schedule_Version__c
            FROM GWB_Year__c
            WHERE Plant__c = :plantRecord.Id
            AND Plant_Sector__c = :plantSector.Id
            AND Year__c = :targetYear
            AND Status__c = 'Draft'
            LIMIT 1
        ];
        System.assertEquals(previousLockedTarget.Id, createdTarget.Previous_Year_GWB__c);
        System.assertEquals(targetYear + ' 01+11', createdTarget.Version__c);
        System.assertEquals(GwbBudgetTestSupport.VERSION, createdTarget.M_Schedule_Version__c);

        GWB_Month__c scheduledVolumeRow = [
            SELECT Prev_Dec_Number__c, Jan_Number__c, Feb_Number__c, Dec_Number__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :createdTarget.Id
            AND Parameter__c = 'Scheduled Volume'
            LIMIT 1
        ];
        System.assertNotEquals(null, scheduledVolumeRow.Prev_Dec_Number__c, 'Prev Dec scheduled volume should be populated.');
        System.assertEquals(100, scheduledVolumeRow.Jan_Number__c);
        System.assertEquals(200, scheduledVolumeRow.Feb_Number__c);
        System.assertEquals(0, scheduledVolumeRow.Dec_Number__c);

        GWB_Month__c baseHeadcountRow = [
            SELECT Prev_Dec_Number__c, Jan_Number__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :createdTarget.Id
            AND Parameter__c = 'Base Headcount'
            AND Classification__c = 'OTS'
            LIMIT 1
        ];
        System.assertEquals(5, baseHeadcountRow.Prev_Dec_Number__c);
        System.assertEquals(5, baseHeadcountRow.Jan_Number__c);

        GWB_Month__c approvedTargetRow = [
            SELECT Prev_Dec_Number__c, Jan_Number__c, Feb_Number__c, Dec_Number__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :createdTarget.Id
            AND Parameter__c = 'Previous YE Approved Target Changes'
            AND Classification__c = 'OTS'
            LIMIT 1
        ];
        System.assertEquals(1, approvedTargetRow.Prev_Dec_Number__c);
        System.assertEquals(null, approvedTargetRow.Jan_Number__c, 'Previous-year approved target changes should only populate Prior Dec.');
        System.assertEquals(null, approvedTargetRow.Feb_Number__c);
        System.assertEquals(null, approvedTargetRow.Dec_Number__c);

        GWB_Month__c productivityDriverRow = [
            SELECT Prev_Dec_Number__c, Jan_Number__c, Feb_Number__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :createdTarget.Id
            AND Driver__c = 'Productivity'
            AND Classification__c = 'OTS'
            LIMIT 1
        ];
        System.assertEquals(12, productivityDriverRow.Prev_Dec_Number__c, 'Driver rows should carry the previous locked target December value into Prior Dec.');
        System.assertEquals(0, productivityDriverRow.Jan_Number__c, 'Driver rows should not copy previous-year adjustments across future target months.');
        System.assertEquals(0, productivityDriverRow.Feb_Number__c);

        List<GWB_Budget_Comment__c> copiedComments = [
            SELECT Id, Month_Key__c, Comment_Text__c
            FROM GWB_Budget_Comment__c
            WHERE GWB_Year__c = :createdTarget.Id
            AND Table_Name__c = 'hoursJustification'
            AND Row_Key__c = 'astjust-monthly'
        ];
        System.assertEquals(12, copiedComments.size());
        System.assertEquals('Carry this comment forward', copiedComments[0].Comment_Text__c);
    }

    @IsTest
    static void loadMethods_respectPolymersVehicleBrandFiltersAndPrevDecFallback() {
        String sourceYear = String.valueOf(Date.today().year() + 1);
        String previousYear = String.valueOf(Date.today().year());

        Plant__c plantRecord = GwbBudgetTestSupport.createPlant('Polymers Plant', 'Polymers', 'SILVERADO;SIERRA');
        Plant_Sector__c plantSector = GwbBudgetTestSupport.createPlantSector(
            plantRecord.Id,
            'Polymers',
            null,
            null
        );

        GWB_Year__c previousLockedTarget = GwbBudgetTestSupport.createTarget(
            plantRecord.Id,
            plantSector.Id,
            'Polymers',
            previousYear,
            'Locked',
            GwbBudgetTestSupport.VERSION
        );
        GwbBudgetTestSupport.createSharedMonth(
            previousLockedTarget.Id,
            plantRecord.Id,
            'Polymers',
            previousYear,
            GwbBudgetTestSupport.VERSION,
            'Scheduled_Volume',
            'Scheduled Volume',
            null,
            'number',
            55,
            null,
            null,
            null
        );

        GWB_Year__c sourceTarget = GwbBudgetTestSupport.createTarget(
            plantRecord.Id,
            plantSector.Id,
            'Polymers',
            sourceYear,
            'Finance Approved',
            GwbBudgetTestSupport.VERSION
        );

        GwbBudgetTestSupport.createPlantVolume(
            plantRecord.Id,
            'Polymers',
            sourceYear,
            GwbBudgetTestSupport.VERSION,
            'January',
            3,
            'SILVERADO',
            null,
            null
        );
        GwbBudgetTestSupport.createPlantVolume(
            plantRecord.Id,
            'Polymers',
            sourceYear,
            GwbBudgetTestSupport.VERSION,
            'February',
            4,
            'SIERRA',
            null,
            null
        );
        GwbBudgetTestSupport.createPlantVolume(
            plantRecord.Id,
            'Polymers',
            sourceYear,
            GwbBudgetTestSupport.VERSION,
            'January',
            9,
            'Cadillac',
            null,
            null
        );

        GWB_Year__c queriedSourceTarget = [
            SELECT Id, Plant__c, Plant__r.Vehicle_Brand__c, Sector__c, Year__c, Plant_Sector__c
            FROM GWB_Year__c
            WHERE Id = :sourceTarget.Id
            LIMIT 1
        ];

        Map<Id, Map<String, Decimal>> volumesByTargetId =
            DraftTargetCreationService.loadScheduledVolumeBySourceTarget(
                new List<GWB_Year__c>{ queriedSourceTarget },
                GwbBudgetTestSupport.VERSION
            );
        Map<Id, Decimal> prevDecByTargetId =
            DraftTargetCreationService.loadPrevYearScheduledVolumeDecByTarget(
                new List<GWB_Year__c>{ queriedSourceTarget }
            );

        System.assertNotEquals(null, volumesByTargetId.get(sourceTarget.Id), 'Expected scheduled volume map for source target.');
        System.assert(volumesByTargetId.get(sourceTarget.Id).get('jan') >= 0, 'January scheduled volume should be non-negative.');
        System.assert(volumesByTargetId.get(sourceTarget.Id).get('feb') >= 0, 'February scheduled volume should be non-negative.');
        System.assert(
            prevDecByTargetId.containsKey(sourceTarget.Id),
            'Previous December lookup should return a map entry for the source target.'
        );
    }

    @IsTest
    static void processPlantSectors_usesTheLatestLockedTargetForCarryForward() {
        String targetYear = String.valueOf(Date.today().year() + 1);
        String previousYear = String.valueOf(Date.today().year());

        Plant__c plantRecord = GwbBudgetTestSupport.createPlant('Assembly Plant Latest Locked', 'Assembly', null);
        Plant_Sector__c plantSector = GwbBudgetTestSupport.createPlantSector(
            plantRecord.Id,
            'Assembly',
            null,
            null
        );

        GWB_Year__c earlierLockedTarget = GwbBudgetTestSupport.createTarget(
            plantRecord.Id,
            plantSector.Id,
            'Assembly',
            previousYear,
            'Locked',
            getActivePicklistValue(GWB_Year__c.M_Schedule_Version__c, 0)
        );
        Test.setCreatedDate(earlierLockedTarget.Id, System.now().addMinutes(-5));
        GWB_Year__c latestLockedTarget = GwbBudgetTestSupport.createTarget(
            plantRecord.Id,
            plantSector.Id,
            'Assembly',
            previousYear,
            'Locked',
            GwbBudgetTestSupport.VERSION
        );

        GwbBudgetTestSupport.createSharedMonth(
            latestLockedTarget.Id,
            plantRecord.Id,
            'Assembly',
            previousYear,
            GwbBudgetTestSupport.VERSION,
            'Scheduled_Volume',
            'Scheduled Volume',
            null,
            'number',
            9,
            null,
            null,
            null
        );

        GwbBudgetTestSupport.createPlantVolume(
            plantRecord.Id,
            'Assembly',
            targetYear,
            GwbBudgetTestSupport.VERSION,
            'January',
            100,
            null,
            null,
            null
        );

        Test.startTest();
        DraftTargetCreationService.ProcessingResult result =
            DraftTargetCreationService.processPlantSectors(
                new List<Plant_Sector__c>{ plantSector },
                GwbBudgetTestSupport.VERSION,
                null,
                null
            );
        Test.stopTest();

        System.assertEquals(0, result.failureCount, 'Generation failures: ' + String.join(result.failureMessages, ' || '));
        System.assertEquals(1, result.successCount, 'One target should be generated from the latest locked baseline. Failures: ' + String.join(result.failureMessages, ' || '));

        GWB_Year__c createdTarget = [
            SELECT Previous_Year_GWB__c
            FROM GWB_Year__c
            WHERE Plant__c = :plantRecord.Id
            AND Plant_Sector__c = :plantSector.Id
            AND Year__c = :targetYear
            AND Status__c = 'Draft'
            LIMIT 1
        ];
        System.assertEquals(
            latestLockedTarget.Id,
            createdTarget.Previous_Year_GWB__c,
            'Target generation should carry forward from the most recently created locked target.'
        );
    }

    @IsTest
    static void processPlantSectors_matchesPreviousLockedTargetByPlantSector() {
        String targetYear = String.valueOf(Date.today().year() + 1);
        String previousYear = String.valueOf(Date.today().year());

        Plant__c plantRecord = GwbBudgetTestSupport.createPlant('Assembly Plant Sector Match', 'Assembly', null);
        String programCode = getActivePicklistValue(Plant_Sector__c.Program_Code__c, 0);

        Plant_Sector__c firstPlantSector = GwbBudgetTestSupport.createPlantSector(plantRecord.Id, 'Assembly', programCode, null);
        Plant_Sector__c secondPlantSector = GwbBudgetTestSupport.createPlantSector(plantRecord.Id, 'Assembly', programCode, null);

        GWB_Year__c firstLockedTarget = GwbBudgetTestSupport.createTarget(
            plantRecord.Id,
            firstPlantSector.Id,
            'Assembly',
            previousYear,
            'Locked',
            '00+12'
        );
        Test.setCreatedDate(firstLockedTarget.Id, System.now().addMinutes(-5));

        GWB_Year__c secondLockedTarget = GwbBudgetTestSupport.createTarget(
            plantRecord.Id,
            secondPlantSector.Id,
            'Assembly',
            previousYear,
            'Locked',
            GwbBudgetTestSupport.VERSION
        );

        Test.startTest();
        DraftTargetCreationService.ProcessingResult result =
            DraftTargetCreationService.processPlantSectors(
                new List<Plant_Sector__c>{ firstPlantSector },
                GwbBudgetTestSupport.VERSION,
                null,
                null
            );
        Test.stopTest();

        System.assertEquals(0, result.failureCount, 'Generation failures: ' + String.join(result.failureMessages, ' || '));

        GWB_Year__c createdTarget = [
            SELECT Previous_Year_GWB__c
            FROM GWB_Year__c
            WHERE Plant__c = :plantRecord.Id
            AND Plant_Sector__c = :firstPlantSector.Id
            AND Year__c = :targetYear
            AND Status__c = 'Draft'
            LIMIT 1
        ];
        System.assertEquals(
            firstLockedTarget.Id,
            createdTarget.Previous_Year_GWB__c,
            'Target generation should only use the previous locked target from the same Plant Sector config.'
        );
        System.assertNotEquals(
            secondLockedTarget.Id,
            createdTarget.Previous_Year_GWB__c,
            'Target generation should not borrow a previous locked target from another Plant Sector config on the same plant.'
        );
    }

    @IsTest
    static void processPlantSectors_persistsHoursCategoryRowsUsingCompatibleStoredSection() {
        String targetYear = String.valueOf(Date.today().year() + 1);
        String previousYear = String.valueOf(Date.today().year());

        Plant__c plantRecord = GwbBudgetTestSupport.createPlant('Assembly Plant Hours Category', 'Assembly', null);
        Plant_Sector__c plantSector = GwbBudgetTestSupport.createPlantSector(
            plantRecord.Id,
            'Assembly',
            null,
            null
        );

        GWB_Year__c previousLockedTarget = GwbBudgetTestSupport.createTarget(
            plantRecord.Id,
            plantSector.Id,
            'Assembly',
            previousYear,
            'Locked',
            GwbBudgetTestSupport.VERSION
        );

        GwbBudgetTestSupport.createSharedMonth(
            previousLockedTarget.Id,
            plantRecord.Id,
            'Assembly',
            previousYear,
            GwbBudgetTestSupport.VERSION,
            'Manpower',
            'Absenteeism %',
            'OTS',
            'percent',
            0.17,
            null,
            null,
            null
        );
        GwbBudgetTestSupport.createSharedMonth(
            previousLockedTarget.Id,
            plantRecord.Id,
            'Assembly',
            previousYear,
            GwbBudgetTestSupport.VERSION,
            'Manpower',
            'NSOT %',
            'OTS',
            'percent',
            0.09,
            null,
            null,
            null
        );
        GwbBudgetTestSupport.createSharedMonth(
            previousLockedTarget.Id,
            plantRecord.Id,
            'Assembly',
            previousYear,
            GwbBudgetTestSupport.VERSION,
            'Manpower',
            'Additional Straight Time Hours Adjustment',
            'OTS',
            'number',
            6,
            null,
            null,
            null
        );
        GwbBudgetTestSupport.createPlantVolume(
            plantRecord.Id,
            'Assembly',
            targetYear,
            GwbBudgetTestSupport.VERSION,
            'January',
            50,
            null,
            null,
            null
        );

        Test.startTest();
        DraftTargetCreationService.ProcessingResult result =
            DraftTargetCreationService.processPlantSectors(
                new List<Plant_Sector__c>{ plantSector },
                GwbBudgetTestSupport.VERSION,
                null,
                null
            );
        Test.stopTest();

        System.assertEquals(0, result.failureCount, 'Generation failures: ' + String.join(result.failureMessages, ' || '));
        System.assertEquals(1, result.successCount, 'Expected one target to be generated.');

        GWB_Year__c createdTarget = [
            SELECT Id
            FROM GWB_Year__c
            WHERE Plant__c = :plantRecord.Id
            AND Plant_Sector__c = :plantSector.Id
            AND Year__c = :targetYear
            AND Status__c = 'Draft'
            LIMIT 1
        ];

        GWB_Month__c absenteeismRow = [
            SELECT Section__c, Category__c, UI_Sequence__c, Value_Type__c,
                   Prev_Dec_Percent__c, Jan_Percent__c, Feb_Percent__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :createdTarget.Id
            AND Parameter__c = 'Absenteeism %'
            AND Classification__c = 'OTS'
            LIMIT 1
        ];
        System.assertEquals('Headcount', absenteeismRow.Section__c, 'Stored section must remain compatible with the restricted Parameter picklist.');
        System.assertEquals('Hours', absenteeismRow.Category__c, 'Hours inputs must persist as Hours category rows.');
        System.assertEquals('Value', absenteeismRow.Value_Type__c);
        System.assertNotEquals(null, absenteeismRow.UI_Sequence__c, 'Hours rows should carry the configured UI sequence.');
        System.assertEquals(0.17, absenteeismRow.Prev_Dec_Percent__c);
        System.assertEquals(0.17, absenteeismRow.Jan_Percent__c);
        System.assertEquals(0.17, absenteeismRow.Feb_Percent__c);

        GWB_Month__c nsotRow = [
            SELECT Section__c, Category__c, Prev_Dec_Percent__c, Jan_Percent__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :createdTarget.Id
            AND Parameter__c = 'NSOT %'
            AND Classification__c = 'OTS'
            LIMIT 1
        ];
        System.assertEquals('Headcount', nsotRow.Section__c);
        System.assertEquals('Hours', nsotRow.Category__c);
        System.assertEquals(0.09, nsotRow.Prev_Dec_Percent__c);
        System.assertEquals(0.09, nsotRow.Jan_Percent__c);

        GWB_Month__c additionalStAdjustmentRow = [
            SELECT Section__c, Category__c, Prev_Dec_Number__c, Jan_Number__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :createdTarget.Id
            AND Parameter__c = 'Additional Straight Time Hours Adjustment'
            AND Classification__c = 'OTS'
            LIMIT 1
        ];
        System.assertEquals('Headcount', additionalStAdjustmentRow.Section__c);
        System.assertEquals('Hours', additionalStAdjustmentRow.Category__c);
        System.assertEquals(6, additionalStAdjustmentRow.Prev_Dec_Number__c);
        System.assertEquals(6, additionalStAdjustmentRow.Jan_Number__c);

        List<GWB_Month__c> totalManpowerRows = [
            SELECT Classification__c, Value_Type__c, Year__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :createdTarget.Id
            AND Parameter__c = 'Total Manpower (Include Target Changes)'
        ];
        System.assertEquals(4, totalManpowerRows.size(), 'Target creation should create all Total Manpower classification rows.');
        for (GWB_Month__c totalManpowerRow : totalManpowerRows) {
            System.assertEquals(targetYear, totalManpowerRow.Year__c, 'Generated GWB Month rows should carry the target year.');
            System.assertEquals(
                String.isBlank(totalManpowerRow.Classification__c) ? 'Total' : 'Value',
                totalManpowerRow.Value_Type__c,
                'Only the Total Manpower rollup row should be stored as Value Type = Total.'
            );
        }
    }

    @IsTest
    static void processPlantSectors_populatesAssemblyOtsVacationCoverageDuringGeneration() {
        String targetYear = String.valueOf(Date.today().year() + 1);
        String previousYear = String.valueOf(Date.today().year());

        Plant__c plantRecord = GwbBudgetTestSupport.createPlant('Assembly Plant Vacation Coverage', 'Assembly', null);
        Plant_Sector__c plantSector = GwbBudgetTestSupport.createPlantSector(
            plantRecord.Id,
            'Assembly',
            null,
            null
        );

        GWB_Year__c previousLockedTarget = GwbBudgetTestSupport.createTarget(
            plantRecord.Id,
            plantSector.Id,
            'Assembly',
            previousYear,
            'Locked',
            GwbBudgetTestSupport.VERSION
        );

        GwbBudgetTestSupport.createSharedMonth(
            previousLockedTarget.Id,
            plantRecord.Id,
            'Assembly',
            previousYear,
            GwbBudgetTestSupport.VERSION,
            'Manpower',
            'Base Headcount',
            'OTS',
            'number',
            null,
            null,
            null,
            300
        );
        GwbBudgetTestSupport.createSharedMonth(
            previousLockedTarget.Id,
            plantRecord.Id,
            'Assembly',
            previousYear,
            GwbBudgetTestSupport.VERSION,
            'Manpower',
            'Previous YE Approved Target Changes',
            'OTS',
            'number',
            null,
            null,
            null,
            20
        );

        insert new GWB_Vacation_Coverage__c(
            Plant__c = plantRecord.Id,
            Year__c = targetYear,
            Sector__c = 'Assembly',
            Classification__c = 'OTS',
            Vacation_Percent__c = 10,
            Entry_Month_Year__c = 'January',
            Exit_Month_Year__c = 'March'
        );

        Test.startTest();
        DraftTargetCreationService.ProcessingResult result =
            DraftTargetCreationService.processPlantSectors(
                new List<Plant_Sector__c>{ plantSector },
                GwbBudgetTestSupport.VERSION,
                null,
                null
            );
        Test.stopTest();

        System.assertEquals(0, result.failureCount, 'Generation failures: ' + String.join(result.failureMessages, ' || '));
        System.assertEquals(1, result.successCount, 'Expected one target to be generated.');

        GWB_Year__c createdTarget = [
            SELECT Id
            FROM GWB_Year__c
            WHERE Plant__c = :plantRecord.Id
            AND Plant_Sector__c = :plantSector.Id
            AND Year__c = :targetYear
            AND Status__c = 'Draft'
            LIMIT 1
        ];

        List<GWB_Month__c> vacationRows = [
            SELECT Driver__c, Classification__c, Prev_Dec_Number__c, Jan_Number__c, Feb_Number__c, Mar_Number__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :createdTarget.Id
            AND Driver__c = 'Vacation Replacement'
        ];
        System.assertEquals(3, vacationRows.size(), 'Vacation coverage family should still create OTS/Skilled/Salaried rows.');

        GWB_Month__c otsVacationRow;
        for (GWB_Month__c row : vacationRows) {
            if (row.Classification__c == 'OTS') {
                otsVacationRow = row;
                break;
            }
        }
        System.assertNotEquals(null, otsVacationRow, 'Assembly OTS vacation row should be created.');
        System.assertEquals(0, otsVacationRow.Prev_Dec_Number__c);
        System.assertEquals(30, otsVacationRow.Jan_Number__c, 'January should be 10% of OTS base headcount before vacation; previous-year approved target should not be included.');
        System.assertEquals(0, otsVacationRow.Feb_Number__c);
        System.assertEquals(-30, otsVacationRow.Mar_Number__c, 'Exit month should reverse the seeded January coverage.');
    }

    @IsTest
    static void processPlantSectors_keepsPreviousDecemberOnlyParametersOutOfTargetYearCarryForward() {
        String targetYear = String.valueOf(Date.today().year() + 1);
        String previousYear = String.valueOf(Date.today().year());

        Plant__c plantRecord = GwbBudgetTestSupport.createPlant('Assembly Plant Prev Dec Only', 'Assembly', null);
        Plant_Sector__c plantSector = GwbBudgetTestSupport.createPlantSector(
            plantRecord.Id,
            'Assembly',
            null,
            null
        );

        GWB_Year__c previousLockedTarget = GwbBudgetTestSupport.createTarget(
            plantRecord.Id,
            plantSector.Id,
            'Assembly',
            previousYear,
            'Locked',
            GwbBudgetTestSupport.VERSION
        );

        GwbBudgetTestSupport.createSharedMonth(
            previousLockedTarget.Id,
            plantRecord.Id,
            'Assembly',
            previousYear,
            GwbBudgetTestSupport.VERSION,
            'Scheduled_Volume',
            'Available Working Days/Month',
            null,
            'decimal',
            22.5,
            null,
            null,
            null
        );
        GwbBudgetTestSupport.createSharedMonth(
            previousLockedTarget.Id,
            plantRecord.Id,
            'Assembly',
            previousYear,
            GwbBudgetTestSupport.VERSION,
            'Scheduled_Volume',
            'Production Working Days/Month',
            null,
            'decimal',
            19.5,
            null,
            null,
            null
        );
        GwbBudgetTestSupport.createSharedMonth(
            previousLockedTarget.Id,
            plantRecord.Id,
            'Assembly',
            previousYear,
            GwbBudgetTestSupport.VERSION,
            'Scheduled_Volume',
            'EQ SOT Days',
            null,
            'decimal',
            2.25,
            null,
            null,
            null
        );
        GwbBudgetTestSupport.createPlantVolume(
            plantRecord.Id,
            'Assembly',
            targetYear,
            GwbBudgetTestSupport.VERSION,
            'January',
            50,
            null,
            null,
            null
        );

        Test.startTest();
        DraftTargetCreationService.ProcessingResult result =
            DraftTargetCreationService.processPlantSectors(
                new List<Plant_Sector__c>{ plantSector },
                GwbBudgetTestSupport.VERSION,
                null,
                null
            );
        Test.stopTest();

        System.assertEquals(0, result.failureCount, 'Generation failures: ' + String.join(result.failureMessages, ' || '));

        GWB_Year__c createdTarget = [
            SELECT Id
            FROM GWB_Year__c
            WHERE Plant__c = :plantRecord.Id
            AND Plant_Sector__c = :plantSector.Id
            AND Year__c = :targetYear
            AND Status__c = 'Draft'
            LIMIT 1
        ];

        for (GWB_Month__c row : [
            SELECT Parameter__c, Prev_Dec_Decimal__c, Jan_Decimal__c, Feb_Decimal__c, Dec_Decimal__c, Category__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :createdTarget.Id
            AND Parameter__c IN ('Available Working Days/Month', 'Production Working Days/Month', 'EQ SOT Days')
        ]) {
            System.assertEquals('Op Plan', row.Category__c);
            System.assertNotEquals(null, row.Prev_Dec_Decimal__c, 'Prev Dec should be retained for ' + row.Parameter__c);
            System.assertEquals(null, row.Jan_Decimal__c, 'Jan should remain empty for prev-Dec-only parameter ' + row.Parameter__c);
            System.assertEquals(null, row.Feb_Decimal__c, 'Feb should remain empty for prev-Dec-only parameter ' + row.Parameter__c);
            System.assertEquals(null, row.Dec_Decimal__c, 'Dec should remain empty for prev-Dec-only parameter ' + row.Parameter__c);
        }
    }

    @IsTest
    static void processPlantSectors_bulkKeepsCarryForwardDataIsolatedPerPlantSector() {
        String targetYear = String.valueOf(Date.today().year() + 1);
        String previousYear = String.valueOf(Date.today().year());

        Long uniqueSeed = System.now().getTime();
        Plant__c firstPlant = GwbBudgetTestSupport.createPlant('Assembly Bulk Plant One ' + uniqueSeed, 'Assembly', null);
        Plant_Sector__c firstPlantSector = GwbBudgetTestSupport.createPlantSector(firstPlant.Id, 'Assembly', null, null);
        GWB_Year__c firstPreviousLockedTarget = GwbBudgetTestSupport.createTarget(
            firstPlant.Id,
            firstPlantSector.Id,
            'Assembly',
            previousYear,
            'Locked',
            GwbBudgetTestSupport.VERSION
        );
        GwbBudgetTestSupport.createSharedMonth(
            firstPreviousLockedTarget.Id,
            firstPlant.Id,
            'Assembly',
            previousYear,
            GwbBudgetTestSupport.VERSION,
            'Scheduled_Volume',
            'Crews',
            null,
            'number',
            4,
            null,
            null,
            null
        );
        GwbBudgetTestSupport.createPlantVolume(
            firstPlant.Id,
            'Assembly',
            targetYear,
            GwbBudgetTestSupport.VERSION,
            'January',
            80,
            null,
            null,
            null
        );

        String alternateSiteName = getActivePicklistValue(Plant__c.Auth_Site_Name__c, 1);
        if (String.isBlank(alternateSiteName)) {
            System.assert(true, 'Skipping multi-plant bulk isolation test because this org exposes only one active Plant Site value.');
            return;
        }

        Plant__c secondPlant = new Plant__c(
            Name = 'Assembly Bulk Plant Two ' + String.valueOf(uniqueSeed + 1),
            Auth_Sector__c = 'Assembly',
            Auth_Region__c = getActivePicklistValue(Plant__c.Auth_Region__c, 0),
            Auth_Site_Name__c = alternateSiteName,
            MVP__c = 'Harness MVP'
        );
        insert secondPlant;

        Plant_Sector__c secondPlantSector = GwbBudgetTestSupport.createPlantSector(secondPlant.Id, 'Assembly', null, null);
        GWB_Year__c secondPreviousLockedTarget = GwbBudgetTestSupport.createTarget(
            secondPlant.Id,
            secondPlantSector.Id,
            'Assembly',
            previousYear,
            'Locked',
            GwbBudgetTestSupport.VERSION
        );
        GwbBudgetTestSupport.createSharedMonth(
            secondPreviousLockedTarget.Id,
            secondPlant.Id,
            'Assembly',
            previousYear,
            GwbBudgetTestSupport.VERSION,
            'Scheduled_Volume',
            'Crews',
            null,
            'number',
            9,
            null,
            null,
            null
        );
        GwbBudgetTestSupport.createPlantVolume(
            secondPlant.Id,
            'Assembly',
            targetYear,
            GwbBudgetTestSupport.VERSION,
            'January',
            120,
            null,
            null,
            null
        );

        Test.startTest();
        DraftTargetCreationService.ProcessingResult result =
            DraftTargetCreationService.processPlantSectors(
                new List<Plant_Sector__c>{ firstPlantSector, secondPlantSector },
                GwbBudgetTestSupport.VERSION,
                null,
                null
            );
        Test.stopTest();

        System.assertEquals(0, result.failureCount, 'Generation failures: ' + String.join(result.failureMessages, ' || '));
        System.assertEquals(2, result.successCount, 'Both plant sectors should generate their own draft target.');

        Map<Id, GWB_Year__c> generatedTargetsByPlantId = new Map<Id, GWB_Year__c>();
        for (GWB_Year__c targetRecord : [
            SELECT Id, Plant__c, Previous_Year_GWB__c
            FROM GWB_Year__c
            WHERE Plant__c IN :new Set<Id>{ firstPlant.Id, secondPlant.Id }
            AND Year__c = :targetYear
            AND Status__c = 'Draft'
        ]) {
            generatedTargetsByPlantId.put(targetRecord.Plant__c, targetRecord);
        }

        System.assertEquals(2, generatedTargetsByPlantId.size(), 'Expected one generated draft target per plant.');
        System.assertEquals(firstPreviousLockedTarget.Id, generatedTargetsByPlantId.get(firstPlant.Id).Previous_Year_GWB__c);
        System.assertEquals(secondPreviousLockedTarget.Id, generatedTargetsByPlantId.get(secondPlant.Id).Previous_Year_GWB__c);

        Set<Id> generatedTargetIds = new Set<Id>();
        for (GWB_Year__c generatedTarget : generatedTargetsByPlantId.values()) {
            generatedTargetIds.add(generatedTarget.Id);
        }

        Map<Id, Decimal> janCrewsByPlantId = new Map<Id, Decimal>();
        for (GWB_Month__c row : [
            SELECT GWB_Year__r.Plant__c, Prev_Dec_Number__c, Jan_Number__c
            FROM GWB_Month__c
            WHERE GWB_Year__c IN :generatedTargetIds
            AND Parameter__c = 'Crews'
        ]) {
            janCrewsByPlantId.put(row.GWB_Year__r.Plant__c, row.Jan_Number__c);
            System.assertEquals(row.Prev_Dec_Number__c, row.Jan_Number__c, 'Crews should carry December into January for each plant independently.');
        }

        System.assertNotEquals(null, janCrewsByPlantId.get(firstPlant.Id), 'First plant crews row should be present.');
        System.assertNotEquals(null, janCrewsByPlantId.get(secondPlant.Id), 'Second plant crews row should be present.');
    }
}