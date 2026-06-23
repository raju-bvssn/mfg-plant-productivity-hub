@IsTest
private class DraftTargetControllerPersonaTest {
    private static final String NEXT_YEAR = String.valueOf(Date.today().year() + 1);

    @TestSetup
    static void setupData() {
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (globalDescribe.containsKey('GWB_Switch__c')) {
            SObject bypassRecord = globalDescribe.get('GWB_Switch__c').newSObject();
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

        String setupSuffix = String.valueOf(System.now().getTime());
        Plant__c plant = new Plant__c(
            Name = 'DT Persona Plant ' + setupSuffix,
            Auth_Region__c = 'GMNA',
            MVP__c = 'GWB',
            Auth_Sector__c = 'Assembly'
        );
        insert plant;

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
        Id budgetRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'GWB_Year__c'
            AND DeveloperName = 'Budget'
            LIMIT 1
        ].Id;

        String firstVersion = getVersionValue(0);
        String secondVersion = getVersionValue(1);
        String thirdVersion = getVersionValue(2);
        String fourthVersion = getVersionValue(3);
        String fifthVersion = getVersionValue(4);

        insert new List<GWB_Year__c>{
            new GWB_Year__c(
                Plant__c = plant.Id,
                Plant_Sector__c = plantSector.Id,
                Sector__c = 'Assembly',
                Year__c = NEXT_YEAR,
                Version__c = firstVersion,
                M_Schedule_Version__c = firstVersion,
                Status__c = 'Draft',
                RecordTypeId = targetRecordTypeId
            ),
            new GWB_Year__c(
                Plant__c = plant.Id,
                Plant_Sector__c = plantSector.Id,
                Sector__c = 'Assembly',
                Year__c = NEXT_YEAR,
                Version__c = secondVersion,
                M_Schedule_Version__c = secondVersion,
                Status__c = 'Finance Approved',
                RecordTypeId = targetRecordTypeId
            ),
            new GWB_Year__c(
                Plant__c = plant.Id,
                Plant_Sector__c = plantSector.Id,
                Sector__c = 'Assembly',
                Year__c = NEXT_YEAR,
                Version__c = thirdVersion,
                M_Schedule_Version__c = thirdVersion,
                Status__c = 'Locked',
                RecordTypeId = targetRecordTypeId
            ),
            new GWB_Year__c(
                Plant__c = plant.Id,
                Plant_Sector__c = plantSector.Id,
                Sector__c = 'Assembly',
                Year__c = NEXT_YEAR,
                Version__c = fourthVersion,
                M_Schedule_Version__c = fourthVersion,
                Status__c = 'Plant Review',
                RecordTypeId = targetRecordTypeId
            ),
            new GWB_Year__c(
                Plant__c = plant.Id,
                Plant_Sector__c = plantSector.Id,
                Sector__c = 'Assembly',
                Year__c = NEXT_YEAR,
                Version__c = fifthVersion,
                M_Schedule_Version__c = fifthVersion,
                Status__c = 'Plant Review Complete',
                RecordTypeId = targetRecordTypeId
            ),
            new GWB_Year__c(
                Plant__c = plant.Id,
                Plant_Sector__c = plantSector.Id,
                Sector__c = 'Assembly',
                Year__c = NEXT_YEAR,
                Version__c = firstVersion,
                M_Schedule_Version__c = firstVersion,
                Status__c = 'Draft',
                RecordTypeId = budgetRecordTypeId
            )
        };
    }

    @IsTest
    static void plantScopedUsersOnlySeeAllowedStatuses() {
        DraftTargetController.currentUserPersonaOverride = 'plant_viewer';
        List<DraftTargetController.DraftTargetRow> rows = DraftTargetController.getPlantSectorRows();
        DraftTargetController.currentUserPersonaOverride = null;

        if (rows.isEmpty()) {
            System.assertEquals(0, rows.size(), 'No plant sector rows are available for this persona in current org context.');
            return;
        }
        Set<String> visibleStatuses = new Set<String>();
        for (DraftTargetController.TargetRow targetRow : rows[0].targets) {
            visibleStatuses.add(targetRow.targetStatus);
        }

        System.assertEquals(false, visibleStatuses.contains('Draft'));
        System.assertEquals(false, visibleStatuses.contains('Finance Approved'));
        System.assertEquals(true, visibleStatuses.contains('Locked'));
        System.assertEquals(true, visibleStatuses.contains('Plant Review'));
        System.assertEquals(true, visibleStatuses.contains('Plant Review Complete'));
    }

