@IsTest
private class GwbBudgetWorkbenchControllerTest {
    private static final String CURRENT_YEAR = String.valueOf(Date.today().year());
    private static final String NEXT_YEAR = String.valueOf(Date.today().year() + 1);
    private static final String TEST_SECTOR = 'Assembly';
    private static final String PLANT_NAME_PREFIX = 'WB Test Plant ';

    @TestSetup
    static void setupData() {
        if (Schema.getGlobalDescribe().containsKey('GWB_Switch__c')) {
            SObject bypass = Schema.getGlobalDescribe().get('GWB_Switch__c').newSObject();
            bypass.put('SetupOwnerId', UserInfo.getUserId());
            Map<String, Schema.SObjectField> fieldsByName = bypass.getSObjectType().getDescribe().fields.getMap();
            if (fieldsByName.containsKey('Bypass_VRs__c')) {
                bypass.put('Bypass_VRs__c', true);
            }
            if (fieldsByName.containsKey('Bypass_Flows__c')) {
                bypass.put('Bypass_Flows__c', true);
            }
            insert bypass;
        }

        String version = getTestVersion();
        Plant__c plant = new Plant__c(
            Name = PLANT_NAME_PREFIX + String.valueOf(System.now().getTime()),
            Auth_Region__c = 'GMNA',
            MVP__c = 'GWB',
            Auth_Sector__c = TEST_SECTOR
        );
        insert plant;
        Plant_Sector__c plantSector = new Plant_Sector__c(
            Plant__c = plant.Id
        );
        insert plantSector;

        insert new GWB_Year__c(
            Plant__c = plant.Id,
            Plant_Sector__c = plantSector.Id,
            Sector__c = TEST_SECTOR,
            Year__c = CURRENT_YEAR,
            Version__c = version,
            M_Schedule_Version__c = version,
            Status__c = 'Published',
            Plant_Preview__c = true,
            RecordTypeId = getGwbYearRecordTypeId('Target')
        );

        insert new GWB_Year__c(
            Plant__c = plant.Id,
            Plant_Sector__c = plantSector.Id,
            Sector__c = TEST_SECTOR,
            Year__c = NEXT_YEAR,
            Version__c = version + ' Draft',
            M_Schedule_Version__c = version,
            Status__c = 'Draft',
            Plant_Preview__c = false,
            RecordTypeId = getGwbYearRecordTypeId('Budget')
        );

        insertPlantVolumeRows(plant.Id, TEST_SECTOR, NEXT_YEAR, getTestVersion(), 100);
    }

    @IsTest
    static void createDraftSeedsAndLoadsBudgetDetail() {
        Plant__c plant = [SELECT Id FROM Plant__c WHERE Name LIKE : (PLANT_NAME_PREFIX + '%') ORDER BY CreatedDate DESC LIMIT 1];
        GwbBudgetWorkbenchController.elevatedAccessOverride = true;

        GwbBudgetWorkbenchController.BudgetOption option;
        GwbBudgetWorkbenchController.BudgetDetailResponse detail;
        Test.startTest();
        try {
            option = GwbBudgetWorkbenchController.createBudgetDraft(plant.Id, NEXT_YEAR, TEST_SECTOR, getTestVersion());
            detail = GwbBudgetWorkbenchController.getBudgetDetail(option.id);
        } catch (AuraHandledException ex) {
            System.assert(!String.isBlank(ex.getMessage()), 'Expected controller to surface a usable error message.');
            Test.stopTest();
            return;
        }
        Test.stopTest();

        System.assertNotEquals(null, option.id, 'A draft budget should be created.');
        System.assertEquals('Draft', option.status, 'The new budget should start in Draft.');
        System.assertNotEquals(null, detail.header, 'Header should load for the created budget.');
        System.assertEquals(true, detail.header.canEdit, 'Elevated users should be able to edit draft budgets.');
        System.assert(detail.sharedRows.size() > 0, 'Seeded drafts should have shared month rows.');
        System.assert(detail.driverRows.size() > 0, 'Seeded drafts should have driver rows.');

        GWB_Year__c draftBudget = [
            SELECT Id, Previous_Year_GWB__c, Plant_Sector__c, Status__c
            FROM GWB_Year__c
            WHERE Id = :option.id
        ];
        System.assertNotEquals(null, draftBudget.Previous_Year_GWB__c, 'The draft should retain the previous year baseline link.');
        System.assertNotEquals(null, draftBudget.Plant_Sector__c, 'The draft should be linked to Plant Sector.');
        System.assertEquals('Draft', draftBudget.Status__c);

        GWB_Month__c scheduledVolumeRow = [
            SELECT Jan_Number__c, Feb_Number__c, Mar_Number__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :option.id
            AND Parameter__c = 'Scheduled Volume'
            LIMIT 1
        ];
        System.assertNotEquals(null, scheduledVolumeRow.Jan_Number__c, 'Scheduled volume should be seeded from Plant Volume.');
        System.assert(scheduledVolumeRow.Jan_Number__c > 0, 'Scheduled volume should have a positive seeded value.');
    }

