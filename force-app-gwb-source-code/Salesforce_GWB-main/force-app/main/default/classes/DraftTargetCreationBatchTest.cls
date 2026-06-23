@IsTest
private class DraftTargetCreationBatchTest {
    @TestSetup
    static void setupValidationBypass() {
        Schema.SObjectType bypassType = Schema.getGlobalDescribe().get('Onstar_Switch__c');
        if (bypassType == null) {
            return;
        }
        SObject bypass = bypassType.newSObject();
        bypass.put('SetupOwnerId', UserInfo.getUserId());
        bypass.put('Bypass_VRs__c', true);
        insert bypass;
    }

    @IsTest
    static void batchProcessesValidPlantSectorAndCompletes() {
        Plant__c plantRecord = createPlantWithMvp('Batch Valid Plant', 'Assembly');
        Plant_Sector__c plantSector = GwbBudgetTestSupport.createPlantSector(plantRecord.Id, 'Assembly', null, null);

        Test.startTest();
        Id jobId = Database.executeBatch(
            new DraftTargetCreationBatch(
                new List<Id>{ plantSector.Id },
                getTestVersion(),
                UserInfo.getUserId()
            ),
            1
        );
        Test.stopTest();

        AsyncApexJob job = [
            SELECT Id, Status
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];
        System.assertEquals('Completed', job.Status, 'Batch should complete successfully.');
        System.assert(
            [SELECT COUNT() FROM GWB_Year__c WHERE Plant_Sector__c = :plantSector.Id] > 0,
            'Expected processing to create at least one target/budget year record.'
        );
    }

    @IsTest
    static void batchHandlesFailureMessagesForIncompletePlantSector() {
        Plant__c plantRecord = createPlantWithMvp('Batch Incomplete Plant', null);
        Plant_Sector__c incompleteSector = new Plant_Sector__c(Plant__c = plantRecord.Id);
        insert incompleteSector;

        Test.startTest();
        Id jobId = Database.executeBatch(
            new DraftTargetCreationBatch(
                new List<Id>{ incompleteSector.Id },
                getTestVersion(),
                UserInfo.getUserId()
            ),
            1
        );
        Test.stopTest();

        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];
        System.assertEquals('Completed', job.Status, 'Batch should complete even when a row fails processing.');
        System.assertEquals(0, job.NumberOfErrors, 'Service-level failures should be captured as messages, not batch errors.');
    }

    @IsTest
    static void batchSkipsEmailWhenInitiatorIsNull() {
        Test.startTest();
        Id jobId = Database.executeBatch(
            new DraftTargetCreationBatch(new List<Id>(), getTestVersion(), null),
            1
        );
        Test.stopTest();

        AsyncApexJob job = [
            SELECT Id, Status
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];
        System.assertEquals('Completed', job.Status, 'Batch should complete with no selected plant sectors.');
    }

    @IsTest
    static void batchSkipsEmailWhenInitiatorDoesNotExist() {
        Test.startTest();
        Id jobId = Database.executeBatch(
            new DraftTargetCreationBatch(new List<Id>(), getTestVersion(), Id.valueOf('005000000000000AAA')),
            1
        );
        Test.stopTest();

        AsyncApexJob job = [
            SELECT Id, Status
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];
        System.assertEquals('Completed', job.Status, 'Batch should complete when initiator user cannot be found.');
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

    private static Plant__c createPlantWithMvp(String name, String authSector) {
        String authRegion = null;
        for (Schema.PicklistEntry entry : Plant__c.Auth_Region__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                authRegion = entry.getValue();
                break;
            }
        }
        Plant__c plantRecord = new Plant__c(
            Name = name,
            Auth_Region__c = authRegion,
            Auth_Sector__c = authSector,
            MVP__c = UserInfo.getUserId()
        );
        insert plantRecord;
        return plantRecord;
    }
}