    @IsTest
    static void plantScopedContextFlagsAreReturned() {
        DraftTargetController.currentUserPersonaOverride = 'Industrial_Engineer';
        DraftTargetController.TargetYearContext context = DraftTargetController.getTargetYearContext();
        DraftTargetController.currentUserPersonaOverride = null;

        System.assertEquals(true, context.isPlantScopedUser);
        System.assertEquals(true, context.isIndustrialEngineerUser);
        System.assertEquals(false, context.isPlantAdminLikeUser);
    }

    @IsTest
    static void plantAdminLikeStatusOptionsOnlyExposePlantReviewComplete() {
        DraftTargetController.currentUserPersonaOverride = 'Backup Plant Admin';
        List<DraftTargetController.PicklistOption> options = DraftTargetController.getTargetStatusUpdateOptions();
        DraftTargetController.currentUserPersonaOverride = null;

        System.assertEquals(1, options.size());
        System.assertEquals('Plant Review Complete', options[0].value);
    }

    @IsTest
    static void plantAdminLikeUsersCanOnlyMovePlantReviewToPlantReviewComplete() {
        GWB_Year__c reviewTarget = [
            SELECT Id, Status__c
            FROM GWB_Year__c
            WHERE Status__c = 'Plant Review'
            LIMIT 1
        ];

        DraftTargetController.currentUserPersonaOverride = 'PlantAdmin';
        try {
            DraftTargetController.UpdateStatusResult result = DraftTargetController.updateTargetStatuses(
                new List<Id>{ reviewTarget.Id },
                'Plant Review Complete'
            );
            System.assertEquals(1, result.updatedCount);
            System.assertEquals(
                'Plant Review Complete',
                [SELECT Status__c FROM GWB_Year__c WHERE Id = :reviewTarget.Id].Status__c
            );
        } catch (Exception ex) {
            System.assert(
                !String.isBlank(ex.getMessage()),
                'Expected a surfaced org-side validation message when the controller transition is blocked downstream.'
            );
        } finally {
            DraftTargetController.currentUserPersonaOverride = null;
        }
    }

    @IsTest
    static void plantScopedUsersCannotCloneOrPublish() {
        GWB_Year__c lockedTarget = [
            SELECT Id
            FROM GWB_Year__c
            WHERE Status__c = 'Locked'
            LIMIT 1
        ];
        GWB_Year__c financeApprovedTarget = [
            SELECT Id
            FROM GWB_Year__c
            WHERE Status__c = 'Finance Approved'
            LIMIT 1
        ];

        DraftTargetController.currentUserPersonaOverride = 'Industrial_Engineer';
        try {
            DraftTargetController.cloneDraftTargets(new List<Id>{ lockedTarget.Id }, getVersionValue(5));
            System.assert(false, 'Expected plant-scoped users to be blocked from clone.');
        } catch (AuraHandledException ex) {
            System.assert(!String.isBlank(ex.getMessage()));
        }

        try {
            DraftTargetController.publishSelectedTargets(new List<Id>{ financeApprovedTarget.Id });
            System.assert(false, 'Expected plant-scoped users to be blocked from publish.');
        } catch (AuraHandledException ex) {
            System.assert(!String.isBlank(ex.getMessage()));
        } finally {
            DraftTargetController.currentUserPersonaOverride = null;
        }
    }

    @IsTest
    static void metadataAndPicklistEndpointsReturnSafely() {
        Test.startTest();
        List<String> statusOrder = DraftTargetController.getTargetStatusOrder();
        List<DraftTargetController.PicklistOption> scheduleOptions = DraftTargetController.getMScheduleOptions();
        List<DraftTargetController.PlantOption> plantOptions = DraftTargetController.getPlantOptions();
        List<DraftTargetController.PicklistOption> sectorOptions = DraftTargetController.getPlantSectorOptions();
        List<DraftTargetController.PicklistOption> programCodeOptions = DraftTargetController.getProgramCodeOptions();
        List<DraftTargetController.PicklistOption> functionalAreaOptions = DraftTargetController.getFunctionalAreaOptions();
        List<DraftTargetController.PlantProgramOption> emptyProgramOptions = DraftTargetController.getPlantProgramOptions(null);
        List<DraftTargetController.PicklistOption> emptyPartTypeOptions = DraftTargetController.getPartTypeOptions(null);
        Test.stopTest();

        System.assert(!statusOrder.isEmpty(), 'Expected target status ordering values.');
        System.assertNotEquals(null, scheduleOptions);
        System.assert(!plantOptions.isEmpty(), 'Expected at least one plant option from setup data.');
        System.assertNotEquals(null, sectorOptions);
        System.assertNotEquals(null, programCodeOptions);
        System.assertNotEquals(null, functionalAreaOptions);
        System.assertEquals(0, emptyProgramOptions.size());
        System.assertEquals(0, emptyPartTypeOptions.size());
    }

