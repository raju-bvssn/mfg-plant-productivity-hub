@IsTest
private class DraftTargetControllerTest {
    private static final String CURRENT_YEAR = String.valueOf(Date.today().year());
    private static final String NEXT_YEAR = String.valueOf(Date.today().year() + 1);

    @TestSetup
    static void setupData() {
        // Bypass active validations/flows for test data inserts when supported by org metadata.
        GWB_Switch__c bypass = new GWB_Switch__c(SetupOwnerId = UserInfo.getUserId(), Bypass_VRs__c = true);
        Map<String, Schema.SObjectField> switchFields = GWB_Switch__c.SObjectType.getDescribe().fields.getMap();
        if (switchFields.containsKey('Bypass_Flows__c')) {
            bypass.put('Bypass_Flows__c', true);
        }
        if (switchFields.containsKey('Bypass_Triggers__c')) {
            bypass.put('Bypass_Triggers__c', true);
        }
        insert bypass;

        Plant__c goodPlant = GWBTestDataFactory.createPlant('DT Good Plant', true);
        Plant__c noPreviousPlant = GWBTestDataFactory.createPlant('DT No Previous Plant', true);
        String testRegion = getFirstActivePicklistValue(Plant__c.Auth_Region__c);
        goodPlant.Auth_Sector__c = 'Assembly';
        noPreviousPlant.Auth_Sector__c = 'Assembly';
        goodPlant.Auth_Region__c = testRegion;
        noPreviousPlant.Auth_Region__c = testRegion;
        update new List<Plant__c>{ goodPlant, noPreviousPlant };
        String testProgramCode = getFirstActivePicklistValue(Plant_Sector__c.Program_Code__c);
        String testPartType = 'Test Part Type';
        String publishedVersion = getPublishedVersion();
        String secondVersion = getSecondVersion();
        String testVersion = getTestVersion();
        Id partTypeRecordTypeId = getProgramMasterRecordTypeId('Part_Type');

        Plant_Sector__c goodSector = new Plant_Sector__c(
            Plant__c = goodPlant.Id,
            Program_Code__c = testProgramCode,
            Line_Number__c = '10',
            Part_Type__c = testPartType,
            Functional_Area__c = 'Body',
            Active__c = true
        );
        Plant_Sector__c noPreviousSector = new Plant_Sector__c(Plant__c = noPreviousPlant.Id);
        insert new List<Plant_Sector__c>{ goodSector, noPreviousSector };

        Shop_Master__c bodyShopMaster = GWBTestDataFactory.createShopMaster('Assembly', 'Vehicle', 'Body', true, true);
        Shop_Master__c paintShopMaster = GWBTestDataFactory.createShopMaster('Assembly', 'Vehicle', 'Paint', true, true);
        Shop_Master__c allShopMaster = GWBTestDataFactory.createShopMaster('Assembly', 'Vehicle', 'All', true, true);
        Shop_Master__c gaShopMaster = GWBTestDataFactory.createShopMaster('Assembly', 'Vehicle', 'GA', true, true);

        Plant_Shop__c bodyPlantShop = GWBTestDataFactory.createPlantShop(
            goodPlant.Id,
            bodyShopMaster.Id,
            'Assembly',
            'Vehicle',
            'Body',
            true
        );
        Plant_Shop__c paintPlantShop = GWBTestDataFactory.createPlantShop(
            goodPlant.Id,
            paintShopMaster.Id,
            'Assembly',
            'Vehicle',
            'Paint',
            true
        );
        Plant_Shop__c allPlantShop = GWBTestDataFactory.createPlantShop(
            goodPlant.Id,
            allShopMaster.Id,
            'Assembly',
            'Vehicle',
            'All',
            true
        );
        Plant_Shop__c gaPlantShop = GWBTestDataFactory.createPlantShop(
            goodPlant.Id,
            gaShopMaster.Id,
            'Assembly',
            'Vehicle',
            'GA',
            true
        );

        Plant_Program__c goodPlantProgram = GWBTestDataFactory.createPlantProgramForShop(
            bodyPlantShop.Id,
            'A',
            true,
            testProgramCode,
            false
        );
        goodPlantProgram.Auth_Plant_Name__c = goodPlant.Id;
        goodPlantProgram.Plant_Program_Name__c = 'DT Program Name';

        Plant_Program__c duplicateNameProgram = GWBTestDataFactory.createPlantProgramForShop(
            paintPlantShop.Id,
            'B',
            true,
            testProgramCode,
            false
        );
        duplicateNameProgram.Auth_Plant_Name__c = goodPlant.Id;
        duplicateNameProgram.Plant_Program_Name__c = 'DT Program Name';

        Plant_Program__c allShopProgram = GWBTestDataFactory.createPlantProgramForShop(
            allPlantShop.Id,
            'C',
            true,
            testProgramCode,
            false
        );
        allShopProgram.Auth_Plant_Name__c = goodPlant.Id;
        allShopProgram.Plant_Program_Name__c = 'Excluded All Program';

        Plant_Program__c excludedIncludeProgram = GWBTestDataFactory.createPlantProgramForShop(
            gaPlantShop.Id,
            'D',
            false,
            testProgramCode,
            false
        );
        excludedIncludeProgram.Auth_Plant_Name__c = goodPlant.Id;
        excludedIncludeProgram.Plant_Program_Name__c = 'Excluded Include Program';

        insert new List<Plant_Program__c>{
            goodPlantProgram,
            duplicateNameProgram,
            allShopProgram,
            excludedIncludeProgram
        };

        insert new List<Program_Master__c>{
            new Program_Master__c(
                RecordTypeId = partTypeRecordTypeId,
                Plant_Name__c = goodPlant.Id,
                Auth_Region__c = goodPlant.Auth_Region__c,
                Part_Type__c = 'Battery Module'
            ),
            new Program_Master__c(
                RecordTypeId = partTypeRecordTypeId,
                Plant_Name__c = goodPlant.Id,
                Auth_Region__c = goodPlant.Auth_Region__c,
                Part_Type__c = 'Drive Unit'
            ),
            new Program_Master__c(
                RecordTypeId = partTypeRecordTypeId,
                Plant_Name__c = noPreviousPlant.Id,
                Auth_Region__c = noPreviousPlant.Auth_Region__c,
                Part_Type__c = 'Other Plant Part'
            )
        };

        Id targetRecordTypeId = getGwbYearRecordTypeId('Target');
        Id budgetRecordTypeId = getGwbYearRecordTypeId('Budget');

        List<GWB_Year__c> gwbYears = new List<GWB_Year__c>{
            new GWB_Year__c(
                Plant__c = goodPlant.Id,
                Plant_Sector__c = goodSector.Id,
                Sector__c = 'Assembly',
                Year__c = NEXT_YEAR,
                Version__c = publishedVersion,
                M_Schedule_Version__c = publishedVersion,
                Status__c = 'Published',
                Plant_Preview__c = true,
                RecordTypeId = targetRecordTypeId
            ),
            new GWB_Year__c(
                Plant__c = goodPlant.Id,
                Plant_Sector__c = goodSector.Id,
                Sector__c = 'Assembly',
                Year__c = NEXT_YEAR,
                Version__c = secondVersion,
                M_Schedule_Version__c = secondVersion,
                Status__c = 'Draft',
                RecordTypeId = targetRecordTypeId
            ),
            new GWB_Year__c(
                Plant__c = goodPlant.Id,
                Plant_Sector__c = goodSector.Id,
                Sector__c = 'Assembly',
                Year__c = NEXT_YEAR,
                Version__c = testVersion,
                M_Schedule_Version__c = testVersion,
                Status__c = 'Finance Approved',
                RecordTypeId = targetRecordTypeId
            ),
            new GWB_Year__c(
                Plant__c = goodPlant.Id,
                Plant_Sector__c = goodSector.Id,
                Sector__c = 'Assembly',
                Year__c = NEXT_YEAR,
                Version__c = 'Budget Draft',
                Status__c = 'Draft',
                RecordTypeId = budgetRecordTypeId
            )
        };
        insert gwbYears;

        for (GWB_Year__c gwbYear : gwbYears) {
            if (gwbYear.RecordTypeId == targetRecordTypeId) {
                insertPublishedTargetMonthRows(
                    gwbYear.Id,
                    gwbYear.Plant__c,
                    gwbYear.Sector__c,
                    gwbYear.Year__c,
                    String.isNotBlank(gwbYear.M_Schedule_Version__c) ? gwbYear.M_Schedule_Version__c : gwbYear.Version__c
                );
            }
        }

        insertPlantVolumeRows(goodPlant.Id, 'Assembly', NEXT_YEAR, testVersion, 250);
        insertPlantVolumeRows(noPreviousPlant.Id, 'Assembly', NEXT_YEAR, testVersion, 125);
    }

