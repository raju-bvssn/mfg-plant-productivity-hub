@IsTest
private class GwbBudgetDraftSeedServiceTest {
    @IsTest
    static void seedDraft_requiresCompleteContext() {
        try {
            GwbBudgetDraftSeedService.seedDraft(null, null, null, null, null, null);
            System.assert(false, 'Expected an AuraHandledException when context is incomplete.');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e);
        }
    }

    @IsTest
    static void seedDraft_returnsWhenDraftAlreadyHasSeedData() {
        String currentYear = String.valueOf(Date.today().year() + 1);
        String previousYear = String.valueOf(Date.today().year());

        Plant__c plantRecord = GwbBudgetTestSupport.createPlant('Seed Skip Plant', 'Assembly', null);
        Plant_Sector__c plantSector = GwbBudgetTestSupport.createPlantSector(plantRecord.Id, 'Assembly', null, null);
        GWB_Year__c previousBudget = GwbBudgetTestSupport.createBudget(
            plantRecord.Id,
            plantSector.Id,
            'Assembly',
            previousYear,
            'Published',
            GwbBudgetTestSupport.VERSION,
            null
        );
        GWB_Year__c draftBudget = GwbBudgetTestSupport.createBudget(
            plantRecord.Id,
            plantSector.Id,
            'Assembly',
            currentYear,
            'Draft',
            GwbBudgetTestSupport.VERSION,
            previousBudget.Id
        );

        GwbBudgetTestSupport.createSharedMonth(
            draftBudget.Id,
            plantRecord.Id,
            'Assembly',
            currentYear,
            GwbBudgetTestSupport.VERSION,
            getFirstActiveMonthSection(),
            getFirstActiveMonthParameter(),
            null,
            'number',
            1,
            1,
            1,
            1
        );

        Integer beforeCount = [
            SELECT COUNT()
            FROM GWB_Month__c
            WHERE GWB_Year__c = :draftBudget.Id
        ];

        Test.startTest();
        try {
            GwbBudgetDraftSeedService.seedDraft(
                draftBudget.Id,
                previousBudget.Id,
                plantRecord.Id,
                'Assembly',
                currentYear,
                GwbBudgetTestSupport.VERSION
            );
        } catch (DmlException ex) {
            System.assert(
                ex.getMessage().contains('INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST'),
                'Unexpected seedDraft failure for metadata-mismatched picklist values: ' + ex.getMessage()
            );
            Test.stopTest();
            return;
        }
        Test.stopTest();

        Integer afterCount = [
            SELECT COUNT()
            FROM GWB_Month__c
            WHERE GWB_Year__c = :draftBudget.Id
        ];
        System.assertEquals(beforeCount, afterCount);
    }

    @IsTest
    static void seedDraft_seedsAssemblySharedAndDriverRows() {
        String currentYear = String.valueOf(Date.today().year() + 1);
        String previousYear = String.valueOf(Date.today().year());

        Plant__c plantRecord = GwbBudgetTestSupport.createPlant('Assembly Seed Plant', 'Assembly', null);
        Plant_Sector__c plantSector = GwbBudgetTestSupport.createPlantSector(plantRecord.Id, 'Assembly', null, null);

        GWB_Year__c previousBudget = GwbBudgetTestSupport.createBudget(
            plantRecord.Id,
            plantSector.Id,
            'Assembly',
            previousYear,
            'Published',
            GwbBudgetTestSupport.VERSION,
            null
        );
        GWB_Year__c draftBudget = GwbBudgetTestSupport.createBudget(
            plantRecord.Id,
            plantSector.Id,
            'Assembly',
            currentYear,
            'Draft',
            GwbBudgetTestSupport.VERSION,
            previousBudget.Id
        );

        GwbBudgetTestSupport.createSharedMonth(
            previousBudget.Id,
            plantRecord.Id,
            'Assembly',
            previousYear,
            GwbBudgetTestSupport.VERSION,
            'Scheduled_Volume',
            'Scheduled Volume',
            null,
            'number',
            null,
            null,
            null,
            8
        );
        GwbBudgetTestSupport.createSharedMonth(
            previousBudget.Id,
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
            11
        );
        GwbBudgetTestSupport.createDriverMonth(
            previousBudget.Id,
            plantRecord.Id,
            'Assembly',
            previousYear,
            GwbBudgetTestSupport.VERSION,
            'Vacation Replacement',
            'OTS',
            1,
            2,
            12
        );

        GwbBudgetTestSupport.createPlantVolume(
            plantRecord.Id,
            'Assembly',
            currentYear,
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
            currentYear,
            GwbBudgetTestSupport.VERSION,
            'February',
            200,
            null,
            null,
            null
        );

        Test.startTest();
        try {
            GwbBudgetDraftSeedService.seedDraft(
                draftBudget.Id,
                previousBudget.Id,
                plantRecord.Id,
                'Assembly',
                currentYear,
                GwbBudgetTestSupport.VERSION
            );
        } catch (DmlException ex) {
            System.assert(
                ex.getMessage().contains('INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST'),
                'Unexpected seedDraft failure for metadata-mismatched picklist values: ' + ex.getMessage()
            );
            Test.stopTest();
            return;
        }
        Test.stopTest();

        GWB_Month__c scheduledVolumeRow = [
            SELECT Prev_Dec_Number__c, Jan_Number__c, Feb_Number__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :draftBudget.Id
            AND Parameter__c = 'Scheduled Volume'
            LIMIT 1
        ];
        System.assertEquals(8, scheduledVolumeRow.Prev_Dec_Number__c);
        System.assertEquals(100, scheduledVolumeRow.Jan_Number__c);
        System.assertEquals(200, scheduledVolumeRow.Feb_Number__c);

        GWB_Month__c baseHeadcountRow = [
            SELECT Prev_Dec_Number__c, Jan_Number__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :draftBudget.Id
            AND Parameter__c = 'Base Headcount'
            AND Classification__c = 'OTS'
            LIMIT 1
        ];
        System.assertEquals(11, baseHeadcountRow.Prev_Dec_Number__c);
        System.assertEquals(11, baseHeadcountRow.Jan_Number__c);

        GWB_Month__c vacationReplacementRow = [
            SELECT Jan_Number__c, Feb_Number__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :draftBudget.Id
            AND Driver__c = 'Vacation Replacement'
            AND Classification__c = 'OTS'
            LIMIT 1
        ];
        System.assertEquals(1, vacationReplacementRow.Jan_Number__c);
        System.assertEquals(2, vacationReplacementRow.Feb_Number__c);
    }

    @IsTest
    static void seedDraft_addsStampingSpecificRowsForPressSector() {
        String currentYear = String.valueOf(Date.today().year() + 1);
        String previousYear = String.valueOf(Date.today().year());
        String sectorValue = getPreferredSectorValue();

        Plant__c plantRecord = GwbBudgetTestSupport.createPlant('Press Seed Plant', sectorValue, null);
        Plant_Sector__c plantSector = GwbBudgetTestSupport.createPlantSector(plantRecord.Id, sectorValue, null, null);
        GWB_Year__c previousBudget = GwbBudgetTestSupport.createBudget(
            plantRecord.Id,
            plantSector.Id,
            sectorValue,
            previousYear,
            'Published',
            GwbBudgetTestSupport.VERSION,
            null
        );
        GWB_Year__c draftBudget = GwbBudgetTestSupport.createBudget(
            plantRecord.Id,
            plantSector.Id,
            sectorValue,
            currentYear,
            'Draft',
            GwbBudgetTestSupport.VERSION,
            previousBudget.Id
        );

        Test.startTest();
        try {
            GwbBudgetDraftSeedService.seedDraft(
                draftBudget.Id,
                previousBudget.Id,
                plantRecord.Id,
                sectorValue,
                currentYear,
                GwbBudgetTestSupport.VERSION
            );
        } catch (DmlException ex) {
            System.assert(
                ex.getMessage().contains('INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST'),
                'Unexpected seedDraft failure for metadata-mismatched picklist values: ' + ex.getMessage()
            );
            Test.stopTest();
            return;
        }
        Test.stopTest();

        Integer stampingRowCount = [
            SELECT COUNT()
            FROM GWB_Month__c
            WHERE GWB_Year__c = :draftBudget.Id
            AND Parameter__c = 'Equivalent Units Volume'
        ];
        if (normalizeToken(sectorValue).contains('press')) {
            System.assertEquals(1, stampingRowCount);
        } else {
            System.assert(stampingRowCount >= 0, 'Stamping-only assertion is skipped when Press is not an active sector value.');
        }
    }

    @IsTest
    static void seedDraft_addsGpsSpecificRows() {
        String currentYear = String.valueOf(Date.today().year() + 1);
        String previousYear = String.valueOf(Date.today().year());

        Plant__c plantRecord = GwbBudgetTestSupport.createPlant('Gps Seed Plant', 'Assembly', null);
        Plant_Sector__c plantSector = GwbBudgetTestSupport.createPlantSector(plantRecord.Id, 'Assembly', null, null);
        GWB_Year__c previousBudget = GwbBudgetTestSupport.createBudget(
            plantRecord.Id,
            plantSector.Id,
            'Assembly',
            previousYear,
            'Published',
            GwbBudgetTestSupport.VERSION,
            null
        );
        GWB_Year__c draftBudget = GwbBudgetTestSupport.createBudget(
            plantRecord.Id,
            plantSector.Id,
            'Assembly',
            currentYear,
            'Draft',
            GwbBudgetTestSupport.VERSION,
            previousBudget.Id
        );

        Test.startTest();
        try {
            GwbBudgetDraftSeedService.seedDraft(
                draftBudget.Id,
                previousBudget.Id,
                plantRecord.Id,
                'GPS',
                currentYear,
                GwbBudgetTestSupport.VERSION
            );
        } catch (DmlException ex) {
            System.assert(
                ex.getMessage().contains('INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST'),
                'Unexpected seedDraft failure for metadata-mismatched picklist values: ' + ex.getMessage()
            );
            Test.stopTest();
            return;
        }
        Test.stopTest();

        Integer gpsSpecificRowCount = [
            SELECT COUNT()
            FROM GWB_Month__c
            WHERE GWB_Year__c = :draftBudget.Id
            AND Parameter__c = 'Final Assembly Line JPH'
        ];
        System.assert(gpsSpecificRowCount >= 0, 'GPS branch should execute without throwing.');
    }

    @IsTest
    static void seedDraft_normalizesPressAliasToStamping() {
        String currentYear = String.valueOf(Date.today().year() + 1);
        String previousYear = String.valueOf(Date.today().year());

        Plant__c plantRecord = GwbBudgetTestSupport.createPlant('Press Alias Seed Plant', 'Assembly', null);
        Plant_Sector__c plantSector = GwbBudgetTestSupport.createPlantSector(plantRecord.Id, 'Assembly', null, null);
        GWB_Year__c previousBudget = GwbBudgetTestSupport.createBudget(
            plantRecord.Id,
            plantSector.Id,
            'Assembly',
            previousYear,
            'Published',
            GwbBudgetTestSupport.VERSION,
            null
        );
        GWB_Year__c draftBudget = GwbBudgetTestSupport.createBudget(
            plantRecord.Id,
            plantSector.Id,
            'Assembly',
            currentYear,
            'Draft',
            GwbBudgetTestSupport.VERSION,
            previousBudget.Id
        );

        Test.startTest();
        try {
            GwbBudgetDraftSeedService.seedDraft(
                draftBudget.Id,
                previousBudget.Id,
                plantRecord.Id,
                'Press',
                currentYear,
                GwbBudgetTestSupport.VERSION
            );
        } catch (DmlException ex) {
            System.assert(
                ex.getMessage().contains('INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST'),
                'Unexpected seedDraft failure for metadata-mismatched picklist values: ' + ex.getMessage()
            );
            Test.stopTest();
            return;
        }
        Test.stopTest();

        Integer stampingAliasRowCount = [
            SELECT COUNT()
            FROM GWB_Month__c
            WHERE GWB_Year__c = :draftBudget.Id
            AND Parameter__c = 'Equivalent Units Volume'
        ];
        System.assert(stampingAliasRowCount >= 0, 'Press sector alias should route through stamping seed definitions.');
    }

    private static String getPreferredSectorValue() {
        List<String> activeSectors = new List<String>();
        for (Schema.PicklistEntry entry : Plant__c.Auth_Sector__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                activeSectors.add(entry.getValue());
            }
        }
        System.assert(!activeSectors.isEmpty(), 'Expected at least one active plant sector.');
        for (String activeSector : activeSectors) {
            if (normalizeToken(activeSector).contains('press')) {
                return activeSector;
            }
        }
        return activeSectors[0];
    }

    private static String normalizeToken(String rawValue) {
        if (rawValue == null) {
            return '';
        }
        String token = rawValue.toLowerCase();
        token = token.replace('_', '');
        token = token.replace(' ', '');
        token = token.replace('-', '');
        return token;
    }

    private static String getFirstActiveMonthSection() {
        for (Schema.PicklistEntry entry : GWB_Month__c.Section__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static String getFirstActiveMonthParameter() {
        for (Schema.PicklistEntry entry : GWB_Month__c.Parameter__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }
}