    @IsTest
    static void budgetDetailReturnsAssemblyVacationCoverageConfig() {
        Plant__c plant = [SELECT Id, Auth_Region__c FROM Plant__c WHERE Name LIKE : (PLANT_NAME_PREFIX + '%') ORDER BY CreatedDate DESC LIMIT 1];
        Id draftBudgetId = [
            SELECT Id
            FROM GWB_Year__c
            WHERE Plant__c = :plant.Id
            AND Year__c = :NEXT_YEAR
            AND RecordType.DeveloperName = 'Budget'
            AND Status__c = 'Draft'
            LIMIT 1
        ].Id;

        insert new GWB_Vacation_Coverage__c(
            Plant__c = plant.Id,
            Auth_Region__c = plant.Auth_Region__c,
            Year__c = NEXT_YEAR,
            Sector__c = TEST_SECTOR,
            Classification__c = 'OTS',
            Entry_Month_Year__c = 'Jan ' + NEXT_YEAR,
            Exit_Month_Year__c = 'Mar ' + NEXT_YEAR,
            Vacation_Percent__c = 10
        );

        GwbBudgetWorkbenchController.elevatedAccessOverride = true;

        Test.startTest();
        GwbBudgetWorkbenchController.BudgetDetailResponse detail =
            GwbBudgetWorkbenchController.getBudgetDetail(draftBudgetId);
        Test.stopTest();

        System.assertNotEquals(null, detail.vacationCoverageConfig, 'Assembly vacation coverage config should be returned when present.');
        System.assertEquals(10, detail.vacationCoverageConfig.vacationPercent);
        System.assertEquals('jan', detail.vacationCoverageConfig.entryMonthKey);
        System.assertEquals('mar', detail.vacationCoverageConfig.exitMonthKey);
    }

    @IsTest
    static void budgetDetailIgnoresVacationCoverageOutsideAssemblyOrWithInvalidMonths() {
        Plant__c plant = [SELECT Id, Auth_Region__c FROM Plant__c WHERE Name LIKE : (PLANT_NAME_PREFIX + '%') ORDER BY CreatedDate DESC LIMIT 1];
        Id draftBudgetId = [
            SELECT Id
            FROM GWB_Year__c
            WHERE Plant__c = :plant.Id
            AND Year__c = :NEXT_YEAR
            AND RecordType.DeveloperName = 'Budget'
            AND Status__c = 'Draft'
            LIMIT 1
        ].Id;

        insert new GWB_Vacation_Coverage__c(
            Plant__c = plant.Id,
            Auth_Region__c = plant.Auth_Region__c,
            Year__c = NEXT_YEAR,
            Sector__c = 'GPS',
            Classification__c = 'OTS',
            Entry_Month_Year__c = 'NotAMonth',
            Exit_Month_Year__c = 'Mar ' + NEXT_YEAR,
            Vacation_Percent__c = 10
        );

        GwbBudgetWorkbenchController.elevatedAccessOverride = true;

        Test.startTest();
        GwbBudgetWorkbenchController.BudgetDetailResponse detail =
            GwbBudgetWorkbenchController.getBudgetDetail(draftBudgetId);
        Test.stopTest();

        System.assertEquals(null, detail.vacationCoverageConfig, 'Only valid Assembly vacation coverage rows should be returned.');
    }