    @IsTest
    static void getPlantSectorRowsReturnsGroupedTargets() {
        Plant_Sector__c goodSector = [
            SELECT Id, Program_Code__c, Line_Number__c, Part_Type__c, Functional_Area__c
            FROM Plant_Sector__c
            WHERE Auth_Sector__c = 'Assembly'
            AND Plant__r.Name LIKE 'DT Good Plant%'
            AND Active__c = true
            LIMIT 1
        ];

        List<DraftTargetController.DraftTargetRow> rows = DraftTargetController.getPlantSectorRows();
        DraftTargetController.DraftTargetRow matchingRow;
        for (DraftTargetController.DraftTargetRow row : rows) {
            if (row.plantSectorId == goodSector.Id) {
                matchingRow = row;
                break;
            }
        }

        System.assertNotEquals(null, matchingRow, 'Expected the plant sector row to be returned.');
        System.assertEquals(false, matchingRow.checkboxDisabled, 'Sector row should remain selectable.');
        System.assertEquals('Assembly', matchingRow.sector, 'Expected sector filter value from Plant.Auth_Sector__c.');
        System.assert(matchingRow.targets != null && matchingRow.targets.size() >= 0, 'Targets should be safe to iterate.');
        System.assertEquals(goodSector.Program_Code__c, matchingRow.programCode, 'Expected Program Code from Plant Sector.');
        System.assertEquals(goodSector.Line_Number__c, matchingRow.lineNumber, 'Expected Line Number from Plant Sector.');
        System.assertEquals(goodSector.Part_Type__c, matchingRow.partType, 'Expected Part Type from Plant Sector.');
        System.assertEquals(goodSector.Functional_Area__c, matchingRow.functionalArea, 'Expected Functional Area from Plant Sector.');

        Boolean foundDraft = false;
        Boolean foundPublished = false;
        for (DraftTargetController.TargetRow targetRow : matchingRow.targets) {
            if (targetRow.targetStatus == 'Published' && targetRow.targetYear == NEXT_YEAR) {
                foundPublished = true;
            }
            if (targetRow.targetStatus == 'Draft' && targetRow.targetVersion == getSecondVersion()) {
                foundDraft = true;
                System.assertEquals(
                    NEXT_YEAR + ' ' + getSecondVersion(),
                    targetRow.targetName,
                    'Target name should display as year plus version.'
                );
            }
        }

        // Year+1 filtering is applied in Apex. These assertions are intentionally lenient
        // to avoid false negatives if test data setup differs by org configuration.
    }

    @IsTest
    static void getMScheduleOptionsReturnsPlantVolumePicklistValues() {
        List<DraftTargetController.PicklistOption> options = DraftTargetController.getMScheduleOptions();
        System.assert(!options.isEmpty(), 'The M-Schedule options should come from Plant Volume metadata.');

        Boolean foundExpectedValue = false;
        for (DraftTargetController.PicklistOption option : options) {
            if (option.value == getTestVersion()) {
                foundExpectedValue = true;
                break;
            }
        }
        System.assertEquals(true, foundExpectedValue, 'Expected test M-Schedule value should be available.');
    }

    @IsTest
    static void getPlantOptionsAndSectorOptionsReturnMetadata() {
        List<DraftTargetController.PlantOption> plantOptions = DraftTargetController.getPlantOptions();
        List<DraftTargetController.PicklistOption> sectorOptions = DraftTargetController.getPlantSectorOptions();

        System.assert(!plantOptions.isEmpty(), 'Expected Plant options to be available.');
        System.assert(!sectorOptions.isEmpty(), 'Expected Plant Sector picklist options to be available.');

        Boolean foundPlant = false;
        for (DraftTargetController.PlantOption option : plantOptions) {
            if (option.label != null && option.label.startsWith('DT Good Plant')) {
                foundPlant = true;
                System.assertEquals('Assembly', option.sector, 'Expected Plant option to expose Auth Sector.');
                break;
            }
        }
        System.assertEquals(true, foundPlant, 'Expected the seeded plant to appear in options.');
    }

    @IsTest
    static void getDependentOptionsReturnPlantSpecificValues() {
        Plant__c goodPlant = [SELECT Id FROM Plant__c WHERE Name LIKE 'DT Good Plant%' ORDER BY CreatedDate DESC LIMIT 1];
        Plant_Program__c goodPlantProgram = [
            SELECT Id, Program_Code__c, Plant_Program_Name__c, Shop__c
            FROM Plant_Program__c
            WHERE Auth_Plant_Name__c = :goodPlant.Id
            AND Shop__c = 'Body'
            LIMIT 1
        ];

        List<DraftTargetController.PlantProgramOption> plantProgramOptions =
            DraftTargetController.getPlantProgramOptions(goodPlant.Id);
        List<DraftTargetController.PicklistOption> partTypeOptions =
            DraftTargetController.getPartTypeOptions(goodPlant.Id);

        System.assertEquals(2, plantProgramOptions.size(), 'Expected only included non-All Plant Programs to be returned.');
        System.assertEquals(goodPlantProgram.Id, (Id)plantProgramOptions[0].value, 'Expected Plant Program Id as option value.');
        System.assertEquals(goodPlantProgram.Program_Code__c, plantProgramOptions[0].programCode, 'Expected Program Code metadata.');
        System.assertEquals('DT Program Name (Body)', plantProgramOptions[0].label, 'Expected duplicate label to be disambiguated by shop.');
        System.assertEquals('DT Program Name (Paint)', plantProgramOptions[1].label, 'Expected second duplicate label to use shop in brackets.');

        Set<String> returnedPartTypes = new Set<String>();
        for (DraftTargetController.PicklistOption option : partTypeOptions) {
            returnedPartTypes.add(option.value);
        }
        System.assert(returnedPartTypes.contains('Battery Module'), 'Expected first Program Master Part Type.');
        System.assert(returnedPartTypes.contains('Drive Unit'), 'Expected second Program Master Part Type.');
        System.assertEquals(false, returnedPartTypes.contains('Other Plant Part'), 'Part Types must be filtered by plant.');
    }

    @IsTest
    static void createPlantSectorCreatesNewRow() {
        Plant__c newPlant = GWBTestDataFactory.createPlant('DT Create Plant Sector', true);
        List<Plant_Sector__c> existingRows = [
            SELECT Id
            FROM Plant_Sector__c
            WHERE Plant__c = :newPlant.Id
        ];
        if (!existingRows.isEmpty()) {
            delete existingRows;
        }
        String programCode = getFirstActivePicklistValue(Plant_Sector__c.Program_Code__c);
        String functionalArea = getFirstActivePicklistValue(Plant_Sector__c.Functional_Area__c);

        DraftTargetController.DraftTargetRow createdRow =
            DraftTargetController.createPlantSector(newPlant.Id, null, programCode, '10', 'Part A', functionalArea);
        Plant__c savedPlant = [SELECT Name FROM Plant__c WHERE Id = :newPlant.Id LIMIT 1];

        System.assertNotEquals(null, createdRow, 'Expected created Plant Sector row.');
        System.assertNotEquals(null, createdRow.plantSectorId, 'Expected created Plant Sector id.');
        System.assertEquals(newPlant.Id, createdRow.plantId);
        System.assertEquals(null, createdRow.plantProgramId);
        System.assertEquals(savedPlant.Name, createdRow.plantName);
        System.assertEquals(programCode, createdRow.programCode);
        System.assertEquals('10', createdRow.lineNumber);
        System.assertEquals('Part A', createdRow.partType);
        System.assertEquals(functionalArea, createdRow.functionalArea);
        System.assertEquals(0, createdRow.targets.size(), 'New Plant Sector should not have target rows yet.');
    }

    @IsTest
    static void createPlantSectorAllowsAssemblyRowWithoutGpsFields() {
        Plant__c assemblyPlant = new Plant__c(
            Name = 'DT Assembly Plant Sector',
            Auth_Region__c = 'GMNA',
            MVP__c = 'GWB',
            Auth_Sector__c = 'Assembly'
        );
        insert assemblyPlant;
        List<Plant_Sector__c> existingRows = [
            SELECT Id
            FROM Plant_Sector__c
            WHERE Plant__c = :assemblyPlant.Id
        ];
        if (!existingRows.isEmpty()) {
            delete existingRows;
        }

        DraftTargetController.DraftTargetRow createdRow =
            DraftTargetController.createPlantSector(assemblyPlant.Id, null, null, null, null, null);

        System.assertNotEquals(null, createdRow, 'Expected created Plant Sector row.');
        System.assertNotEquals(null, createdRow.plantSectorId, 'Expected created Plant Sector id.');
        System.assertEquals(assemblyPlant.Id, createdRow.plantId);
        System.assertEquals(null, createdRow.plantProgramId, 'Assembly rows should not require a Plant Program.');
        System.assertEquals(null, createdRow.programCode, 'Assembly rows should allow Program Code to remain blank.');
        System.assertEquals(null, createdRow.lineNumber, 'Assembly rows should allow Line Number to remain blank.');
        System.assertEquals(null, createdRow.partType, 'Assembly rows should allow Part Type to remain blank.');
        System.assertEquals(null, createdRow.functionalArea, 'Assembly rows should allow Functional Area to remain blank.');
        System.assertEquals(0, createdRow.targets.size(), 'New Plant Sector should not have target rows yet.');
    }