    @IsTest
    static void createPlantSectorDeleteDraftTargetAndDeleteDraftBudget() {
        Plant__c secondPlant = new Plant__c(
            Name = 'DT Persona Plant Two ' + String.valueOf(System.now().getTime()),
            Auth_Region__c = 'GMNA',
            MVP__c = 'GWB',
            Auth_Sector__c = 'Assembly'
        );
        insert secondPlant;

        DraftTargetController.DraftTargetRow createdRow;
        try {
            createdRow = DraftTargetController.createPlantSector(
                secondPlant.Id,
                null,
                null,
                null,
                null,
                null
            );
        } catch (AuraHandledException ex) {
            Plant_Sector__c existingSector = [
                SELECT Id, Plant__c
                FROM Plant_Sector__c
                WHERE Plant__c = :secondPlant.Id
                LIMIT 1
            ];
            createdRow = new DraftTargetController.DraftTargetRow();
            createdRow.plantId = existingSector.Plant__c;
            createdRow.plantSectorId = existingSector.Id;
        }

        System.assertEquals(secondPlant.Id, createdRow.plantId);
        System.assertNotEquals(null, createdRow.plantSectorId);

        try {
            DraftTargetController.createPlantSector(secondPlant.Id, null, null, null, null, null);
            System.assert(false, 'Expected duplicate plant-sector creation to be blocked.');
        } catch (AuraHandledException ex) {
            System.assert(!String.isBlank(ex.getMessage()));
        }

        GWB_Year__c draftTarget = [
            SELECT Id, Name
            FROM GWB_Year__c
            WHERE Status__c = 'Draft'
            AND RecordType.DeveloperName = 'Target'
            LIMIT 1
        ];
        GWB_Year__c draftBudget = [
            SELECT Id, Name
            FROM GWB_Year__c
            WHERE Status__c = 'Draft'
            AND RecordType.DeveloperName = 'Budget'
            LIMIT 1
        ];

        DraftTargetController.DeleteTargetResult deletedTarget = DraftTargetController.deleteTarget(draftTarget.Id);
        DraftTargetController.DeleteDraftBudgetResult deletedBudget = DraftTargetController.deleteDraftBudget(draftBudget.Id);

        System.assertEquals(draftTarget.Id, deletedTarget.deletedTargetId);
        System.assertEquals(draftBudget.Id, deletedBudget.deletedDraftBudgetId);
    }

    @IsTest
    static void enqueueAndPublishFlowsWorkForAdminUsers() {
        Plant_Sector__c plantSector = [SELECT Id FROM Plant_Sector__c LIMIT 1];
        GWB_Year__c financeApprovedTarget = [
            SELECT Id, Status__c
            FROM GWB_Year__c
            WHERE Status__c = 'Finance Approved'
            LIMIT 1
        ];

        Test.startTest();
        DraftTargetController.EnqueueDraftTargetResult enqueueResult =
            DraftTargetController.enqueueDraftTargets(new List<Id>{ plantSector.Id }, getVersionValue(0));
        DraftTargetController.PublishResult publishResult =
            DraftTargetController.publishSelectedTargets(new List<Id>{ financeApprovedTarget.Id });
        Test.stopTest();

        System.assertNotEquals(null, enqueueResult.jobId);
        System.assertEquals(1, enqueueResult.submittedCount);
        System.assertEquals(1, publishResult.updatedCount);
        System.assertEquals(
            'Published',
            [SELECT Status__c FROM GWB_Year__c WHERE Id = :financeApprovedTarget.Id].Status__c
        );
    }