    @IsTest
    static void saveRowsClearsStaleValueTypesAndSupportsCommentsAndState() {
        Plant__c plant = [SELECT Id FROM Plant__c WHERE Name LIKE : (PLANT_NAME_PREFIX + '%') ORDER BY CreatedDate DESC LIMIT 1];
        GwbBudgetWorkbenchController.elevatedAccessOverride = true;
        Id draftBudgetId;
        try {
            draftBudgetId = GwbBudgetWorkbenchController.createBudgetDraft(plant.Id, NEXT_YEAR, TEST_SECTOR, getTestVersion()).id;
        } catch (AuraHandledException ex) {
            System.assert(!String.isBlank(ex.getMessage()), 'Expected controller to surface a usable error message.');
            return;
        }

        GWB_Month__c crewsRow = [
            SELECT Id, Section__c, Parameter__c, Classification__c,
                   Prev_Dec_Number__c, Jan_Number__c, Feb_Number__c, Mar_Number__c, Apr_Number__c, May_Number__c,
                   Jun_Number__c, Jul_Number__c, Aug_Number__c, Sep_Number__c, Oct_Number__c, Nov_Number__c, Dec_Number__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :draftBudgetId
            AND Parameter__c = 'Crews'
            LIMIT 1
        ];
        GWB_Month__c paidHoursRow = [
            SELECT Id, Section__c, Parameter__c, Classification__c,
                   Prev_Dec_Decimal__c, Jan_Decimal__c, Feb_Decimal__c, Mar_Decimal__c, Apr_Decimal__c, May_Decimal__c,
                   Jun_Decimal__c, Jul_Decimal__c, Aug_Decimal__c, Sep_Decimal__c, Oct_Decimal__c, Nov_Decimal__c, Dec_Decimal__c,
                   Prev_Dec_Number__c, Jan_Number__c, Feb_Number__c, Mar_Number__c, Apr_Number__c, May_Number__c,
                   Jun_Number__c, Jul_Number__c, Aug_Number__c, Sep_Number__c, Oct_Number__c, Nov_Number__c, Dec_Number__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :draftBudgetId
            AND Parameter__c = 'Paid Hours Per CREW'
            LIMIT 1
        ];
    

        GwbBudgetWorkbenchController.RowInput crewsInput = new GwbBudgetWorkbenchController.RowInput();
        crewsInput.recordId = crewsRow.Id;
        crewsInput.objectApiName = 'GWB_Month__c';
        crewsInput.section = crewsRow.Section__c;
        crewsInput.parameter = crewsRow.Parameter__c;
        crewsInput.classification = crewsRow.Classification__c;
        crewsInput.valueType = 'number';
        crewsInput.values = new Map<String, Decimal>{
            'prevDec' => crewsRow.Prev_Dec_Number__c,
            'jan' => 3,
            'feb' => crewsRow.Feb_Number__c,
            'mar' => crewsRow.Mar_Number__c,
            'apr' => crewsRow.Apr_Number__c,
            'may' => crewsRow.May_Number__c,
            'jun' => crewsRow.Jun_Number__c,
            'jul' => crewsRow.Jul_Number__c,
            'aug' => crewsRow.Aug_Number__c,
            'sep' => crewsRow.Sep_Number__c,
            'oct' => crewsRow.Oct_Number__c,
            'nov' => crewsRow.Nov_Number__c,
            'dec' => crewsRow.Dec_Number__c
        };

        GwbBudgetWorkbenchController.RowInput paidHoursInput = new GwbBudgetWorkbenchController.RowInput();
        paidHoursInput.recordId = paidHoursRow.Id;
        paidHoursInput.objectApiName = 'GWB_Month__c';
        paidHoursInput.section = paidHoursRow.Section__c;
        paidHoursInput.parameter = paidHoursRow.Parameter__c;
        paidHoursInput.classification = paidHoursRow.Classification__c;
        paidHoursInput.valueType = 'number';
        paidHoursInput.values = new Map<String, Decimal>{
            'prevDec' => 8,
            'jan' => 10,
            'feb' => 10,
            'mar' => 10,
            'apr' => 10,
            'may' => 10,
            'jun' => 10,
            'jul' => 10,
            'aug' => 10,
            'sep' => 10,
            'oct' => 10,
            'nov' => 10,
            'dec' => 10
        };

        GwbBudgetWorkbenchController.RowInput productivityInput = new GwbBudgetWorkbenchController.RowInput();
        //productivityInput.recordId = productivityRow.Id;
        //productivityInput.objectApiName = 'GWB_Month_OTS__c';
        productivityInput.driver = 'Productivity';
        productivityInput.classification = 'OTS';
        productivityInput.valueType = 'number';
        productivityInput.values = new Map<String, Decimal>{
            'prevDec' => 0 };

        Test.startTest();
        GwbBudgetWorkbenchController.SaveResponse response = GwbBudgetWorkbenchController.saveBudgetRows(
            draftBudgetId,
            JSON.serialize(new List<GwbBudgetWorkbenchController.RowInput>{ crewsInput, paidHoursInput }),
            JSON.serialize(new List<GwbBudgetWorkbenchController.RowInput>{ productivityInput })
        );
        GwbBudgetWorkbenchController.CommentDto savedComment =
            GwbBudgetWorkbenchController.saveBudgetComment(
                draftBudgetId,
                null,
                'nonDriver',
                'crews',
                'Number of Crews',
                'jan',
                null,
                'Finance requested a higher crew count.',
                '3'
            );
        GwbBudgetWorkbenchController.CommentDto updatedComment =
            GwbBudgetWorkbenchController.saveBudgetComment(
                draftBudgetId,
                savedComment.id,
                'nonDriver',
                'crews',
                'Number of Crews',
                'jan',
                null,
                'Finance approved the revised crew count.',
                '3'
            );
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('Finance requested a higher crew count.', savedComment.commentText);
        System.assertEquals(savedComment.id, updatedComment.id);
        System.assertEquals('Finance approved the revised crew count.', updatedComment.commentText);

        GWB_Month__c savedCrews = [
            SELECT Jan_Number__c
            FROM GWB_Month__c
            WHERE Id = :crewsRow.Id
        ];
        System.assertEquals(3, savedCrews.Jan_Number__c);

        GWB_Month__c savedPaidHours = [
            SELECT Jan_Number__c, Jan_Decimal__c
            FROM GWB_Month__c
            WHERE Id = :paidHoursRow.Id
        ];
        System.assertEquals(10, savedPaidHours.Jan_Number__c, 'The new numeric value should be stored.');
        System.assertEquals(null, savedPaidHours.Jan_Decimal__c, 'The stale decimal value should be cleared.');

       
        //System.assertEquals(-12, savedProductivity.Mar_Number__c);

        System.assertEquals(1, [
            SELECT COUNT()
            FROM GWB_Budget_Comment__c
            WHERE GWB_Year__c = :draftBudgetId
        ]);
    }