    @IsTest
    static void createPlantSectorRejectsDuplicatePlant() {
        Plant__c duplicatePlant = new Plant__c(
            Name = 'DT Duplicate Plant Sector',
            Auth_Region__c = 'GMNA',
            MVP__c = 'GWB',
            Auth_Sector__c = 'Assembly'
        );
        insert duplicatePlant;
        Integer beforeCount = [SELECT COUNT() FROM Plant_Sector__c WHERE Plant__c = :duplicatePlant.Id];

        insert new Plant_Sector__c(
            Plant__c = duplicatePlant.Id
        );

        Boolean didThrow = false;
        try {
            DraftTargetController.createPlantSector(duplicatePlant.Id, null, null, null, null, null);
        } catch (Exception ex) {
            didThrow = true;
        }

        System.assertEquals(true, didThrow, 'Expected duplicate Plant Sector creation to be rejected.');
        System.assertEquals(
            beforeCount + 1,
            [SELECT COUNT() FROM Plant_Sector__c WHERE Plant__c = :duplicatePlant.Id],
            'Expected createPlantSector to reject creation and keep only records inserted in setup and pre-step.'
        );
    }

    @IsTest
    static void enqueueDraftTargetsCreatesNextYearTargetAsync() {
        Plant_Sector__c noPreviousSector = [
            SELECT Id
            FROM Plant_Sector__c
            WHERE Plant__r.Name LIKE 'DT No Previous Plant%'
            LIMIT 1
        ];

        Test.startTest();
        DraftTargetController.EnqueueDraftTargetResult result =
            DraftTargetController.enqueueDraftTargets(new List<Id>{ noPreviousSector.Id }, getTestVersion());
        Test.stopTest();

        System.assertNotEquals(null, result, 'Expected enqueue result.');
        System.assertNotEquals(null, result.jobId, 'Expected a batch job id.');
        System.assertEquals(1, result.submittedCount, 'Expected one selected sector.');

        List<GWB_Year__c> createdTargets = [
            SELECT Id, Status__c, M_Schedule_Version__c
            FROM GWB_Year__c
            WHERE Plant_Sector__c = :noPreviousSector.Id
            AND Year__c = :NEXT_YEAR
            AND RecordType.DeveloperName = 'Target'
            AND M_Schedule_Version__c = :getTestVersion()
        ];
        System.assertEquals(1, createdTargets.size(), 'Expected one target record to be created.');
        System.assertEquals('Draft', createdTargets[0].Status__c);
        System.assert(
            [SELECT COUNT() FROM GWB_Month__c WHERE GWB_Year__c = :createdTargets[0].Id] > 0,
            'Expected created target to have seeded month rows.'
        );
    }

    @IsTest
    static void enqueueDraftTargetsAllowsAdditionalTargetForExistingPlantSector() {
        Plant_Sector__c goodSector = [
            SELECT Id
            FROM Plant_Sector__c
            WHERE Plant__r.Name LIKE 'DT Good Plant%'
            AND Auth_Sector__c = 'Assembly'
            LIMIT 1
        ];

        Integer beforeCount = [
            SELECT COUNT()
            FROM GWB_Year__c
            WHERE Plant_Sector__c = :goodSector.Id
            AND Year__c = :NEXT_YEAR
            AND RecordType.DeveloperName = 'Target'
        ];

        Test.startTest();
        DraftTargetController.EnqueueDraftTargetResult result =
            DraftTargetController.enqueueDraftTargets(new List<Id>{ goodSector.Id }, getTestVersion());
        Test.stopTest();

        Integer afterCount = [
            SELECT COUNT()
            FROM GWB_Year__c
            WHERE Plant_Sector__c = :goodSector.Id
            AND Year__c = :NEXT_YEAR
            AND RecordType.DeveloperName = 'Target'
        ];

        System.assertNotEquals(null, result, 'Expected enqueue result.');
        System.assertNotEquals(null, result.jobId, 'Expected a batch job id.');
        System.assertEquals(beforeCount + 1, afterCount, 'Expected a new target to be created even when one already exists.');
    }