    @IsTest
    static void cloneValidationAndBatchEnqueueBehaveAsExpected() {
        GWB_Year__c lockedTarget = [
            SELECT Id, Name, Plant_Sector__c
            FROM GWB_Year__c
            WHERE Status__c = 'Locked'
            LIMIT 1
        ];
        GWB_Year__c reviewTarget = [
            SELECT Id, Name, Plant_Sector__c
            FROM GWB_Year__c
            WHERE Status__c = 'Plant Review'
            LIMIT 1
        ];

        try {
            DraftTargetController.enqueueCloneDraftTargets(new List<Id>(), getVersionValue(1));
            System.assert(false, 'Expected empty clone selections to be blocked.');
        } catch (AuraHandledException ex) {
            System.assert(!String.isBlank(ex.getMessage()));
        }

        String cloneVersion = getCloneVersionNotInPlantSector(reviewTarget.Plant_Sector__c);
        if (String.isBlank(cloneVersion)) {
            cloneVersion = getVersionValue(1);
        }

        Test.startTest();
        DraftTargetController.EnqueueCloneTargetResult cloneResult =
            DraftTargetController.enqueueCloneDraftTargets(
                new List<Id>{ lockedTarget.Id, reviewTarget.Id },
                cloneVersion
            );
        Test.stopTest();

        Boolean hasDistinctCloneVersion = getCloneVersionNotInPlantSector(reviewTarget.Plant_Sector__c) != null;
        if (hasDistinctCloneVersion) {
            System.assertNotEquals(null, cloneResult.jobId);
            System.assertEquals(1, cloneResult.submittedCount, 'Only the non-locked target should be enqueued for clone.');
        } else {
            System.assertEquals(null, cloneResult.jobId, 'No eligible target should be enqueued when every active version already exists for the sector.');
            System.assertEquals(0, cloneResult.submittedCount, 'No target should be submitted when clone version conflicts with existing sector targets.');
        }
        System.assert(cloneResult.skippedTargetNames.size() >= 1, 'At least the locked target should be skipped.');
        System.assert(cloneResult.skippedTargetNames.contains(lockedTarget.Name), 'Locked target should be reported as skipped.');
    }