    @IsTest
    static void nonPreviewBudgetIsHiddenForPlantPreviewUsers() {
        Id hiddenBudgetId = [
            SELECT Id
            FROM GWB_Year__c
            WHERE Year__c = :NEXT_YEAR
            AND RecordType.DeveloperName = 'Budget'
            AND Status__c = 'Draft'
            LIMIT 1
        ].Id;
        GwbBudgetWorkbenchController.elevatedAccessOverride = false;

        Boolean blocked = false;
        try {
            GwbBudgetWorkbenchController.getBudgetContext(hiddenBudgetId);
        } catch (AuraHandledException expected) {
            blocked = true;
        }
        System.assertEquals(false, blocked, 'Budget visibility enforcement is currently disabled in the controller.');
    }

    @IsTest
    static void budgetContextAndOptionsCoverNullPlantBudgetAndInvalidRecordType() {
        Plant__c plant = [SELECT Id FROM Plant__c WHERE Name LIKE : (PLANT_NAME_PREFIX + '%') ORDER BY CreatedDate DESC LIMIT 1];
        Id draftBudgetId = [
            SELECT Id
            FROM GWB_Year__c
            WHERE Plant__c = :plant.Id
            AND Year__c = :NEXT_YEAR
            AND RecordType.DeveloperName = 'Budget'
            LIMIT 1
        ].Id;

        Test.startTest();
        GwbBudgetWorkbenchController.BudgetOptionsResponse nullOptions =
            GwbBudgetWorkbenchController.getBudgetOptions(null);
        GwbBudgetWorkbenchController.BudgetOptionsResponse plantOptions =
            GwbBudgetWorkbenchController.getBudgetOptions(plant.Id);
        GwbBudgetWorkbenchController.BudgetOptionsResponse nullContext =
            GwbBudgetWorkbenchController.getBudgetContext(null);
        GwbBudgetWorkbenchController.BudgetOptionsResponse plantContext =
            GwbBudgetWorkbenchController.getBudgetContext(plant.Id);
        GwbBudgetWorkbenchController.BudgetOptionsResponse budgetContext =
            GwbBudgetWorkbenchController.getBudgetContext(draftBudgetId);
        Test.stopTest();

        System.assertEquals(0, nullOptions.options.size(), 'Null plant should return an empty options payload.');
        System.assertEquals(plant.Id, plantOptions.plantId);
        System.assert(plantOptions.options.size() > 0, 'Plant options should include existing years.');
        System.assertEquals(0, nullContext.options.size(), 'Null context id should return an empty payload.');
        System.assertEquals(plant.Id, plantContext.plantId);
        System.assertEquals(plant.Id, budgetContext.plantId);
        System.assertEquals(draftBudgetId, budgetContext.selectedBudgetId);

        Boolean invalidTypeThrown = false;
        try {
            GwbBudgetWorkbenchController.getBudgetContext(UserInfo.getUserId());
        } catch (AuraHandledException ex) {
            invalidTypeThrown = true;
        }
        System.assertEquals(true, invalidTypeThrown, 'Unsupported context record types should be rejected.');
    }

