@IsTest
private class DraftTargetCloneBatchTest {
    private static Id getTargetRecordTypeId() {
        Schema.RecordTypeInfo recordTypeInfo = GWB_Year__c.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName()
            .get('Target');
        System.assertNotEquals(null, recordTypeInfo, 'Target record type must exist for the test.');
        return recordTypeInfo.getRecordTypeId();
    }

    private static Plant__c createPlant() {
        Plant__c plantRecord = new Plant__c(
            Name = 'Test Plant',
            Auth_Region__c = 'GMNA',
            MVP__c = UserInfo.getUserId(),
            Auth_Sector__c = 'Assembly'
        );
        insert plantRecord;
        return plantRecord;
    }

    private static Plant_Sector__c createPlantSector(Id plantId) {
        Plant_Sector__c plantSector = new Plant_Sector__c(
            Plant__c = plantId
        );
        insert plantSector;
        return plantSector;
    }

    private static GWB_Year__c createTarget(Id plantId, Id plantSectorId) {
        GWB_Year__c targetRecord = new GWB_Year__c(
            Plant__c = plantId,
            Plant_Sector__c = plantSectorId,
            Sector__c = 'Assembly',
            Year__c = String.valueOf(Date.today().year() + 1),
            Version__c = getTestVersion(),
            M_Schedule_Version__c = getTestVersion(),
            Status__c = 'Finance Approved',
            RecordTypeId = getTargetRecordTypeId()
        );
        insert targetRecord;
        return targetRecord;
    }

    @IsTest
    static void enqueueCloneDraftTargets_queuesBackgroundJob() {
        Plant__c plantRecord = createPlant();
        Plant_Sector__c plantSector = createPlantSector(plantRecord.Id);
        String sourceVersion = getTestVersion();
        GWB_Year__c sourceTarget = createTarget(plantRecord.Id, plantSector.Id);
        String cloneVersion = getAlternateTestVersion(sourceVersion);

        GWB_Month__c monthRow = new GWB_Month__c(
            GWB_Year__c = sourceTarget.Id,
            Plant__c = plantRecord.Id,
            Sector__c = 'Assembly',
            Year__c = sourceTarget.Year__c,
            Data_Point_Value__c = getTestVersion(),
            Section__c = 'Headcount',
            Parameter__c = 'Base Headcount',
            Jan_Number__c = 1,
            Feb_Number__c = 2,
            Mar_Number__c = 3,
            Apr_Number__c = 4,
            May_Number__c = 5,
            Jun_Number__c = 6,
            Jul_Number__c = 7,
            Aug_Number__c = 8,
            Sep_Number__c = 9,
            Oct_Number__c = 10,
            Nov_Number__c = 11,
            Dec_Number__c = 12
        );
        insert monthRow;

        GWB_Budget_Comment__c commentRow = new GWB_Budget_Comment__c(
            GWB_Year__c = sourceTarget.Id,
            Cell_Key__c = 'cell-1',
            Classification__c = 'Planning',
            Comment_Text__c = 'Copy me',
            Month_Key__c = 'jan',
            Row_Key__c = 'row-1',
            Row_Label__c = 'Row 1',
            Table_Name__c = 'Test Table',
            Value_Snapshot__c = '1'
        );
        insert commentRow;

        Test.startTest();
        DraftTargetController.EnqueueCloneTargetResult result =
            DraftTargetController.enqueueCloneDraftTargets(
                new List<Id>{ sourceTarget.Id },
                cloneVersion == null ? sourceVersion : cloneVersion
            );
        Test.stopTest();

        if (cloneVersion == null) {
            System.assertEquals(null, result.jobId, 'No distinct version exists, so no clone job should be queued.');
            System.assertEquals(0, result.submittedCount, 'No targets should be submitted when only one active version exists.');
            return;
        }

        System.assertNotEquals(null, result.jobId, 'Clone job should be queued.');
        System.assertEquals(1, result.submittedCount, 'One target should be queued for cloning.');

        List<GWB_Year__c> clonedTargets = [
            SELECT Id, Status__c, M_Schedule_Version__c, Version__c, Plant__c, Plant_Sector__c, Sector__c
            FROM GWB_Year__c
            WHERE Id != :sourceTarget.Id
            AND Plant__c = :plantRecord.Id
            AND Plant_Sector__c = :plantSector.Id
            ORDER BY CreatedDate DESC
        ];
        System.assert(!clonedTargets.isEmpty(), 'A cloned target should be created.');
        System.assertEquals('Draft', clonedTargets[0].Status__c);
        System.assertEquals(cloneVersion, clonedTargets[0].M_Schedule_Version__c);

        List<GWB_Budget_Comment__c> clonedComments = [
            SELECT Id, Comment_Text__c, GWB_Year__c
            FROM GWB_Budget_Comment__c
            WHERE GWB_Year__c = :clonedTargets[0].Id
        ];
        System.assertEquals(1, clonedComments.size(), 'Comments should be cloned.');
        System.assertEquals('Copy me', clonedComments[0].Comment_Text__c);
    }

    @IsTest
    static void draftTargetCloneBatch_tracksFailuresWhenCloneThrows() {
        Plant__c plantRecord = createPlant();
        Plant_Sector__c plantSector = createPlantSector(plantRecord.Id);
        GWB_Year__c sourceTarget = createTarget(plantRecord.Id, plantSector.Id);

        Test.startTest();
        Id batchJobId = Database.executeBatch(
            new DraftTargetCloneBatch(
                new List<Id>{ sourceTarget.Id },
                '',
                UserInfo.getUserId()
            ),
            1
        );
        Test.stopTest();

        System.assertNotEquals(null, batchJobId, 'Batch job id should be returned.');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM GWB_Year__c WHERE Id = :sourceTarget.Id],
            'The source target remains unchanged when clone processing fails.'
        );
    }

    @IsTest
    static void draftTargetCloneBatch_skipsEmailWhenInitiatorMissing() {
        String versionValue = getTestVersion();

        Test.startTest();
        Id batchJobId = Database.executeBatch(
            new DraftTargetCloneBatch(
                null,
                versionValue,
                null
            ),
            1
        );
        Test.stopTest();

        System.assertNotEquals(null, batchJobId, 'Batch job id should be returned.');
        System.assertEquals(0, Limits.getEmailInvocations(), 'Email should be skipped when initiator is null.');
    }

    private static String getTestVersion() {
        for (Schema.PicklistEntry entry : GWB_Year__c.M_Schedule_Version__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        System.assert(false, 'Expected an active M-Schedule Version value.');
        return null;
    }

    private static String getAlternateTestVersion(String excludedVersion) {
        for (Schema.PicklistEntry entry : GWB_Year__c.M_Schedule_Version__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() != excludedVersion) {
                return entry.getValue();
            }
        }
        return null;
    }
}