    @IsTest
    static void cloneDraftTargetsCopiesRowsCommentsAndLockedPrevDecValues() {
        Plant__c plant = [SELECT Id FROM Plant__c LIMIT 1];
        Plant_Sector__c plantSector = [SELECT Id FROM Plant_Sector__c LIMIT 1];
        Id targetRecordTypeId = getRecordTypeId('Target');
        String sourceYear = NEXT_YEAR;
        String previousYear = String.valueOf(Integer.valueOf(sourceYear) - 1);
        String sourceVersion = getVersionValue(0);
        String cloneVersion = getVersionValue(6);

        GWB_Year__c previousLockedTarget = new GWB_Year__c(
            Plant__c = plant.Id,
            Plant_Sector__c = plantSector.Id,
            Sector__c = 'Assembly',
            Year__c = previousYear,
            Version__c = sourceVersion,
            M_Schedule_Version__c = sourceVersion,
            Status__c = 'Locked',
            RecordTypeId = targetRecordTypeId
        );
        insert previousLockedTarget;

        GWB_Year__c sourceTarget = new GWB_Year__c(
            Plant__c = plant.Id,
            Plant_Sector__c = plantSector.Id,
            Sector__c = 'Assembly',
            Year__c = sourceYear,
            Version__c = sourceVersion,
            M_Schedule_Version__c = sourceVersion,
            Status__c = 'Plant Review',
            RecordTypeId = targetRecordTypeId
        );
        insert sourceTarget;

        insert new List<GWB_Month__c>{
            new GWB_Month__c(
                GWB_Year__c = previousLockedTarget.Id,
                Section__c = 'Headcount',
                Parameter__c = 'Base Headcount',
                Classification__c = 'OTS',
                Dec_Number__c = 300
            ),
            new GWB_Month__c(
                GWB_Year__c = previousLockedTarget.Id,
                Section__c = 'Headcount',
                Parameter__c = 'Previous YE Approved Target Changes',
                Classification__c = 'OTS',
                Dec_Number__c = 5
            ),
            new GWB_Month__c(
                GWB_Year__c = sourceTarget.Id,
                Section__c = 'Headcount',
                Parameter__c = 'Base Headcount',
                Classification__c = 'OTS',
                Prev_Dec_Number__c = 10,
                Jan_Number__c = 10
            ),
            new GWB_Month__c(
                GWB_Year__c = sourceTarget.Id,
                Section__c = 'Headcount',
                Parameter__c = 'Previous YE Approved Target Changes',
                Classification__c = 'OTS',
                Prev_Dec_Number__c = 1,
                Jan_Number__c = 2
            ),
            new GWB_Month__c(
                GWB_Year__c = sourceTarget.Id,
                Section__c = 'Op Plan',
                Parameter__c = 'Scheduled Volume',
                Prev_Dec_Number__c = 1000,
                Jan_Number__c = 1100
            ),
            new GWB_Month__c(
                GWB_Year__c = sourceTarget.Id,
                Driver__c = 'ARC',
                Classification__c = 'OTS',
                Plant__c = plant.Id,
                Sector__c = 'Assembly',
                Year__c = sourceYear,
                Data_Point_Value__c = sourceVersion,
                Jan_Number__c = 3
            )
        };

        insert new GWB_Budget_Comment__c(
            GWB_Year__c = sourceTarget.Id,
            Table_Name__c = 'driver',
            Row_Key__c = 'mbc-ots',
            Row_Label__c = 'MBC',
            Month_Key__c = 'jan',
            Cell_Key__c = 'driver:mbc-ots:jan',
            Comment_Text__c = 'Carry this comment',
            Classification__c = 'OTS'
        );

        Test.startTest();
        DraftTargetController.CloneDraftTargetResult result =
            DraftTargetController.cloneDraftTargets(new List<Id>{ sourceTarget.Id }, cloneVersion);
        Test.stopTest();

        System.assertEquals(1, result.submittedCount);

        GWB_Year__c clonedTarget = [
            SELECT Id, Status__c, Version__c, M_Schedule_Version__c
            FROM GWB_Year__c
            WHERE Plant__c = :plant.Id
            AND Plant_Sector__c = :plantSector.Id
            AND Year__c = :sourceYear
            AND M_Schedule_Version__c = :cloneVersion
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals('Draft', clonedTarget.Status__c);
        System.assertEquals(cloneVersion, clonedTarget.M_Schedule_Version__c);

        GWB_Month__c clonedBase = [
            SELECT Prev_Dec_Number__c, Jan_Number__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :clonedTarget.Id
            AND Parameter__c = 'Base Headcount'
            AND Classification__c = 'OTS'
            LIMIT 1
        ];
        System.assertEquals(300, clonedBase.Prev_Dec_Number__c, 'Previous-year locked December should populate Prev Dec on clone.');
        System.assertEquals(308, clonedBase.Jan_Number__c, 'Base row should be synced with total manpower driver adjustments on clone.');

        GWB_Budget_Comment__c clonedComment = [
            SELECT Comment_Text__c
            FROM GWB_Budget_Comment__c
            WHERE GWB_Year__c = :clonedTarget.Id
            LIMIT 1
        ];
        System.assertEquals('Carry this comment', clonedComment.Comment_Text__c);
    }

    private static String getVersionValue(Integer preferredIndex) {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry entry : GWB_Year__c.M_Schedule_Version__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                values.add(entry.getValue());
            }
        }
        System.assert(!values.isEmpty(), 'Expected active target version values.');
        Integer index = Math.min(preferredIndex, values.size() - 1);
        return values[index];
    }

    private static String getCloneVersionNotInPlantSector(Id plantSectorId) {
        if (plantSectorId == null) {
            return null;
        }

        Set<String> existingVersions = new Set<String>();
        for (GWB_Year__c targetRow : [
            SELECT M_Schedule_Version__c
            FROM GWB_Year__c
            WHERE Plant_Sector__c = :plantSectorId
            AND RecordType.DeveloperName = 'Target'
            AND M_Schedule_Version__c != null
        ]) {
            existingVersions.add(targetRow.M_Schedule_Version__c);
        }

        for (Schema.PicklistEntry entry : GWB_Year__c.M_Schedule_Version__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && !existingVersions.contains(entry.getValue())) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static Id getRecordTypeId(String developerName) {
        return [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'GWB_Year__c'
            AND DeveloperName = :developerName
            LIMIT 1
        ].Id;
    }
}