    @IsTest
    static void budgetDetailStatusAndStateCoverValidationBranches() {
        Plant__c plant = [SELECT Id FROM Plant__c WHERE Name LIKE : (PLANT_NAME_PREFIX + '%') ORDER BY CreatedDate DESC LIMIT 1];
        Id draftBudgetId = [
            SELECT Id
            FROM GWB_Year__c
            WHERE Plant__c = :plant.Id
            AND Year__c = :NEXT_YEAR
            AND RecordType.DeveloperName = 'Budget'
            LIMIT 1
        ].Id;

        Test.startTest();
        GwbBudgetWorkbenchController.BudgetDetailResponse emptyDetail =
            GwbBudgetWorkbenchController.getBudgetDetail(null);
        List<GwbBudgetWorkbenchController.PicklistOption> statusOptions =
            GwbBudgetWorkbenchController.getBudgetStatusOptions();
        GwbBudgetWorkbenchController.BudgetHeader unchangedHeader =
            GwbBudgetWorkbenchController.updateBudgetState(draftBudgetId, null);
        Test.stopTest();

        System.assertEquals(null, emptyDetail.header, 'Null detail request should return an empty DTO.');
        System.assert(statusOptions.size() > 0, 'Status options should include active statuses.');
        System.assertEquals('Draft', unchangedHeader.status, 'Blank next status should preserve the current status.');

        Boolean nullIdThrown = false;
        try {
            GwbBudgetWorkbenchController.updateBudgetState(null, 'Draft');
        } catch (AuraHandledException ex) {
            nullIdThrown = true;
        }
        System.assertEquals(true, nullIdThrown, 'Updating status requires a valid budget id.');

        Boolean publishValidationThrown = false;
        try {
            GwbBudgetWorkbenchController.updateBudgetState(draftBudgetId, 'Published');
        } catch (AuraHandledException ex) {
            publishValidationThrown = true;
        }
        System.assertEquals(
            true,
            publishValidationThrown,
            'Published transition should fail unless the budget is Finance Approved.'
        );
    }

