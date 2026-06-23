@IsTest
private class GwbWorkbenchTestDataControllerTest {
    @TestSetup
    static void setupBypassSwitch() {
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        String switchObjectName = globalDescribe.containsKey('GWB_Switch__c')
            ? 'GWB_Switch__c'
            : (globalDescribe.containsKey('Onstar_Switch__c') ? 'Onstar_Switch__c' : null);
        if (switchObjectName == null) {
            return;
        }

        Schema.DescribeSObjectResult switchDescribe = globalDescribe.get(switchObjectName).getDescribe();
        Map<String, Schema.SObjectField> fieldsByName = switchDescribe.fields.getMap();
        SObject bypassRecord = globalDescribe.get(switchObjectName).newSObject();
        bypassRecord.put('SetupOwnerId', UserInfo.getUserId());
        for (String fieldName : fieldsByName.keySet()) {
            if (
                fieldName.toLowerCase().contains('bypass') &&
                fieldsByName.get(fieldName).getDescribe().getType() == Schema.DisplayType.Boolean &&
                fieldsByName.get(fieldName).getDescribe().isCreateable()
            ) {
                bypassRecord.put(fieldName, true);
            }
        }
        insert bypassRecord;
    }

    private static String uniqueLabel(String prefix) {
        return prefix + ' ' + String.valueOf(Crypto.getRandomInteger()).replace('-', '').right(6);
    }

    @IsTest
    static void createAndDeleteWorkbenchTestData() {
        String label = uniqueLabel('Harness UT');
        String sector = 'Assembly';
        String version = '3+9';

        Test.startTest();
        GwbWorkbenchTestDataController.HarnessResult created =
            GwbWorkbenchTestDataController.createWorkbenchTestData(label, sector, version, 12, 'Jun', 'Aug');
        Test.stopTest();

        System.assertEquals(true, created.success);
        System.assertNotEquals(null, created.plantId);
        System.assertNotEquals(null, created.plantSectorId);
        System.assertNotEquals(null, created.previousPublishedTargetId);
        System.assert(created.createdMonthRows > 20);
        System.assert(created.createdPlantVolumeRows > 0);
        System.assertNotEquals(null, created.vacationCoverageId);
        System.assertEquals(
            'Locked',
            [SELECT Status__c FROM GWB_Year__c WHERE Id = :created.previousPublishedTargetId].Status__c
        );

        GwbWorkbenchTestDataController.HarnessResult deleted =
            GwbWorkbenchTestDataController.deleteWorkbenchTestData(label, sector, version);

        System.assertEquals(true, deleted.success);
        System.assert(deleted.deletedYearCount >= 1);
        System.assert(deleted.deletedMonthCount >= 1);
    }

    @IsTest
    static void deleteWorkbenchTestData_noPlantFound() {
        GwbWorkbenchTestDataController.HarnessResult result =
            GwbWorkbenchTestDataController.deleteWorkbenchTestData('Missing Harness', 'Assembly', '3+9');
        System.assertEquals(true, result.success);
        System.assertEquals('No matching test plant found. Nothing to delete.', result.message);
    }

    @IsTest
    static void createWorkbenchTestData_defaultsBlankInputs() {
        GwbWorkbenchTestDataController.HarnessResult result =
            GwbWorkbenchTestDataController.createWorkbenchTestData('', '', '', null, null, null);
        System.assertEquals(true, result.success);
        System.assertNotEquals(null, result.plantId);
        System.assertNotEquals(null, result.previousPublishedTargetId);
        System.assert(result.createdMonthRows > 20);
    }

    @IsTest
    static void harnessOptionsAndSnapshot_workForExistingPlant() {
        String label = uniqueLabel('Snapshot UT');
        GwbWorkbenchTestDataController.HarnessResult created =
            GwbWorkbenchTestDataController.createWorkbenchTestData(label, 'Assembly', '3+9', 9.5, 'May', 'Jul');
        System.assertEquals(true, created.success);

        System.assertEquals(true, GwbWorkbenchTestDataController.canCurrentUserAccessHarness());

        List<GwbWorkbenchTestDataController.PlantOption> sectorOptions =
            GwbWorkbenchTestDataController.getHarnessSectorOptions();
        System.assert(!sectorOptions.isEmpty());
        Boolean foundAssembly = false;
        for (GwbWorkbenchTestDataController.PlantOption option : sectorOptions) {
            if (option.value == 'Assembly') {
                foundAssembly = true;
                break;
            }
        }
        System.assertEquals(true, foundAssembly);

        List<GwbWorkbenchTestDataController.PlantOption> options =
            GwbWorkbenchTestDataController.getHarnessPlantOptions('Assembly');
        System.assert(!options.isEmpty());

        List<GwbWorkbenchTestDataController.PlantOption> versionOptions =
            GwbWorkbenchTestDataController.getMScheduleVersionOptions();
        System.assert(!versionOptions.isEmpty());

        GwbWorkbenchTestDataController.HarnessSnapshot snapshot =
            GwbWorkbenchTestDataController.getHarnessDataSnapshot('WB Test - ' + label, 'Assembly', '3+9');
        System.assertEquals(true, snapshot.success);
        System.assertEquals('Assembly', snapshot.sector);
        System.assert(snapshot.currentYearTargetCount >= 1);
        System.assert(snapshot.plantVolumeRowCount >= 1);
        System.assert(!snapshot.currentYearTargets.isEmpty());
        System.assertNotEquals(null, snapshot.nextYearTargets);
        System.assert(!snapshot.previousPublishedMonthRows.isEmpty());
        System.assert(!snapshot.plantVolumeRows.isEmpty());
        System.assertEquals(1, snapshot.vacationCoverageCount);
        System.assertEquals('Locked', snapshot.previousPublishedTarget.status);
        System.assertEquals('May ' + String.valueOf(Date.today().year() + 1), snapshot.vacationCoverageRows[0].entryMonthYear);
        System.assertEquals('Jul ' + String.valueOf(Date.today().year() + 1), snapshot.vacationCoverageRows[0].exitMonthYear);
    }

    @IsTest
    static void createWorkbenchTestData_supportsPressAndSectorScopedPlantOptions() {
        String label = uniqueLabel('Press UT');
        GwbWorkbenchTestDataController.HarnessResult created =
            GwbWorkbenchTestDataController.createWorkbenchTestData(label, 'Press', '3+9', null, null, null);

        System.assertEquals(true, created.success);
        System.assert(created.createdMonthRows > 20, 'Press should seed metadata-driven target month rows.');
        System.assertEquals(null, created.vacationCoverageId, 'Non-Assembly harness runs should not create vacation coverage rows.');

        List<GwbWorkbenchTestDataController.PlantOption> options =
            GwbWorkbenchTestDataController.getHarnessPlantOptions('Press');
        Boolean foundPlant = false;
        for (GwbWorkbenchTestDataController.PlantOption option : options) {
            if (option.value == created.plantName) {
                foundPlant = true;
                break;
            }
        }
        System.assertEquals(true, foundPlant, 'The created Press plant should appear in the sector-aware plant options.');

        GwbWorkbenchTestDataController.HarnessSnapshot snapshot =
            GwbWorkbenchTestDataController.getHarnessDataSnapshot(created.plantName, 'Press', '3+9');
        System.assertEquals(true, snapshot.success);
        System.assertEquals('Press', snapshot.sector);
        System.assert(snapshot.currentYearTargetCount >= 1);
        System.assert(snapshot.plantVolumeRowCount >= 1);
    }
}