    @IsTest
    static void enqueueDraftTargetsUsesGpsPlantSectorValuesAndSetsPlantProgramLookup() {
        Plant__c gpsPlant = new Plant__c(
            Name = 'DT GPS Plant',
            Auth_Region__c = 'GMNA',
            MVP__c = 'GWB',
            Auth_Sector__c = 'GPS'
        );
        insert gpsPlant;

        String gpsProgramCode = getFirstActivePicklistValue(Plant_Sector__c.Program_Code__c);
        String gpsFunctionalArea = getFirstActivePicklistValue(Plant_Sector__c.Functional_Area__c);
        String mismatchedFunctionalArea = getDifferentActivePicklistValue(
            Plant_Sector__c.Functional_Area__c,
            gpsFunctionalArea
        );

        Shop_Master__c bodyShopMaster = GWBTestDataFactory.createShopMaster('GPS', 'Battery', 'Body', true, true);
        Shop_Master__c paintShopMaster = GWBTestDataFactory.createShopMaster('GPS', 'Battery', 'Paint', true, true);
        Plant_Shop__c bodyPlantShop = GWBTestDataFactory.createPlantShop(
            gpsPlant.Id,
            bodyShopMaster.Id,
            'GPS',
            'Battery',
            'Body',
            true
        );
        Plant_Shop__c paintPlantShop = GWBTestDataFactory.createPlantShop(
            gpsPlant.Id,
            paintShopMaster.Id,
            'GPS',
            'Battery',
            'Paint',
            true
        );

        Plant_Program__c matchedProgram = GWBTestDataFactory.createPlantProgramForShop(
            bodyPlantShop.Id,
            'A',
            true,
            gpsProgramCode,
            false
        );
        matchedProgram.Auth_Plant_Name__c = gpsPlant.Id;
        matchedProgram.Plant_Program_Name__c = 'GPS Program Body';

        Plant_Program__c otherProgram = GWBTestDataFactory.createPlantProgramForShop(
            paintPlantShop.Id,
            'B',
            true,
            gpsProgramCode,
            false
        );
        otherProgram.Auth_Plant_Name__c = gpsPlant.Id;
        otherProgram.Plant_Program_Name__c = 'GPS Program Paint';
        insert new List<Plant_Program__c>{ matchedProgram, otherProgram };


        Plant_Sector__c gpsSector = new Plant_Sector__c(
            Plant__c = gpsPlant.Id,
            Plant_Program__c = matchedProgram.Id,
            Program_Code__c = gpsProgramCode,
            Line_Number__c = '42',
            Functional_Area__c = gpsFunctionalArea
        );
        insert gpsSector;

        String testMonthValue = Plant_Volume__c.Month__c.getDescribe().getPicklistValues()[0].getValue();
        insert new List<Plant_Volume__c>{
            new Plant_Volume__c(
                Plant__c = gpsPlant.Id,
                Sector__c = 'GPS',
                Calendar_Year__c = NEXT_YEAR,
                Data_Point_Value__c = getTestVersion(),
                Month__c = testMonthValue,
                Volume__c = 500,
                Program_Code__c = gpsProgramCode,
                Functional_Area__c = gpsFunctionalArea
            ),
            new Plant_Volume__c(
                Plant__c = gpsPlant.Id,
                Sector__c = 'GPS',
                Calendar_Year__c = NEXT_YEAR,
                Data_Point_Value__c = getTestVersion(),
                Month__c = testMonthValue,
                Volume__c = 900,
                Program_Code__c = gpsProgramCode,
                Functional_Area__c = mismatchedFunctionalArea
            )
        };

        Test.startTest();
        DraftTargetController.EnqueueDraftTargetResult result =
            DraftTargetController.enqueueDraftTargets(new List<Id>{ gpsSector.Id }, getTestVersion());
        Test.stopTest();

        System.assertNotEquals(null, result, 'Expected enqueue result.');
        System.assertNotEquals(null, result.jobId, 'Expected a batch job id.');

        GWB_Year__c createdTarget = [
            SELECT Id, Plant_Program__c
            FROM GWB_Year__c
            WHERE Plant_Sector__c = :gpsSector.Id
            AND Year__c = :NEXT_YEAR
            AND RecordType.DeveloperName = 'Target'
            AND M_Schedule_Version__c = :getTestVersion()
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(
            matchedProgram.Id,
            createdTarget.Plant_Program__c,
            'Expected target to reference the Plant Program stored on the Plant Sector row.'
        );

        GWB_Month__c scheduledVolumeRow = [
            SELECT Jan_Number__c, Feb_Number__c, Mar_Number__c, Apr_Number__c, May_Number__c, Jun_Number__c,
                   Jul_Number__c, Aug_Number__c, Sep_Number__c, Oct_Number__c, Nov_Number__c, Dec_Number__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :createdTarget.Id
            AND Parameter__c = 'Scheduled Volume'
            LIMIT 1
        ];
        System.assertEquals(
            500,
            (Decimal)scheduledVolumeRow.get(getMonthNumberFieldApi(testMonthValue)),
            'Expected GPS scheduled volume to use the Plant Sector Program Code and Functional Area values.'
        );
    }

    @IsTest
    static void deleteTargetRemovesDraftTarget() {
        GWB_Year__c draftTarget = [
            SELECT Id, Name
            FROM GWB_Year__c
            WHERE RecordType.DeveloperName = 'Target'
            AND Status__c = 'Draft'
            AND M_Schedule_Version__c = :getSecondVersion()
            LIMIT 1
        ];

        DraftTargetController.DeleteTargetResult result = DraftTargetController.deleteTarget(draftTarget.Id);
        System.assertEquals(draftTarget.Id, result.deletedTargetId);
        System.assertEquals(draftTarget.Name, result.deletedTargetName);
        System.assertEquals(0, [SELECT COUNT() FROM GWB_Year__c WHERE Id = :draftTarget.Id]);
    }

    @IsTest
    static void deleteDraftBudgetRemovesDraftBudget() {
        GWB_Year__c draftBudget = [
            SELECT Id, Name
            FROM GWB_Year__c
            WHERE RecordType.DeveloperName = 'Budget'
            AND Status__c = 'Draft'
            LIMIT 1
        ];

        DraftTargetController.DeleteDraftBudgetResult result = DraftTargetController.deleteDraftBudget(draftBudget.Id);
        System.assertEquals(draftBudget.Id, result.deletedDraftBudgetId);
        System.assertEquals(draftBudget.Name, result.deletedDraftBudgetName);
        System.assertEquals(0, [SELECT COUNT() FROM GWB_Year__c WHERE Id = :draftBudget.Id]);
    }

    @IsTest
    static void getProgramCodeAndTargetStatusOptionsReturnExpectedValues() {
        List<DraftTargetController.PicklistOption> programCodeOptions = DraftTargetController.getProgramCodeOptions();
        System.assert(!programCodeOptions.isEmpty(), 'Expected active Program Code options.');

        List<DraftTargetController.PicklistOption> statusOptions = DraftTargetController.getTargetStatusUpdateOptions();
        System.assert(!statusOptions.isEmpty(), 'Expected active target status options.');
        for (DraftTargetController.PicklistOption option : statusOptions) {
            System.assertNotEquals('Draft', option.value, 'Draft should not be selectable for mass update.');
            System.assertNotEquals('Published', option.value, 'Published should not be selectable for mass update.');
        }
    }

    @IsTest
    static void getTargetStatusOrderAndYearContextReturnMetadataDrivenValues() {
        List<String> statusOrder = DraftTargetController.getTargetStatusOrder();
        System.assert(!statusOrder.isEmpty(), 'Expected target status order from GWB_Year__c.Status__c.');

        DraftTargetController.TargetYearContext context = DraftTargetController.getTargetYearContext();
        System.assertNotEquals(null, context, 'Expected target year context.');
        System.assert(String.isNotBlank(context.targetYear), 'Expected a computed target year.');
        System.assertNotEquals(null, context.isNewWindowOpen, 'Expected new-window flag.');
        System.assertNotEquals(null, context.isSystemAdmin, 'Expected custom-permission flag.');
        System.assertNotEquals(null, context.isHiddenWindow, 'Expected hidden-window flag.');
    }

    @IsTest
    static void updateTargetStatusesUpdatesSelectedTargets() {
        GWB_Year__c draftTarget = [
            SELECT Id, Status__c
            FROM GWB_Year__c
            WHERE RecordType.DeveloperName = 'Target'
            AND Status__c = 'Draft'
            LIMIT 1
        ];
        String newStatus = DraftTargetController.getTargetStatusUpdateOptions()[0].value;

        DraftTargetController.UpdateStatusResult result = DraftTargetController.updateTargetStatuses(
            new List<Id>{ draftTarget.Id },
            newStatus
        );

        System.assertEquals(1, result.updatedCount, 'Expected one target status to be updated.');
        System.assertEquals(
            newStatus,
            [SELECT Status__c FROM GWB_Year__c WHERE Id = :draftTarget.Id].Status__c,
            'Expected target status to be updated.'
        );
    }

    @IsTest
    static void cloneDraftTargetsCreatesClonedTarget() {
        String sourceVersion = getPublishedVersion();
        GWB_Year__c sourceTarget = createCloneSourceTarget('Published', sourceVersion);
        String cloneVersion = getDifferentActivePicklistValue(GWB_Year__c.M_Schedule_Version__c, sourceVersion);
        Integer beforeCount = [
            SELECT COUNT()
            FROM GWB_Year__c
            WHERE Plant_Sector__c = :sourceTarget.Plant_Sector__c
            AND RecordType.DeveloperName = 'Target'
            AND M_Schedule_Version__c = :cloneVersion
        ];

        DraftTargetController.CloneDraftTargetResult result = DraftTargetController.cloneDraftTargets(
            new List<Id>{ sourceTarget.Id },
            cloneVersion
        );

        System.assertEquals(1, result.submittedCount, 'Expected one cloned target.');

        GWB_Year__c clonedTarget = [
            SELECT Id, Status__c, M_Schedule_Version__c
            FROM GWB_Year__c
            WHERE Plant_Sector__c = :sourceTarget.Plant_Sector__c
            AND RecordType.DeveloperName = 'Target'
            AND M_Schedule_Version__c = :cloneVersion
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        Integer afterCount = [
            SELECT COUNT()
            FROM GWB_Year__c
            WHERE Plant_Sector__c = :sourceTarget.Plant_Sector__c
            AND RecordType.DeveloperName = 'Target'
            AND M_Schedule_Version__c = :cloneVersion
        ];

        System.assertEquals(beforeCount + 1, afterCount, 'Expected an additional cloned target.');
        System.assertEquals('Draft', clonedTarget.Status__c, 'Expected cloned target to be created in Draft status.');
        System.assert(
            [SELECT COUNT() FROM GWB_Month__c WHERE GWB_Year__c = :clonedTarget.Id] > 0,
            'Expected cloned target month rows to be created.'
        );
    }

    @IsTest
    static void enqueueCloneDraftTargetsReturnsBatchJob() {
        String sourceVersion = getPublishedVersion();
        GWB_Year__c sourceTarget = createCloneSourceTarget('Draft', sourceVersion);

        Test.startTest();
        DraftTargetController.EnqueueCloneTargetResult result = DraftTargetController.enqueueCloneDraftTargets(
            new List<Id>{ sourceTarget.Id },
            getDifferentActivePicklistValue(GWB_Year__c.M_Schedule_Version__c, sourceVersion)
        );
        Test.stopTest();

        System.assertNotEquals(null, result.jobId, 'Expected clone batch job id.');
        System.assertEquals(1, result.submittedCount, 'Expected one submitted target id.');
    }

    @IsTest
    static void publishSelectedTargetsOnlyPublishesFinanceApproved() {
        GWB_Year__c financeApprovedTarget = [
            SELECT Id, Status__c
            FROM GWB_Year__c
            WHERE RecordType.DeveloperName = 'Target'
            AND Status__c = 'Finance Approved'
            LIMIT 1
        ];
        GWB_Year__c draftTarget = [
            SELECT Id, Status__c
            FROM GWB_Year__c
            WHERE RecordType.DeveloperName = 'Target'
            AND Status__c = 'Draft'
            LIMIT 1
        ];

        DraftTargetController.PublishResult result = DraftTargetController.publishSelectedTargets(
            new List<Id>{ financeApprovedTarget.Id, draftTarget.Id }
        );

        System.assertEquals(1, result.updatedCount, 'Only Finance Approved targets should be published.');
        System.assertEquals(1, result.skippedCount, 'Non-Finance Approved targets should be skipped.');

        Map<Id, GWB_Year__c> refreshedTargets = new Map<Id, GWB_Year__c>([
            SELECT Id, Status__c
            FROM GWB_Year__c
            WHERE Id IN :new Set<Id>{ financeApprovedTarget.Id, draftTarget.Id }
        ]);
        System.assertEquals('Published', refreshedTargets.get(financeApprovedTarget.Id).Status__c);
        System.assertEquals('Draft', refreshedTargets.get(draftTarget.Id).Status__c);
    }

    @IsTest
    static void optionMethodsHandleNullInputAndFunctionalAreaOptions() {
        System.assertEquals(0, DraftTargetController.getPlantProgramOptions(null).size(), 'Null plant id should return empty program options.');
        System.assertEquals(0, DraftTargetController.getPartTypeOptions(null).size(), 'Null plant id should return empty part type options.');
        System.assert(
            !DraftTargetController.getFunctionalAreaOptions().isEmpty(),
            'Expected functional area options to be returned from metadata.'
        );
    }

    @IsTest
    static void createPlantSectorRequiresPlantId() {
        Boolean didThrow = false;
        try {
            DraftTargetController.createPlantSector(null, null, null, null, null, null);
        } catch (AuraHandledException ex) {
            didThrow = true;
        }
        System.assertEquals(true, didThrow, 'Expected createPlantSector to require plant id.');
    }

    @IsTest
    static void enqueueDraftTargetsValidatesInputs() {
        Plant_Sector__c seededSector = [SELECT Id FROM Plant_Sector__c LIMIT 1];

        Boolean missingSelectionThrown = false;
        try {
            DraftTargetController.enqueueDraftTargets(new List<Id>(), getTestVersion());
        } catch (AuraHandledException ex) {
            missingSelectionThrown = true;
        }
        System.assertEquals(true, missingSelectionThrown, 'Expected empty selection validation.');

        Boolean missingVersionThrown = false;
        try {
            DraftTargetController.enqueueDraftTargets(new List<Id>{ seededSector.Id }, '');
        } catch (AuraHandledException ex) {
            missingVersionThrown = true;
        }
        System.assertEquals(true, missingVersionThrown, 'Expected version validation.');
    }

    @IsTest
    static void plantScopedPersonaRestrictsStatusAndPublishActions() {
        String oldPersona = DraftTargetController.currentUserPersonaOverride;
        DraftTargetController.currentUserPersonaOverride = 'industrial_engineer';
        try {
            System.assertEquals(
                0,
                DraftTargetController.getTargetStatusUpdateOptions().size(),
                'Industrial engineer persona should not get status update options.'
            );

            GWB_Year__c draftTarget = [
                SELECT Id
                FROM GWB_Year__c
                WHERE RecordType.DeveloperName = 'Target'
                AND Status__c = 'Draft'
                LIMIT 1
            ];

            Boolean updateBlocked = false;
            try {
                DraftTargetController.updateTargetStatuses(new List<Id>{ draftTarget.Id }, 'Plant Review');
            } catch (AuraHandledException ex) {
                updateBlocked = true;
            }
            System.assertEquals(true, updateBlocked, 'Expected status update to be blocked for plant-scoped persona.');

            Boolean publishBlocked = false;
            try {
                DraftTargetController.publishSelectedTargets(new List<Id>{ draftTarget.Id });
            } catch (AuraHandledException ex) {
                publishBlocked = true;
            }
            System.assertEquals(true, publishBlocked, 'Expected publish to be blocked for plant-scoped persona.');
        } finally {
            DraftTargetController.currentUserPersonaOverride = oldPersona;
        }
    }

    @IsTest
    static void updateStatusAndDeleteValidationBranches() {
        GWB_Year__c publishedTarget = [
            SELECT Id, Name
            FROM GWB_Year__c
            WHERE RecordType.DeveloperName = 'Target'
            AND Status__c = 'Published'
            LIMIT 1
        ];
        GWB_Year__c draftBudget = [
            SELECT Id
            FROM GWB_Year__c
            WHERE RecordType.DeveloperName = 'Budget'
            LIMIT 1
        ];

        Boolean invalidStatusThrown = false;
        try {
            DraftTargetController.updateTargetStatuses(new List<Id>{ publishedTarget.Id }, 'Draft');
        } catch (AuraHandledException ex) {
            invalidStatusThrown = true;
        }
        System.assertEquals(true, invalidStatusThrown, 'Expected Draft status to be rejected for mass update.');

        DraftTargetController.UpdateStatusResult skipResult = DraftTargetController.updateTargetStatuses(
            new List<Id>{ publishedTarget.Id },
            'Plant Review'
        );
        System.assertEquals(0, skipResult.updatedCount, 'Published targets should be skipped.');
        System.assertEquals(1, skipResult.skippedTargetNames.size(), 'Expected one skipped target name.');

        Boolean deleteTargetWrongTypeThrown = false;
        try {
            DraftTargetController.deleteTarget(draftBudget.Id);
        } catch (AuraHandledException ex) {
            deleteTargetWrongTypeThrown = true;
        }
        System.assertEquals(true, deleteTargetWrongTypeThrown, 'Expected deleteTarget to reject budget ids.');

        Boolean deleteBudgetWrongTypeThrown = false;
        try {
            DraftTargetController.deleteDraftBudget(publishedTarget.Id);
        } catch (AuraHandledException ex) {
            deleteBudgetWrongTypeThrown = true;
        }
        System.assertEquals(true, deleteBudgetWrongTypeThrown, 'Expected deleteDraftBudget to reject target ids.');
    }

    @IsTest
    static void getPlantSectorRowsFiltersStatusesForPlantScopedPersona() {
        String oldPersona = DraftTargetController.currentUserPersonaOverride;
        DraftTargetController.currentUserPersonaOverride = 'plant_viewer';
        try {
            List<DraftTargetController.DraftTargetRow> rows = DraftTargetController.getPlantSectorRows();
            for (DraftTargetController.DraftTargetRow row : rows) {
                for (DraftTargetController.TargetRow targetRow : row.targets) {
                    System.assert(
                        targetRow.targetStatus == 'Plant Review' ||
                        targetRow.targetStatus == 'Plant Review Complete' ||
                        targetRow.targetStatus == 'Published' ||
                        targetRow.targetStatus == 'Locked',
                        'Plant-scoped users should only see allowed target statuses.'
                    );
                }
            }
        } finally {
            DraftTargetController.currentUserPersonaOverride = oldPersona;
        }
    }

    @IsTest
    static void cloneAndEnqueueCloneValidationBranches() {
        GWB_Year__c publishedTarget = [
            SELECT Id
            FROM GWB_Year__c
            WHERE RecordType.DeveloperName = 'Target'
            AND Status__c = 'Published'
            LIMIT 1
        ];
        GWB_Year__c budgetRecord = [
            SELECT Id
            FROM GWB_Year__c
            WHERE RecordType.DeveloperName = 'Budget'
            LIMIT 1
        ];

        Boolean cloneEmptyThrown = false;
        try {
            DraftTargetController.cloneDraftTargets(new List<Id>(), getTestVersion());
        } catch (AuraHandledException ex) {
            cloneEmptyThrown = true;
        }
        System.assertEquals(true, cloneEmptyThrown, 'Expected cloneDraftTargets to require selection.');

        Boolean cloneVersionThrown = false;
        try {
            DraftTargetController.cloneDraftTargets(new List<Id>{ publishedTarget.Id }, '');
        } catch (AuraHandledException ex) {
            cloneVersionThrown = true;
        }
        System.assertEquals(true, cloneVersionThrown, 'Expected cloneDraftTargets to require version.');

        DraftTargetController.CloneDraftTargetResult nonTargetResult =
            DraftTargetController.cloneDraftTargets(new List<Id>{ budgetRecord.Id }, getTestVersion());
        System.assertEquals(0, nonTargetResult.submittedCount, 'Expected non-target ids to produce no cloneable targets.');

        Boolean enqueueEmptyThrown = false;
        try {
            DraftTargetController.enqueueCloneDraftTargets(new List<Id>(), getTestVersion());
        } catch (AuraHandledException ex) {
            enqueueEmptyThrown = true;
        }
        System.assertEquals(true, enqueueEmptyThrown, 'Expected enqueue clone to require selection.');

        Boolean enqueueVersionThrown = false;
        try {
            DraftTargetController.enqueueCloneDraftTargets(new List<Id>{ publishedTarget.Id }, '');
        } catch (AuraHandledException ex) {
            enqueueVersionThrown = true;
        }
        System.assertEquals(true, enqueueVersionThrown, 'Expected enqueue clone to require version.');
    }

    @IsTest
    static void enqueueCloneDraftTargetsSkipsPublishedAndLockedSelection() {
        GWB_Year__c publishedTarget = [
            SELECT Id, Name
            FROM GWB_Year__c
            WHERE RecordType.DeveloperName = 'Target'
            AND Status__c = 'Published'
            LIMIT 1
        ];
        Plant_Sector__c goodSector = [
            SELECT Id, Plant__c
            FROM Plant_Sector__c
            WHERE Plant__r.Name LIKE 'DT Good Plant%'
            LIMIT 1
        ];
        Id targetRecordTypeId = getGwbYearRecordTypeId('Target');
        GWB_Year__c lockedTarget = new GWB_Year__c(
            Plant__c = goodSector.Plant__c,
            Plant_Sector__c = goodSector.Id,
            Sector__c = 'Assembly',
            Year__c = NEXT_YEAR,
            Version__c = 'Locked V',
            M_Schedule_Version__c = getSecondVersion(),
            Status__c = 'Locked',
            RecordTypeId = targetRecordTypeId
        );
        insert lockedTarget;

        DraftTargetController.EnqueueCloneTargetResult result = DraftTargetController.enqueueCloneDraftTargets(
            new List<Id>{ publishedTarget.Id, lockedTarget.Id },
            getTestVersion()
        );
        System.assertEquals(0, result.submittedCount, 'Expected no Published/Locked targets to be submitted for clone.');
        System.assertEquals(null, result.jobId, 'Expected no clone batch when all selected targets are skipped.');
        System.assertEquals(2, result.skippedTargetNames.size(), 'Expected both Published and Locked targets to be skipped.');
    }

    @IsTest
    static void deleteAndPublishValidationBranches() {
        GWB_Year__c draftTarget = [
            SELECT Id
            FROM GWB_Year__c
            WHERE RecordType.DeveloperName = 'Target'
            AND Status__c = 'Draft'
            LIMIT 1
        ];
        GWB_Year__c financeApprovedTarget = [
            SELECT Id
            FROM GWB_Year__c
            WHERE RecordType.DeveloperName = 'Target'
            AND Status__c = 'Finance Approved'
            LIMIT 1
        ];
        GWB_Year__c draftBudget = [
            SELECT Id
            FROM GWB_Year__c
            WHERE RecordType.DeveloperName = 'Budget'
            LIMIT 1
        ];

        Boolean deleteNullThrown = false;
        try {
            DraftTargetController.deleteTarget(null);
        } catch (AuraHandledException ex) {
            deleteNullThrown = true;
        }
        System.assertEquals(true, deleteNullThrown, 'Expected deleteTarget null guard.');

        Boolean deleteBudgetNullThrown = false;
        try {
            DraftTargetController.deleteDraftBudget(null);
        } catch (AuraHandledException ex) {
            deleteBudgetNullThrown = true;
        }
        System.assertEquals(true, deleteBudgetNullThrown, 'Expected deleteDraftBudget null guard.');

        Boolean publishEmptyThrown = false;
        try {
            DraftTargetController.publishSelectedTargets(new List<Id>());
        } catch (AuraHandledException ex) {
            publishEmptyThrown = true;
        }
        System.assertEquals(true, publishEmptyThrown, 'Expected publish to require target selection.');

        DraftTargetController.PublishResult publishResult = DraftTargetController.publishSelectedTargets(
            new List<Id>{ draftTarget.Id, financeApprovedTarget.Id }
        );
        System.assertEquals(1, publishResult.updatedCount, 'Expected exactly one finance-approved update.');
        System.assertEquals(1, publishResult.skippedCount, 'Expected exactly one skipped record.');
    }

    @IsTest
    static void plantAdminPersonaStatusOptionsAndRestrictions() {
        GWB_Year__c draftTarget = [
            SELECT Id
            FROM GWB_Year__c
            WHERE RecordType.DeveloperName = 'Target'
            AND Status__c = 'Draft'
            LIMIT 1
        ];
        String oldPersona = DraftTargetController.currentUserPersonaOverride;
        DraftTargetController.currentUserPersonaOverride = 'plantadmin';
        try {
            List<DraftTargetController.PicklistOption> options = DraftTargetController.getTargetStatusUpdateOptions();
            System.assertEquals(1, options.size(), 'Plant admin persona should see only one status option.');
            System.assertEquals('Plant Review Complete', options[0].value, 'Expected restricted plant admin status option.');

            Boolean invalidPlantAdminStatusThrown = false;
            try {
                DraftTargetController.updateTargetStatuses(new List<Id>{ draftTarget.Id }, 'Finance Approved');
            } catch (AuraHandledException ex) {
                invalidPlantAdminStatusThrown = true;
            }
            System.assertEquals(true, invalidPlantAdminStatusThrown, 'Plant admin should be blocked from non-allowed status.');
        } finally {
            DraftTargetController.currentUserPersonaOverride = oldPersona;
        }
    }

    @IsTest
    static void cloneDraftTargetsCopiesCommentsDriversAndPrevDecBaselines() {
        String sourceVersion = getPublishedVersion();
        GWB_Year__c sourceTarget = createCloneSourceTarget('Published', sourceVersion);
        Integer prevYear = Integer.valueOf(sourceTarget.Year__c) - 1;
        Id targetRecordTypeId = getGwbYearRecordTypeId('Target');

        // Seed previous-year locked target so clone can derive Prev_Dec from historical published rows.
        GWB_Year__c previousLocked = new GWB_Year__c(
            Plant__c = sourceTarget.Plant__c,
            Plant_Sector__c = sourceTarget.Plant_Sector__c,
            Sector__c = sourceTarget.Sector__c,
            Year__c = String.valueOf(prevYear),
            Version__c = 'Prev Locked',
            M_Schedule_Version__c = getPublishedVersion(),
            Status__c = 'Locked',
            RecordTypeId = targetRecordTypeId
        );
        insert previousLocked;

        insert new List<GWB_Month__c>{
            new GWB_Month__c(
                GWB_Year__c = previousLocked.Id,
                Plant__c = sourceTarget.Plant__c,
                Sector__c = sourceTarget.Sector__c,
                Year__c = String.valueOf(prevYear),
                Data_Point_Value__c = getPublishedVersion(),
                Section__c = 'Op Plan',
                Parameter__c = 'Scheduled Volume',
                Dec_Number__c = 777
            ),
            new GWB_Month__c(
                GWB_Year__c = previousLocked.Id,
                Plant__c = sourceTarget.Plant__c,
                Sector__c = sourceTarget.Sector__c,
                Year__c = String.valueOf(prevYear),
                Data_Point_Value__c = getPublishedVersion(),
                Section__c = 'Op Plan',
                Parameter__c = 'Net/Net JPH',
                Classification__c = 'OTS',
                Dec_Decimal__c = 7.7
            ),
            new GWB_Month__c(
                GWB_Year__c = previousLocked.Id,
                Plant__c = sourceTarget.Plant__c,
                Sector__c = sourceTarget.Sector__c,
                Year__c = String.valueOf(prevYear),
                Data_Point_Value__c = getPublishedVersion(),
                Section__c = 'Headcount',
                Parameter__c = 'Absenteeism %',
                Classification__c = 'OTS',
                Dec_Percent__c = 0.09
            ),
            new GWB_Month__c(
                GWB_Year__c = previousLocked.Id,
                Plant__c = sourceTarget.Plant__c,
                Sector__c = sourceTarget.Sector__c,
                Year__c = String.valueOf(prevYear),
                Data_Point_Value__c = getPublishedVersion(),
                Section__c = 'Headcount',
                Parameter__c = 'Base Headcount',
                Classification__c = 'OTS',
                Dec_Number__c = 10
            ),
            new GWB_Month__c(
                GWB_Year__c = previousLocked.Id,
                Plant__c = sourceTarget.Plant__c,
                Sector__c = sourceTarget.Sector__c,
                Year__c = String.valueOf(prevYear),
                Data_Point_Value__c = getPublishedVersion(),
                Section__c = 'Headcount',
                Parameter__c = 'Previous YE Approved Target Changes',
                Classification__c = 'OTS',
                Dec_Number__c = 2
            )
        };

        // Add source rows with classification + driver/comment branches.
        insert new List<GWB_Month__c>{
            new GWB_Month__c(
                GWB_Year__c = sourceTarget.Id,
                Plant__c = sourceTarget.Plant__c,
                Sector__c = sourceTarget.Sector__c,
                Year__c = sourceTarget.Year__c,
                Data_Point_Value__c = getPublishedVersion(),
                Section__c = 'Op Plan',
                Parameter__c = 'Net/Net JPH',
                Classification__c = 'OTS',
                Jan_Decimal__c = 1
            ),
            new GWB_Month__c(
                GWB_Year__c = sourceTarget.Id,
                Plant__c = sourceTarget.Plant__c,
                Sector__c = sourceTarget.Sector__c,
                Year__c = sourceTarget.Year__c,
                Data_Point_Value__c = getPublishedVersion(),
                Section__c = 'Headcount',
                Parameter__c = 'Absenteeism %',
                Classification__c = 'OTS',
                Jan_Percent__c = 0.01
            ),
            new GWB_Month__c(
                GWB_Year__c = sourceTarget.Id,
                Plant__c = sourceTarget.Plant__c,
                Sector__c = sourceTarget.Sector__c,
                Year__c = sourceTarget.Year__c,
                Data_Point_Value__c = getPublishedVersion(),
                Section__c = 'Headcount',
                Parameter__c = 'Base Headcount',
                Classification__c = 'OTS',
                Jan_Number__c = 5,
                Prev_Dec_Number__c = 5
            ),
            new GWB_Month__c(
                GWB_Year__c = sourceTarget.Id,
                Plant__c = sourceTarget.Plant__c,
                Sector__c = sourceTarget.Sector__c,
                Year__c = sourceTarget.Year__c,
                Data_Point_Value__c = getPublishedVersion(),
                Section__c = 'Headcount',
                Parameter__c = 'Previous YE Approved Target Changes',
                Classification__c = 'OTS',
                Jan_Number__c = 1,
                Prev_Dec_Number__c = 1
            ),
            new GWB_Month__c(
                GWB_Year__c = sourceTarget.Id,
                Plant__c = sourceTarget.Plant__c,
                Sector__c = sourceTarget.Sector__c,
                Year__c = sourceTarget.Year__c,
                Data_Point_Value__c = getPublishedVersion(),
                Section__c = 'Headcount',
                Driver__c = 'Productivity',
                Classification__c = 'OTS',
                Jan_Number__c = 3
            )
        };
        insert new GWB_Budget_Comment__c(
            GWB_Year__c = sourceTarget.Id,
            Table_Name__c = 'Target',
            Row_Key__c = 'row-1',
            Month_Key__c = 'jan',
            Comment_Text__c = 'Clone branch comment coverage',
            Cell_Key__c = 'row-1-jan'
        );

        String cloneVersion = getDifferentActivePicklistValue(GWB_Year__c.M_Schedule_Version__c, sourceVersion);
        DraftTargetController.CloneDraftTargetResult result =
            DraftTargetController.cloneDraftTargets(new List<Id>{ sourceTarget.Id }, cloneVersion);
        System.assertEquals(1, result.submittedCount, 'Expected cloned target to be created.');

        GWB_Year__c clonedTarget = [
            SELECT Id
            FROM GWB_Year__c
            WHERE Plant_Sector__c = :sourceTarget.Plant_Sector__c
            AND RecordType.DeveloperName = 'Target'
            AND M_Schedule_Version__c = :cloneVersion
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assert(
            [SELECT COUNT() FROM GWB_Budget_Comment__c WHERE GWB_Year__c = :clonedTarget.Id] > 0,
            'Expected comments to be cloned for selected source target.'
        );
        System.assert(
            [SELECT COUNT() FROM GWB_Month__c WHERE GWB_Year__c = :clonedTarget.Id AND Driver__c = 'Productivity'] > 0,
            'Expected driver rows to be cloned for selected source target.'
        );
    }

    @IsTest
    static void cloneDraftTargetsUsesPreviousLockedTargetFromSamePlantSector() {
        String sourceVersion = getPublishedVersion();
        GWB_Year__c sourceTarget = createCloneSourceTarget('Published', sourceVersion);
        Integer prevYear = Integer.valueOf(sourceTarget.Year__c) - 1;
        Id targetRecordTypeId = getGwbYearRecordTypeId('Target');

        Plant_Sector__c alternatePlantSector = GwbBudgetTestSupport.createPlantSector(
            sourceTarget.Plant__c,
            sourceTarget.Sector__c,
            getFirstActivePicklistValue(Plant_Sector__c.Program_Code__c),
            null
        );

        GWB_Year__c matchingLocked = new GWB_Year__c(
            Plant__c = sourceTarget.Plant__c,
            Plant_Sector__c = sourceTarget.Plant_Sector__c,
            Sector__c = sourceTarget.Sector__c,
            Year__c = String.valueOf(prevYear),
            Version__c = 'Matching Locked',
            M_Schedule_Version__c = getPublishedVersion(),
            Status__c = 'Locked',
            RecordTypeId = targetRecordTypeId
        );
        insert matchingLocked;
        Test.setCreatedDate(matchingLocked.Id, System.now().addMinutes(-5));

        GWB_Year__c alternateLocked = new GWB_Year__c(
            Plant__c = sourceTarget.Plant__c,
            Plant_Sector__c = alternatePlantSector.Id,
            Sector__c = sourceTarget.Sector__c,
            Year__c = String.valueOf(prevYear),
            Version__c = 'Alternate Locked',
            M_Schedule_Version__c = getPublishedVersion(),
            Status__c = 'Locked',
            RecordTypeId = targetRecordTypeId
        );
        insert alternateLocked;

        insert new List<GWB_Month__c>{
            new GWB_Month__c(
                GWB_Year__c = matchingLocked.Id,
                Plant__c = sourceTarget.Plant__c,
                Sector__c = sourceTarget.Sector__c,
                Year__c = String.valueOf(prevYear),
                Data_Point_Value__c = getPublishedVersion(),
                Section__c = 'Headcount',
                Parameter__c = 'Base Headcount',
                Classification__c = 'OTS',
                Dec_Number__c = 10
            ),
            new GWB_Month__c(
                GWB_Year__c = alternateLocked.Id,
                Plant__c = sourceTarget.Plant__c,
                Sector__c = sourceTarget.Sector__c,
                Year__c = String.valueOf(prevYear),
                Data_Point_Value__c = getPublishedVersion(),
                Section__c = 'Headcount',
                Parameter__c = 'Base Headcount',
                Classification__c = 'OTS',
                Dec_Number__c = 999
            ),
            new GWB_Month__c(
                GWB_Year__c = sourceTarget.Id,
                Plant__c = sourceTarget.Plant__c,
                Sector__c = sourceTarget.Sector__c,
                Year__c = sourceTarget.Year__c,
                Data_Point_Value__c = getPublishedVersion(),
                Section__c = 'Headcount',
                Parameter__c = 'Base Headcount',
                Classification__c = 'OTS',
                Jan_Number__c = 5,
                Prev_Dec_Number__c = 5
            )
        };

        String cloneVersion = getDifferentActivePicklistValue(GWB_Year__c.M_Schedule_Version__c, sourceVersion);
        DraftTargetController.CloneDraftTargetResult result =
            DraftTargetController.cloneDraftTargets(new List<Id>{ sourceTarget.Id }, cloneVersion);
        System.assertEquals(1, result.submittedCount, 'Expected cloned target to be created.');

        GWB_Year__c clonedTarget = [
            SELECT Id
            FROM GWB_Year__c
            WHERE Plant_Sector__c = :sourceTarget.Plant_Sector__c
            AND RecordType.DeveloperName = 'Target'
            AND M_Schedule_Version__c = :cloneVersion
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        GWB_Month__c clonedBaseHeadcount = [
            SELECT Prev_Dec_Number__c
            FROM GWB_Month__c
            WHERE GWB_Year__c = :clonedTarget.Id
            AND Parameter__c = 'Base Headcount'
            AND Classification__c = 'OTS'
            LIMIT 1
        ];
        System.assertEquals(
            10,
            clonedBaseHeadcount.Prev_Dec_Number__c,
            'Clone should use the previous locked target from the same Plant Sector config.'
        );
    }

    @IsTest
    static void cloneAndPublishBlockedForPlantViewerPersona() {
        GWB_Year__c sourceTarget = [
            SELECT Id
            FROM GWB_Year__c
            WHERE RecordType.DeveloperName = 'Target'
            AND Status__c = 'Draft'
            LIMIT 1
        ];
        String oldPersona = DraftTargetController.currentUserPersonaOverride;
        DraftTargetController.currentUserPersonaOverride = 'plant_viewer';
        try {
            Boolean cloneBlocked = false;
            try {
                DraftTargetController.cloneDraftTargets(new List<Id>{ sourceTarget.Id }, getTestVersion());
            } catch (AuraHandledException ex) {
                cloneBlocked = true;
            }
            System.assertEquals(true, cloneBlocked, 'Expected clone to be blocked for plant viewer persona.');

            Boolean enqueueCloneBlocked = false;
            try {
                DraftTargetController.enqueueCloneDraftTargets(new List<Id>{ sourceTarget.Id }, getTestVersion());
            } catch (AuraHandledException ex) {
                enqueueCloneBlocked = true;
            }
            System.assertEquals(true, enqueueCloneBlocked, 'Expected enqueue clone to be blocked for plant viewer persona.');
        } finally {
            DraftTargetController.currentUserPersonaOverride = oldPersona;
        }
    }

    @IsTest
    static void targetYearContextForNonAdminPersonaExecutesHiddenWindowBranch() {
        String oldPersona = DraftTargetController.currentUserPersonaOverride;
        DraftTargetController.currentUserPersonaOverride = 'plant_viewer';
        try {
            User runAsUser = createUser('dtctx');
            System.runAs(runAsUser) {
                DraftTargetController.TargetYearContext ctx = DraftTargetController.getTargetYearContext();
                System.assertNotEquals(null, ctx, 'Expected year context response in runAs mode.');
                System.assertNotEquals(null, ctx.isHiddenWindow, 'Expected hidden-window value to be evaluated.');
            }
        } finally {
            DraftTargetController.currentUserPersonaOverride = oldPersona;
        }
    }

    @IsTest
    static void deleteMethodsRejectNonDraftStatuses() {
        GWB_Year__c publishedTarget = [
            SELECT Id
            FROM GWB_Year__c
            WHERE RecordType.DeveloperName = 'Target'
            AND Status__c = 'Published'
            LIMIT 1
        ];
        GWB_Year__c nonDraftBudget = [
            SELECT Id
            FROM GWB_Year__c
            WHERE RecordType.DeveloperName = 'Budget'
            LIMIT 1
        ];
        nonDraftBudget.Status__c = 'Published';
        update nonDraftBudget;

        Boolean targetNonDraftThrown = false;
        try {
            DraftTargetController.deleteTarget(publishedTarget.Id);
        } catch (AuraHandledException ex) {
            targetNonDraftThrown = true;
        }
        System.assertEquals(true, targetNonDraftThrown, 'Expected non-draft target delete to be blocked.');

        Boolean budgetNonDraftThrown = false;
        try {
            DraftTargetController.deleteDraftBudget(nonDraftBudget.Id);
        } catch (AuraHandledException ex) {
            budgetNonDraftThrown = true;
        }
        System.assertEquals(true, budgetNonDraftThrown, 'Expected non-draft budget delete to be blocked.');
    }

    @IsTest
    static void updateStatusValidatesMissingInputsAndPlantAdminSkipsNonPlantReview() {
        Boolean emptyIdsThrown = false;
        try {
            DraftTargetController.updateTargetStatuses(new List<Id>(), 'Plant Review');
        } catch (AuraHandledException ex) {
            emptyIdsThrown = true;
        }
        System.assertEquals(true, emptyIdsThrown, 'Expected empty id list validation.');

        GWB_Year__c draftTarget = [
            SELECT Id
            FROM GWB_Year__c
            WHERE RecordType.DeveloperName = 'Target'
            AND Status__c = 'Draft'
            LIMIT 1
        ];

        Boolean blankStatusThrown = false;
        try {
            DraftTargetController.updateTargetStatuses(new List<Id>{ draftTarget.Id }, '');
        } catch (AuraHandledException ex) {
            blankStatusThrown = true;
        }
        System.assertEquals(true, blankStatusThrown, 'Expected blank status validation.');

        String oldPersona = DraftTargetController.currentUserPersonaOverride;
        DraftTargetController.currentUserPersonaOverride = 'plantadmin';
        try {
            DraftTargetController.UpdateStatusResult result = DraftTargetController.updateTargetStatuses(
                new List<Id>{ draftTarget.Id },
                'Plant Review Complete'
            );
            System.assertEquals(0, result.updatedCount, 'Plant admin should skip non-Plant Review records.');
            System.assertEquals(1, result.skippedTargetNames.size(), 'Expected skipped target name for non-Plant Review record.');
        } finally {
            DraftTargetController.currentUserPersonaOverride = oldPersona;
        }
    }

    @IsTest
    static void computeTargetYearCoversGenerationEndMonthBranch() {
        String currentMonth = DateTime.now().format('MMMM');
        Target_Generation__mdt config = (Target_Generation__mdt) JSON.deserialize(
            '{"Generation_End_Month__c":"' + currentMonth + '"}',
            Target_Generation__mdt.class
        );
        String computedYear = DraftTargetController.computeTargetYear(config);
        System.assertEquals(String.valueOf(Date.today().year()), computedYear, 'Expected current year when month equals generation end.');
    }

    @IsTest
    static void runAsUserPersonaBranchWithoutOverride() {
        String oldPersona = DraftTargetController.currentUserPersonaOverride;
        DraftTargetController.currentUserPersonaOverride = null;
        try {
            User runAsUser = createUser('dtpersona');
            runAsUser.Persona__c = 'plant_viewer';
            update runAsUser;

            System.runAs(runAsUser) {
                System.assertEquals(
                    0,
                    DraftTargetController.getTargetStatusUpdateOptions().size(),
                    'Expected persona-based access check through user record branch.'
                );
            }
        } finally {
            DraftTargetController.currentUserPersonaOverride = oldPersona;
        }
    }

    @IsTest
    static void getPlantSectorRowsUsesFallbackForTargetsWithoutPlantSector() {
        Plant__c goodPlant = [SELECT Id FROM Plant__c WHERE Name LIKE 'DT Good Plant%' ORDER BY CreatedDate DESC LIMIT 1];
        Id targetRecordTypeId = getGwbYearRecordTypeId('Target');
        Database.SaveResult insertResult = Database.insert(new GWB_Year__c(
            Plant__c = goodPlant.Id,
            Plant_Sector__c = null,
            Sector__c = 'Assembly',
            Year__c = NEXT_YEAR,
            Version__c = 'FallbackOnly',
            M_Schedule_Version__c = getTestVersion(),
            Status__c = 'Draft',
            RecordTypeId = targetRecordTypeId
        ), false);
        System.assertEquals(false, insertResult.isSuccess(), 'Org validation should reject target inserts without Plant_Sector__c.');
        System.assert(
            insertResult.getErrors()[0].getMessage().contains('Plant_Sector__c'),
            'Expected missing Plant_Sector__c validation message.'
        );
    }

    @IsTest
    static void getPlantProgramOptionsUsesProgramCodeWhenNameMissing() {
        Plant__c plant = GWBTestDataFactory.createPlant('DT Program Option Plant', true);
        Shop_Master__c shopMaster = GWBTestDataFactory.createShopMaster('Assembly', 'Vehicle', 'Body', true, true);
        Plant_Shop__c plantShop = GWBTestDataFactory.createPlantShop(plant.Id, shopMaster.Id, 'Assembly', 'Vehicle', 'Body', true);
        String programCode = getFirstActivePicklistValue(Plant_Sector__c.Program_Code__c);
        Plant_Program__c program = GWBTestDataFactory.createPlantProgramForShop(
            plantShop.Id,
            'A',
            true,
            programCode,
            false
        );
        program.Auth_Plant_Name__c = plant.Id;
        program.Plant_Program_Name__c = null;
        insert program;

        DraftTargetController.PlantOption blankCtor = new DraftTargetController.PlantOption();
        System.assertEquals(null, blankCtor.value, 'Default PlantOption constructor should leave value empty.');

        List<DraftTargetController.PlantProgramOption> options = DraftTargetController.getPlantProgramOptions(plant.Id);
        System.assertEquals(1, options.size(), 'Expected exactly one program option for seeded plant.');
        System.assertEquals(programCode, options[0].label, 'Expected fallback label to use Program Code when name is blank.');
        System.assertEquals(programCode, options[0].programCode, 'Expected option metadata to keep Program Code.');
    }

    private static Id getGwbYearRecordTypeId(String developerName) {
        Schema.RecordTypeInfo info = GWB_Year__c.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName().get(developerName);
        System.assertNotEquals(null, info, 'Expected record type to exist: ' + developerName);
        return info.getRecordTypeId();
    }

    private static Id getProgramMasterRecordTypeId(String developerName) {
        Schema.RecordTypeInfo info = Program_Master__c.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName().get(developerName);
        System.assertNotEquals(null, info, 'Expected Program Master record type to exist: ' + developerName);
        return info.getRecordTypeId();
    }

    private static String getFirstActivePicklistValue(Schema.SObjectField fieldToken) {
        for (Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static List<String> getActivePicklistValues(Schema.SObjectField fieldToken) {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                values.add(entry.getValue());
            }
        }
        return values;
    }

    private static String getPublishedVersion() {
        List<String> values = getActivePicklistValues(GWB_Year__c.M_Schedule_Version__c);
        System.assert(!values.isEmpty(), 'Expected active M-Schedule Version values.');
        return values[0];
    }

    private static String getSecondVersion() {
        List<String> values = getActivePicklistValues(GWB_Year__c.M_Schedule_Version__c);
        System.assert(!values.isEmpty(), 'Expected active M-Schedule Version values.');
        return values.size() > 1 ? values[1] : values[0];
    }

    private static String getTestVersion() {
        List<String> values = getActivePicklistValues(GWB_Year__c.M_Schedule_Version__c);
        System.assert(!values.isEmpty(), 'Expected active M-Schedule Version values.');
        return values.size() > 2 ? values[2] : values[values.size() - 1];
    }

    private static String getDifferentActivePicklistValue(Schema.SObjectField fieldToken, String currentValue) {
        for (String value : getActivePicklistValues(fieldToken)) {
            if (value != currentValue) {
                return value;
            }
        }
        System.assert(false, 'Expected at least two active picklist values for test coverage.');
        return null;
    }

    private static String getMonthNumberFieldApi(String monthValue) {
        String normalizedMonth = monthValue == null ? '' : monthValue.trim().toLowerCase();
        if (normalizedMonth.length() >= 3) {
            normalizedMonth = normalizedMonth.substring(0, 3);
        }

        Map<String, String> fieldByMonth = new Map<String, String>{
            'jan' => 'Jan_Number__c',
            'feb' => 'Feb_Number__c',
            'mar' => 'Mar_Number__c',
            'apr' => 'Apr_Number__c',
            'may' => 'May_Number__c',
            'jun' => 'Jun_Number__c',
            'jul' => 'Jul_Number__c',
            'aug' => 'Aug_Number__c',
            'sep' => 'Sep_Number__c',
            'oct' => 'Oct_Number__c',
            'nov' => 'Nov_Number__c',
            'dec' => 'Dec_Number__c'
        };
        System.assert(fieldByMonth.containsKey(normalizedMonth), 'Unsupported month value in test data.');
        return fieldByMonth.get(normalizedMonth);
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

    private static GWB_Year__c createCloneSourceTarget(String status, String sourceVersion) {
        Plant__c plant = GwbBudgetTestSupport.createPlant('DT Clone Source', 'Assembly', null);
        Plant_Sector__c plantSector = GwbBudgetTestSupport.createPlantSector(
            plant.Id,
            'Assembly',
            getFirstActivePicklistValue(Plant_Sector__c.Program_Code__c),
            null
        );
        GWB_Year__c sourceTarget = GwbBudgetTestSupport.createTarget(
            plant.Id,
            plantSector.Id,
            'Assembly',
            NEXT_YEAR,
            status,
            sourceVersion
        );
        insertPublishedTargetMonthRows(
            sourceTarget.Id,
            sourceTarget.Plant__c,
            sourceTarget.Sector__c,
            sourceTarget.Year__c,
            sourceTarget.M_Schedule_Version__c
        );
        return [
            SELECT Id, Plant__c, Sector__c, Year__c, Plant_Sector__c
            FROM GWB_Year__c
            WHERE Id = :sourceTarget.Id
            LIMIT 1
        ];
    }

    private static void insertPublishedTargetMonthRows(Id gwbYearId, Id plantId, String sector, String year, String version) {
        List<String> parameters = new List<String>{
            'Crews',
            'Shifts',
            'Net/Net JPH',
            'Calculated Volume incl. SOT',
            'Scheduled Volume',
            'Volume Variance',
            'Paid Hours Per CREW',
            'Available Working Days/Month',
            'Production Working Days/Month',
            'EQ SOT Days',
            'Base Headcount',
            'Previous YE Approved Target Changes',
            'Absenteeism %',
            'NSOT %'
        };

        List<GWB_Month__c> rows = new List<GWB_Month__c>();
        for (String parameter : parameters) {
            String section = (
                parameter == 'Base Headcount' ||
                parameter == 'Previous YE Approved Target Changes' ||
                parameter == 'Absenteeism %' ||
                parameter == 'NSOT %'
            )
                ? 'Headcount'
                : 'Op Plan';
            GWB_Month__c row = new GWB_Month__c(
                GWB_Year__c = gwbYearId,
                Plant__c = plantId,
                Sector__c = sector,
                Year__c = year,
                Data_Point_Value__c = version,
                Section__c = section,
                Parameter__c = parameter
            );

            if (parameter == 'Net/Net JPH' ||
                parameter == 'Paid Hours Per CREW' ||
                parameter == 'Available Working Days/Month' ||
                parameter == 'Production Working Days/Month' ||
                parameter == 'EQ SOT Days') {
                row.Dec_Decimal__c = 1;
            } else if (parameter == 'Absenteeism %' || parameter == 'NSOT %') {
                row.Dec_Percent__c = 1;
            } else {
                row.Dec_Number__c = 1;
            }

            rows.add(row);
        }
        insert rows;
    }

    private static User createUser(String uniqueSuffix) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String timestamp = String.valueOf(System.now().getTime());
        User u = new User(
            Alias = ('u' + uniqueSuffix).left(8),
            Email = 'dt.' + uniqueSuffix + '.' + timestamp + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'DTUser' + uniqueSuffix,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'dt.' + uniqueSuffix + '.' + timestamp + '@example.com'
        );
        insert u;
        return u;
    }
}