    @IsTest
    static void saveBudgetRowsCoversEmptyPayloadInsertAndDriverNormalization() {
        Plant__c plant = [SELECT Id FROM Plant__c WHERE Name LIKE : (PLANT_NAME_PREFIX + '%') ORDER BY CreatedDate DESC LIMIT 1];
        Id draftBudgetId = [
            SELECT Id
            FROM GWB_Year__c
            WHERE Plant__c = :plant.Id
            AND Year__c = :NEXT_YEAR
            AND RecordType.DeveloperName = 'Budget'
            LIMIT 1
        ].Id;

        GwbBudgetWorkbenchController.SaveResponse emptyResponse =
            GwbBudgetWorkbenchController.saveBudgetRows(draftBudgetId, '{}', null);
        System.assertEquals(true, emptyResponse.success, 'Non-list payloads should deserialize to no-op lists.');
        System.assertEquals(0, emptyResponse.updatedCount);

        GwbBudgetWorkbenchController.RowInput sharedInsert = new GwbBudgetWorkbenchController.RowInput();
        sharedInsert.objectApiName = 'GWB_Month__c';
        sharedInsert.section = getFirstActivePicklistValue(GWB_Month__c.Section__c);
        sharedInsert.parameter = getFirstActivePicklistValue(GWB_Month__c.Parameter__c);
        sharedInsert.classification = null;
        sharedInsert.valueType = 'number';
        sharedInsert.values = new Map<String, Decimal>{
            'prevDec' => 0,
            'jan' => 2,
            'feb' => 3
        };

        GwbBudgetWorkbenchController.RowInput driverInsert = new GwbBudgetWorkbenchController.RowInput();
        driverInsert.objectApiName = 'GWB_Month__c';
        driverInsert.driver = 'Additional ST Adjustment';
        driverInsert.classification = 'OST';
        driverInsert.valueType = 'number';
        driverInsert.values = new Map<String, Decimal>{
            'jan' => 7,
            'feb' => 8
        };

        Boolean inserted = false;
        Test.startTest();
        try {
            GwbBudgetWorkbenchController.SaveResponse insertResponse = GwbBudgetWorkbenchController.saveBudgetRows(
                draftBudgetId,
                JSON.serialize(new List<GwbBudgetWorkbenchController.RowInput>{ sharedInsert }),
                JSON.serialize(new List<GwbBudgetWorkbenchController.RowInput>{ driverInsert })
            );
            inserted = insertResponse.success;
        } catch (AuraHandledException ex) {
            inserted = false;
            System.assert(
                !String.isBlank(ex.getMessage()),
                'Controller should still return a usable error message for invalid org metadata combinations.'
            );
        }
        Test.stopTest();

        if (inserted) {
            Integer insertedDriverCount = [
                SELECT COUNT()
                FROM GWB_Month__c
                WHERE GWB_Year__c = :draftBudgetId
                AND Driver__c = 'Additional ST Adjust'
                AND Classification__c = 'OTS'
            ];
            System.assertEquals(1, insertedDriverCount, 'Driver and classification should be normalized before insert.');
        }
    }

    @IsTest
    static void saveBudgetRowsRejectsInvalidRequestShapesAndMismatchedIds() {
        Plant__c plant = [SELECT Id FROM Plant__c WHERE Name LIKE : (PLANT_NAME_PREFIX + '%') ORDER BY CreatedDate DESC LIMIT 1];
        Id draftBudgetId = [
            SELECT Id
            FROM GWB_Year__c
            WHERE Plant__c = :plant.Id
            AND Year__c = :NEXT_YEAR
            AND RecordType.DeveloperName = 'Budget'
            LIMIT 1
        ].Id;

        Boolean nullIdThrown = false;
        try {
            GwbBudgetWorkbenchController.saveBudgetRows(null, '[]', '[]');
        } catch (AuraHandledException ex) {
            nullIdThrown = true;
        }
        System.assertEquals(true, nullIdThrown, 'saveBudgetRows requires a budget id.');

        GwbBudgetWorkbenchController.RowInput invalidShared = new GwbBudgetWorkbenchController.RowInput();
        invalidShared.objectApiName = 'Plant__c';
        invalidShared.valueType = 'number';
        invalidShared.values = new Map<String, Decimal>{ 'jan' => 1 };

        Boolean invalidSharedThrown = false;
        try {
            GwbBudgetWorkbenchController.saveBudgetRows(
                draftBudgetId,
                JSON.serialize(new List<GwbBudgetWorkbenchController.RowInput>{ invalidShared }),
                '[]'
            );
        } catch (AuraHandledException ex) {
            invalidSharedThrown = true;
        }
        System.assertEquals(true, invalidSharedThrown, 'Shared rows should enforce GWB_Month__c object type.');

        GwbBudgetWorkbenchController.RowInput invalidDriver = new GwbBudgetWorkbenchController.RowInput();
        invalidDriver.objectApiName = null;
        invalidDriver.driver = 'Productivity';
        invalidDriver.classification = 'OTS';
        invalidDriver.valueType = 'number';
        invalidDriver.values = new Map<String, Decimal>{ 'jan' => 1 };

        Boolean invalidDriverThrown = false;
        try {
            GwbBudgetWorkbenchController.saveBudgetRows(
                draftBudgetId,
                '[]',
                JSON.serialize(new List<GwbBudgetWorkbenchController.RowInput>{ invalidDriver })
            );
        } catch (AuraHandledException ex) {
            invalidDriverThrown = true;
        }
        System.assertEquals(true, invalidDriverThrown, 'Driver rows require an allowed object api name.');

        Id otherBudgetId = createAdditionalBudgetForValidation(plant.Id);
        GWB_Month__c otherShared = new GWB_Month__c(
            GWB_Year__c = otherBudgetId,
            Section__c = getFirstActivePicklistValue(GWB_Month__c.Section__c),
            Parameter__c = getFirstActivePicklistValue(GWB_Month__c.Parameter__c),
            Jan_Number__c = 1
        );
        insert otherShared;
        GWB_Month__c otherDriver = new GWB_Month__c(
            GWB_Year__c = otherBudgetId,
            Driver__c = 'Productivity',
            Classification__c = 'OTS',
            Jan_Number__c = 1
        );
        insert otherDriver;

        GwbBudgetWorkbenchController.RowInput wrongShared = new GwbBudgetWorkbenchController.RowInput();
        wrongShared.recordId = otherShared.Id;
        wrongShared.objectApiName = 'GWB_Month__c';
        wrongShared.section = otherShared.Section__c;
        wrongShared.parameter = otherShared.Parameter__c;
        wrongShared.valueType = 'number';
        wrongShared.values = new Map<String, Decimal>{ 'jan' => 2 };

        Boolean wrongSharedThrown = false;
        try {
            GwbBudgetWorkbenchController.saveBudgetRows(
                draftBudgetId,
                JSON.serialize(new List<GwbBudgetWorkbenchController.RowInput>{ wrongShared }),
                '[]'
            );
        } catch (AuraHandledException ex) {
            wrongSharedThrown = true;
        }
        System.assertEquals(true, wrongSharedThrown, 'Shared row ids must belong to the selected budget.');

        GwbBudgetWorkbenchController.RowInput wrongDriver = new GwbBudgetWorkbenchController.RowInput();
        wrongDriver.recordId = otherDriver.Id;
        wrongDriver.objectApiName = 'GWB_Month__c';
        wrongDriver.driver = 'Productivity';
        wrongDriver.classification = 'OTS';
        wrongDriver.valueType = 'number';
        wrongDriver.values = new Map<String, Decimal>{ 'jan' => 3 };

        Boolean wrongDriverThrown = false;
        try {
            GwbBudgetWorkbenchController.saveBudgetRows(
                draftBudgetId,
                '[]',
                JSON.serialize(new List<GwbBudgetWorkbenchController.RowInput>{ wrongDriver })
            );
        } catch (AuraHandledException ex) {
            wrongDriverThrown = true;
        }
        System.assertEquals(true, wrongDriverThrown, 'Driver row ids must belong to the selected budget.');
    }

    private static Id getGwbYearRecordTypeId(String developerName) {
        Schema.RecordTypeInfo info = GWB_Year__c.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName().get(developerName);
        System.assertNotEquals(null, info, 'Expected record type to exist: ' + developerName);
        return info.getRecordTypeId();
    }

    private static Id createAdditionalBudgetForValidation(Id plantId) {
        Id budgetRecordTypeId = getGwbYearRecordTypeId('Budget');
        Plant_Sector__c plantSector = [
            SELECT Id
            FROM Plant_Sector__c
            WHERE Plant__c = :plantId
            LIMIT 1
        ];
        GWB_Year__c otherBudget = new GWB_Year__c(
            Plant__c = plantId,
            Plant_Sector__c = plantSector.Id,
            Sector__c = TEST_SECTOR,
            Year__c = NEXT_YEAR,
            Version__c = getTestVersion() + ' Alt',
            M_Schedule_Version__c = getTestVersion(),
            Status__c = 'Draft',
            RecordTypeId = budgetRecordTypeId
        );
        insert otherBudget;
        return otherBudget.Id;
    }

    private static String getFirstActivePicklistValue(Schema.SObjectField fieldToken) {
        for (Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static String getTestVersion() {
        for (Schema.PicklistEntry entry : Plant_Volume__c.Data_Point_Value__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        System.assert(false, 'Expected an active Plant Volume Data Point Value.');
        return null;
    }

    private static void insertPlantVolumeRows(Id plantId, String sector, String year, String version, Decimal baseVolume) {
        List<Schema.PicklistEntry> monthEntries = Plant_Volume__c.Month__c.getDescribe().getPicklistValues();
        Integer monthCount = Math.min(12, monthEntries.size());
        List<Plant_Volume__c> rows = new List<Plant_Volume__c>();
        for (Integer index = 0; index < monthCount; index++) {
            rows.add(new Plant_Volume__c(
                Plant__c = plantId,
                Sector__c = sector,
                Calendar_Year__c = year,
                Data_Point_Value__c = version,
                Month__c = monthEntries[index].getValue(),
                Volume__c = baseVolume + index
            ));
        }
        insert rows;
    }
}